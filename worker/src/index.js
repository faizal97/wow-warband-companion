/**
 * WoW Companion Auth Proxy — Cloudflare Worker
 *
 * Exchanges Battle.net OAuth authorization codes for access tokens,
 * keeping the client secret server-side.
 *
 * Also serves as a commodities price proxy: fetches the full Blizzard
 * commodities dump (~20-30MB), processes it into a compact price index,
 * and caches it in KV so mobile clients only download what they need.
 *
 * Secrets (set via `wrangler secret put`):
 *   BNET_CLIENT_ID
 *   BNET_CLIENT_SECRET
 *
 * KV namespace binding: CACHE
 */

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

const REGION_API_BASES = {
  us: 'https://us.api.blizzard.com',
  eu: 'https://eu.api.blizzard.com',
  kr: 'https://kr.api.blizzard.com',
  tw: 'https://tw.api.blizzard.com',
  cn: 'https://gateway.battlenet.com.cn',
};

export default {
  async fetch(request, env) {
    // Handle CORS preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }

    const url = new URL(request.url);

    if (url.pathname === '/token' && request.method === 'POST') {
      return handleTokenExchange(request, env);
    }

    if (url.pathname === '/commodities/prices' && request.method === 'GET') {
      return handleCommoditiesPrices(request, env);
    }

    if (url.pathname.startsWith('/wago/') && request.method === 'GET') {
      return handleWagoProxy(request, env);
    }

    if (url.pathname.startsWith('/news/') && request.method === 'GET') {
      return handleNews(request, env);
    }

    if (url.pathname === '/image-proxy' && request.method === 'GET') {
      return handleImageProxy(request, env);
    }

    // Health check
    if (url.pathname === '/' && request.method === 'GET') {
      return json({ status: 'ok', service: 'wow-companion-auth' });
    }

    return json({ error: 'Not found' }, 404);
  },
};

// ---------------------------------------------------------------------------
// Token exchange (existing)
// ---------------------------------------------------------------------------

async function handleTokenExchange(request, env) {
  try {
    const body = await request.json();
    const { code, redirect_uri } = body;

    if (!code || !redirect_uri) {
      return json({ error: 'Missing code or redirect_uri' }, 400);
    }

    const credentials = btoa(`${env.BNET_CLIENT_ID}:${env.BNET_CLIENT_SECRET}`);

    const tokenResponse = await fetch('https://oauth.battle.net/token', {
      method: 'POST',
      headers: {
        'Authorization': `Basic ${credentials}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({
        grant_type: 'authorization_code',
        code,
        redirect_uri,
      }),
    });

    const data = await tokenResponse.json();

    if (!tokenResponse.ok) {
      return json({ error: 'Token exchange failed', details: data }, tokenResponse.status);
    }

    // Only return the access token, not the full response
    return json({ access_token: data.access_token });
  } catch (e) {
    return json({ error: 'Internal error' }, 500);
  }
}

// ---------------------------------------------------------------------------
// Commodities prices endpoint
// ---------------------------------------------------------------------------

async function handleCommoditiesPrices(request, env) {
  try {
    const url = new URL(request.url);
    const itemsParam = url.searchParams.get('items');
    const region = url.searchParams.get('region') || 'us';

    if (!itemsParam) {
      return json({ error: 'Missing required query parameter: items' }, 400);
    }

    const itemIds = itemsParam.split(',').map((id) => id.trim()).filter(Boolean);

    if (itemIds.length === 0) {
      return json({ error: 'Missing required query parameter: items' }, 400);
    }

    if (itemIds.length > 100) {
      return json({ error: 'Too many items requested (max 100)' }, 400);
    }

    if (!REGION_API_BASES[region]) {
      return json({ error: `Invalid region: ${region}` }, 400);
    }

    const data = await getCommoditiesIndex(region, env);
    const index = data.index || data; // backwards compat with old cache format
    const lastUpdated = data.last_updated || null;

    const prices = {};
    for (const id of itemIds) {
      if (index[id]) {
        prices[id] = index[id];
      }
    }

    return json({ prices, last_updated: lastUpdated });
  } catch (e) {
    return json({ error: 'Failed to fetch commodities prices' }, 500);
  }
}

// ---------------------------------------------------------------------------
// Client-credentials token helper
// ---------------------------------------------------------------------------

async function getClientToken(env) {
  // Check KV cache first
  const cached = await env.CACHE.get('bnet_client_token');
  if (cached) {
    return cached;
  }

  const credentials = btoa(`${env.BNET_CLIENT_ID}:${env.BNET_CLIENT_SECRET}`);

  const response = await fetch('https://oauth.battle.net/token', {
    method: 'POST',
    headers: {
      'Authorization': `Basic ${credentials}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams({ grant_type: 'client_credentials' }),
  });

  if (!response.ok) {
    throw new Error(`Client token request failed: ${response.status}`);
  }

  const data = await response.json();
  const token = data.access_token;
  const ttl = Math.max(data.expires_in - 3600, 60);

  await env.CACHE.put('bnet_client_token', token, { expirationTtl: ttl });

  return token;
}

// ---------------------------------------------------------------------------
// Commodities fetch + process logic
// ---------------------------------------------------------------------------

async function getCommoditiesIndex(region, env) {
  const cacheKey = `commodities_${region}`;

  // Check KV cache first
  const cached = await env.CACHE.get(cacheKey, { type: 'json' });
  if (cached) {
    return cached;
  }

  const token = await getClientToken(env);
  const apiBase = REGION_API_BASES[region];

  const response = await fetch(
    `${apiBase}/data/wow/auctions/commodities?namespace=dynamic-${region}`,
    {
      headers: { 'Authorization': `Bearer ${token}` },
    },
  );

  if (!response.ok) {
    throw new Error(`Commodities API request failed: ${response.status}`);
  }

  const data = await response.json();
  const auctions = data.auctions || [];

  // Build price index: { itemId: { min_price, total_quantity } }
  const index = {};
  for (const auction of auctions) {
    const itemId = auction.item?.id;
    if (!itemId) continue;
    const unitPrice = auction.unit_price || 0;
    const quantity = auction.quantity || 0;

    const entry = index[itemId];
    if (entry) {
      if (unitPrice < entry.min_price) {
        entry.min_price = unitPrice;
      }
      entry.total_quantity += quantity;
    } else {
      index[itemId] = { min_price: unitPrice, total_quantity: quantity };
    }
  }

  // Use Blizzard's Last-Modified if available, otherwise current time
  const lastModified = response.headers.get('Last-Modified');
  const lastUpdated = lastModified
    ? new Date(lastModified).getTime()
    : Date.now();

  const cached_data = { index, last_updated: lastUpdated };

  // Cache the processed data for 1 hour
  await env.CACHE.put(cacheKey, JSON.stringify(cached_data), { expirationTtl: 3600 });

  return cached_data;
}

// ---------------------------------------------------------------------------
// Wago DB2 proxy (CORS bypass + KV caching)
// ---------------------------------------------------------------------------

// Allowed Wago DB2 tables (whitelist to prevent abuse)
const ALLOWED_WAGO_TABLES = new Set([
  'Mount', 'MountXDisplay', 'PlayerCondition', 'CurrencyTypes',
  'JournalEncounter', 'JournalEncounterItem', 'JournalInstance',
]);

async function handleWagoProxy(request, env) {
  try {
    const url = new URL(request.url);
    // Path: /wago/Mount/csv → table = Mount
    const parts = url.pathname.replace('/wago/', '').split('/');
    const table = parts[0];

    if (!ALLOWED_WAGO_TABLES.has(table)) {
      return json({ error: `Table not allowed: ${table}` }, 403);
    }

    const cacheKey = `wago_${table}`;

    // Check KV cache (24h TTL)
    const cached = await env.CACHE.get(cacheKey);
    if (cached) {
      return new Response(cached, {
        status: 200,
        headers: { 'Content-Type': 'text/csv', ...CORS_HEADERS },
      });
    }

    // Fetch from Wago
    const wagoUrl = `https://wago.tools/db2/${table}/csv`;
    const response = await fetch(wagoUrl);

    if (!response.ok) {
      return json({ error: `Wago returned ${response.status}` }, 502);
    }

    const body = await response.text();

    // Cache in KV for 24 hours
    await env.CACHE.put(cacheKey, body, { expirationTtl: 86400 });

    return new Response(body, {
      status: 200,
      headers: { 'Content-Type': 'text/csv', ...CORS_HEADERS },
    });
  } catch (e) {
    return json({ error: 'Wago proxy error' }, 500);
  }
}

// ---------------------------------------------------------------------------
// News aggregation endpoints
// ---------------------------------------------------------------------------

const NEWS_CACHE_TTL = 1800; // 30 minutes
const ARTICLE_CACHE_TTL = 86400; // 24 hours

async function handleNews(request, env) {
  const url = new URL(request.url);
  const path = url.pathname.replace('/news/', '');

  try {
    switch (path) {
      case 'blizzard':
        return await fetchBlizzardNews(env);
      case 'wowhead':
        return await fetchWowheadNews(env);
      case 'mmochampion':
        return await fetchMMOChampionNews(env);
      case 'icyveins':
        return await fetchIcyVeinsNews(env);
      case 'reddit':
        return await fetchRedditPosts(env);
      case 'article':
        return await fetchArticleContent(url, env);
      default:
        return json({ error: `Unknown news source: ${path}` }, 404);
    }
  } catch (e) {
    return json({ error: `News fetch failed: ${e.message}` }, 500);
  }
}

// --- Blizzard News ---
async function fetchBlizzardNews(env) {
  const cacheKey = 'news_blizzard';
  const cached = await env.CACHE.get(cacheKey);
  if (cached) {
    return new Response(cached, {
      headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
    });
  }

  const response = await fetch('https://worldofwarcraft.blizzard.com/en-us/news', {
    headers: { 'User-Agent': 'WoWCompanion/1.0' },
  });

  if (!response.ok) {
    return json({ error: `Blizzard returned ${response.status}` }, 502);
  }

  const html = await response.text();
  const articles = parseBlizzardNews(html);
  const result = JSON.stringify(articles);

  await env.CACHE.put(cacheKey, result, { expirationTtl: NEWS_CACHE_TTL });

  return new Response(result, {
    headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
  });
}

function parseBlizzardNews(html) {
  const articles = [];

  // The Blizzard news page embeds data in a JS variable: model = { ... }
  // It contains masthead.features[] and blogList.blogs[]
  const modelMatch = html.match(/model\s*=\s*(\{[\s\S]*?\});\s*(?:var|const|let|<\/script>)/);
  if (modelMatch) {
    try {
      const model = JSON.parse(modelMatch[1]);

      // Collect articles from both masthead features and blogList
      const allBlogs = [];
      if (model.masthead?.features) allBlogs.push(...model.masthead.features);
      if (model.blogList?.blogs) allBlogs.push(...model.blogList.blogs);

      const seen = new Set();
      for (const item of allBlogs) {
        const title = item.blog_title || item.title || '';
        if (!title) continue;

        let slug = item.default_url || item.article_url || '';
        // Skip non-article links (shop, external)
        if (!slug || slug.includes('shop.battle.net')) continue;

        // Normalize URL: ensure it points to worldofwarcraft.blizzard.com
        if (slug.startsWith('/')) {
          slug = `https://worldofwarcraft.blizzard.com${slug}`;
        } else if (slug.includes('worldofwarcraft.com') && !slug.includes('blizzard.com')) {
          slug = slug.replace('worldofwarcraft.com', 'worldofwarcraft.blizzard.com');
        }

        // Deduplicate by title
        if (seen.has(title)) continue;
        seen.add(title);

        let imageUrl = null;
        if (item.header?.url) {
          imageUrl = item.header.url;
        } else if (item.thumbnail?.url) {
          imageUrl = item.thumbnail.url;
        }
        if (imageUrl && imageUrl.startsWith('//')) {
          imageUrl = `https:${imageUrl}`;
        }

        articles.push({
          id: `blizzard_${item.id || articles.length}`,
          title,
          source: 'blizzard',
          category: item.community || 'News',
          imageUrl,
          summary: item.summary || item.description || '',
          content: item.content || item.body || item.html || '',
          author: 'Blizzard Entertainment',
          publishedAt: item.created_at || item.updated_at || new Date().toISOString(),
          url: slug,
        });
      }
    } catch (_) {}
  }

  // Only use the model-based results (fallback produced junk with homepage URLs)
  return articles;
}

// --- Wowhead News ---
async function fetchWowheadNews(env) {
  const cacheKey = 'news_wowhead';
  const cached = await env.CACHE.get(cacheKey);
  if (cached) {
    return new Response(cached, {
      headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
    });
  }

  let articles = [];

  // Strategy 1: Direct RSS (has images + metadata, but content:encoded is truncated)
  try {
    const response = await fetch('https://www.wowhead.com/news/rss/all', {
      headers: { 'User-Agent': 'WoWCompanion/1.0' },
    });
    if (response.ok) {
      const xml = await response.text();
      articles = parseRSS(xml, 'wowhead', 'https://www.wowhead.com');
    }
  } catch (_) {}

  // Strategy 2: Always try feed2json.org for full content_html
  {
    try {
      const proxyUrl = 'https://feed2json.org/convert?url=' +
        encodeURIComponent('https://www.wowhead.com/news/rss/all');
      const response = await fetch(proxyUrl, { headers: { 'Accept': 'application/json' } });
      if (response.ok) {
        const data = await response.json();
        if (data.items && data.items.length > 0) {
          // If we already have articles from direct RSS (with images), merge content
          if (articles.length > 0) {
            const contentMap = {};
            for (const item of data.items) {
              if (item.url && item.content_html) {
                contentMap[item.url] = item.content_html;
              }
            }
            for (const article of articles) {
              if (contentMap[article.url]) {
                article.content = contentMap[article.url];
              }
            }
          } else {
            // No direct RSS results, use feed2json entirely
            for (const item of data.items) {
              let imageUrl = item.image || null;
              if (!imageUrl && item.content_html) {
                const imgMatch = item.content_html.match(/<img[^>]*src="([^"]*)"[^>]*>/i);
                if (imgMatch) imageUrl = imgMatch[1];
              }
              articles.push({
                id: `wowhead_${articles.length}`,
                title: item.title || '',
                source: 'wowhead',
                category: detectCategory(item.title || ''),
                imageUrl,
                summary: (item.summary || '').replace(/<[^>]+>/g, '').trim().substring(0, 300),
                content: item.content_html || '',
                author: item.author?.name || null,
                publishedAt: item.date_published
                  ? new Date(item.date_published).toISOString()
                  : new Date().toISOString(),
                url: item.url || item.id || '',
              });
            }
          }
        }
      }
    } catch (_) {}
  }

  if (articles.length > 0) {
    const result = JSON.stringify(articles);
    await env.CACHE.put(cacheKey, result, { expirationTtl: NEWS_CACHE_TTL });
    return new Response(result, {
      headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
    });
  }

  return json([]);
}

// --- MMO-Champion News ---
async function fetchMMOChampionNews(env) {
  const cacheKey = 'news_mmochampion';
  const cached = await env.CACHE.get(cacheKey);
  if (cached) {
    return new Response(cached, {
      headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
    });
  }

  // Use sectionid=1 for front-page news (not forum posts)
  const mmocRssUrl = 'https://www.mmo-champion.com/external.php?do=rss&type=newcontent&sectionid=1&days=120&count=20';
  let articles = [];

  // Strategy 1: Direct RSS (may have content:encoded)
  try {
    const rssResponse = await fetch(mmocRssUrl, {
      headers: { 'User-Agent': 'WoWCompanion/1.0' },
    });
    if (rssResponse.ok) {
      const xml = await rssResponse.text();
      articles = parseRSS(xml, 'mmochampion', 'https://www.mmo-champion.com');
    }
  } catch (_) {}

  // Strategy 2: feed2json.org for full content_html
  if (articles.length === 0 || !articles[0].content) {
    try {
      const proxyUrl = 'https://feed2json.org/convert?url=' + encodeURIComponent(mmocRssUrl);
      const response = await fetch(proxyUrl, { headers: { 'Accept': 'application/json' } });
      if (response.ok) {
        const data = await response.json();
        if (data.items && data.items.length > 0) {
          if (articles.length > 0) {
            // Merge content + images into existing articles
            const contentMap = {};
            for (const item of data.items) {
              if (item.url) {
                contentMap[item.url] = {
                  content: item.content_html || '',
                  image: item.image || null,
                };
              }
            }
            for (const article of articles) {
              const enrichment = contentMap[article.url];
              if (enrichment) {
                if (enrichment.content) article.content = enrichment.content;
                if (!article.imageUrl && enrichment.image) article.imageUrl = enrichment.image;
                // Extract first large image from content if still no image
                if (!article.imageUrl && enrichment.content) {
                  const imgMatch = enrichment.content.match(/<img[^>]*src="(https?:\/\/[^"]*(?:news|upload|header|banner|featured)[^"]*)"/i);
                  if (imgMatch) article.imageUrl = imgMatch[1];
                }
              }
            }
          } else {
            for (const item of data.items) {
              let imageUrl = item.image || null;
              if (!imageUrl && item.content_html) {
                const imgMatch = item.content_html.match(/<img[^>]*src="([^"]*)"[^>]*>/i);
                if (imgMatch) imageUrl = imgMatch[1];
              }
              articles.push({
                id: `mmochampion_${articles.length}`,
                title: item.title || '',
                source: 'mmochampion',
                category: detectCategory(item.title || ''),
                imageUrl,
                summary: (item.content_text || item.summary || '').substring(0, 300),
                content: item.content_html || '',
                author: item.author?.name || null,
                publishedAt: item.date_published
                  ? new Date(item.date_published).toISOString()
                  : new Date().toISOString(),
                url: item.url || item.id || '',
              });
            }
          }
        }
      }
    } catch (_) {}
  }

  if (articles.length > 0) {
    const result = JSON.stringify(articles);
    await env.CACHE.put(cacheKey, result, { expirationTtl: NEWS_CACHE_TTL });
    return new Response(result, {
      headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
    });
  }

  return json([]);
}

// --- Icy Veins News ---
async function fetchIcyVeinsNews(env) {
  const cacheKey = 'news_icyveins';
  const cached = await env.CACHE.get(cacheKey);
  if (cached) {
    return new Response(cached, {
      headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
    });
  }

  // IcyVeins RSS — resolve the origin IP directly to bypass Cloudflare bot protection.
  // wp-prod.icy-veins.com is behind CF, but we can try fetching with cf.resolveOverride
  // or by going through a third-party RSS proxy as fallback.
  let articles = [];

  // Strategy 1: Direct fetch (may be blocked by CF bot protection)
  try {
    const response = await fetch('https://wp-prod.icy-veins.com/custom-rss/?category=wow', {
      cf: { cacheTtl: 1800, cacheEverything: true },
    });
    if (response.ok) {
      const text = await response.text();
      if (text.includes('<item>')) {
        articles = parseRSS(text, 'icyveins', 'https://www.icy-veins.com');
      }
    }
  } catch (_) {}

  // Strategy 2: Use feed2json.org as a proxy (not on Cloudflare, bypasses bot protection)
  if (articles.length === 0) {
    try {
      const proxyUrl = 'https://feed2json.org/convert?url=' +
        encodeURIComponent('https://wp-prod.icy-veins.com/custom-rss/?category=wow');
      const response = await fetch(proxyUrl, {
        headers: { 'Accept': 'application/json' },
      });
      if (response.ok) {
        const data = await response.json();
        if (data.items && data.items.length > 0) {
          for (const item of data.items) {
            // Extract a meaningful thumbnail — skip tiny icons and logos
            let imageUrl = item.image || null;
            if (item.content_html) {
              // Find all images, pick the first one that looks like article content (not an icon)
              const allImgs = [...(item.content_html.matchAll(/<img[^>]*src="(https?:\/\/[^"]+)"[^>]*/gi))];
              for (const m of allImgs) {
                const src = m[1];
                // Skip known icon patterns
                if (src.includes('icon-small') || src.includes('emoji') || src.includes('widgets.js') ||
                    src.includes('/icons/') || src.includes('gravatar') || src.includes('platform.twitter')) {
                  continue;
                }
                // Prefer wp-content/uploads images (featured/article images)
                if (src.includes('wp-content/uploads') || src.includes('static.icy-veins.com') ||
                    src.includes('.jpg') || src.includes('.png') || src.includes('.webp')) {
                  imageUrl = src;
                  break;
                }
              }
            }

            articles.push({
              id: `icyveins_${articles.length}`,
              title: item.title || '',
              source: 'icyveins',
              category: detectCategory(item.title || ''),
              imageUrl: imageUrl || null,
              summary: (item.content_text || item.summary || '').substring(0, 300),
              content: item.content_html || item.content || '',
              author: item.author?.name || null,
              publishedAt: item.date_published
                ? new Date(item.date_published).toISOString()
                : new Date().toISOString(),
              url: item.url || item.id || '',
            });
          }
        }
      }
    } catch (_) {}
  }

  // Only cache non-empty results so we retry on next request
  if (articles.length > 0) {
    const result = JSON.stringify(articles);
    await env.CACHE.put(cacheKey, result, { expirationTtl: NEWS_CACHE_TTL });
    return new Response(result, {
      headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
    });
  }

  return json([]);
}

// --- Reddit r/wow ---
async function fetchRedditPosts(env) {
  const cacheKey = 'news_reddit';
  const cached = await env.CACHE.get(cacheKey);
  if (cached) {
    return new Response(cached, {
      headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
    });
  }

  const response = await fetch('https://www.reddit.com/r/wow/hot.json?limit=20', {
    headers: { 'User-Agent': 'WoWCompanion/1.0 (by /u/wowcompanion)' },
  });

  if (!response.ok) {
    return json({ error: `Reddit returned ${response.status}` }, 502);
  }

  const data = await response.json();
  const posts = (data?.data?.children || [])
    .filter(child => !child.data.stickied) // Skip pinned posts
    .map(child => {
      const post = child.data;
      return {
        id: `reddit_${post.id}`,
        title: post.title,
        source: 'reddit',
        category: post.link_flair_text || 'Discussion',
        imageUrl: (post.thumbnail && post.thumbnail !== 'self' && post.thumbnail !== 'default' && post.thumbnail !== 'nsfw')
          ? post.thumbnail : null,
        summary: post.selftext ? post.selftext.substring(0, 200) : '',
        content: post.selftext || '',
        author: post.author,
        publishedAt: new Date(post.created_utc * 1000).toISOString(),
        url: `https://reddit.com${post.permalink}`,
        score: post.score,
        numComments: post.num_comments,
        flair: post.link_flair_text || null,
      };
    });

  const result = JSON.stringify(posts);
  await env.CACHE.put(cacheKey, result, { expirationTtl: NEWS_CACHE_TTL });

  return new Response(result, {
    headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
  });
}

// --- Article content extraction ---
async function fetchArticleContent(url, env) {
  let articleUrl = url.searchParams.get('url');
  if (!articleUrl) {
    return json({ error: 'Missing url parameter' }, 400);
  }

  // Normalize Blizzard URLs
  articleUrl = articleUrl.replace('worldofwarcraft.com/', 'worldofwarcraft.blizzard.com/');

  // Validate URL is from allowed domains
  const allowed = ['worldofwarcraft.blizzard.com', 'www.wowhead.com', 'www.mmo-champion.com', 'www.icy-veins.com', 'icy-veins.com'];
  const parsedUrl = new URL(articleUrl);
  if (!allowed.includes(parsedUrl.hostname)) {
    return json({ error: `Domain not allowed: ${parsedUrl.hostname}` }, 403);
  }

  const cacheKey = `article_${btoa(articleUrl).substring(0, 100)}`;
  const cached = await env.CACHE.get(cacheKey);
  if (cached) {
    return new Response(cached, {
      headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
    });
  }

  // Fetch with redirect following
  const response = await fetch(articleUrl, {
    headers: { 'User-Agent': 'WoWCompanion/1.0' },
    redirect: 'follow',
  });

  if (!response.ok) {
    return json({ error: `Article fetch returned ${response.status}` }, 502);
  }

  const html = await response.text();
  const finalHostname = new URL(response.url || articleUrl).hostname;
  const article = extractArticleContent(html, finalHostname);

  // Only cache if we got content
  if (article.content || article.summary || article.imageUrl) {
    const result = JSON.stringify(article);
    await env.CACHE.put(cacheKey, result, { expirationTtl: ARTICLE_CACHE_TTL });
    return new Response(result, {
      headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
    });
  }

  return json(article);
}

function extractArticleContent(html, hostname) {
  // Extract og:image and og:description BEFORE stripping scripts
  // (they're in <meta> tags, not scripts)
  const ogImageMatch = html.match(/<meta[^>]*property="og:image"[^>]*content="([^"]*)"[^>]*>/i)
    || html.match(/<meta[^>]*content="([^"]*)"[^>]*property="og:image"[^>]*>/i);
  const imageUrl = ogImageMatch ? ogImageMatch[1] : null;

  const ogDescMatch = html.match(/<meta[^>]*property="og:description"[^>]*content="([^"]*)"[^>]*>/i)
    || html.match(/<meta[^>]*content="([^"]*)"[^>]*property="og:description"[^>]*>/i);
  const summary = ogDescMatch ? ogDescMatch[1] : '';

  let content = '';
  let author = null;

  if (hostname.includes('blizzard') || hostname.includes('worldofwarcraft')) {
    // Blizzard news pages are SPAs — article content is in the model JS variable
    const modelMatch = html.match(/model\s*=\s*(\{[\s\S]*?\});\s*(?:var|const|let|<\/script>)/);
    if (modelMatch) {
      try {
        const model = JSON.parse(modelMatch[1]);
        // The article detail page has a 'blog' object with the content
        const blog = model.blog || model.article || model;
        content = blog.content || blog.body || blog.html || '';
      } catch (_) {}
    }
    // Fallback: try traditional HTML extraction
    if (!content) {
      const cleaned = html.replace(/<script[\s\S]*?<\/script>/gi, '').replace(/<style[\s\S]*?<\/style>/gi, '');
      const bodyMatch = cleaned.match(/class="[^"]*(?:Blog-content|blog-detail|article-content|news-detail)[^"]*">([\s\S]*?)<\/(?:section|article|main)/i)
        || cleaned.match(/<article[^>]*>([\s\S]*?)<\/article>/i)
        || cleaned.match(/<main[^>]*>([\s\S]*?)<\/main>/i);
      content = bodyMatch ? bodyMatch[1] : '';
    }
    author = 'Blizzard Entertainment';
  } else if (hostname.includes('wowhead')) {
    // Wowhead injects content via WH.markup.printHtml() in a script tag.
    // Extract the HTML string argument from that call.
    const whMarkupMatch = html.match(/WH\.markup\.printHtml\("((?:[^"\\]|\\.)*)"/);
    if (whMarkupMatch) {
      try {
        // The argument is a JSON-escaped string containing Wowhead markup
        const rawMarkup = JSON.parse('"' + whMarkupMatch[1] + '"');
        // Convert Wowhead markup tags [b], [url=...], [item=...] etc. to HTML
        content = rawMarkup
          .replace(/\[b\]/g, '<strong>').replace(/\[\/b\]/g, '</strong>')
          .replace(/\[i\]/g, '<em>').replace(/\[\/i\]/g, '</em>')
          .replace(/\[u\]/g, '<u>').replace(/\[\/u\]/g, '</u>')
          .replace(/\[h2\]/g, '<h3>').replace(/\[\/h2\]/g, '</h3>')
          .replace(/\[h3\]/g, '<h3>').replace(/\[\/h3\]/g, '</h3>')
          .replace(/\[ul\]/g, '<ul>').replace(/\[\/ul\]/g, '</ul>')
          .replace(/\[ol\]/g, '<ol>').replace(/\[\/ol\]/g, '</ol>')
          .replace(/\[li\]/g, '<li>').replace(/\[\/li\]/g, '</li>')
          .replace(/\[url=([^\]]*)\]([^[]*)\[\/url\]/g, '<a href="$1">$2</a>')
          .replace(/\[img\]([^[]*)\[\/img\]/g, '<img src="$1">')
          .replace(/\[quote[^\]]*\]/g, '<blockquote>').replace(/\[\/quote\]/g, '</blockquote>')
          .replace(/\[db=live\]/g, '').replace(/\[\/db\]/g, '')
          .replace(/\[(?:item|spell|npc|quest|achievement|event)=(\d+)[^\]]*\]/g, '')
          .replace(/\[\/(?:item|spell|npc|quest|achievement|event)\]/g, '')
          .replace(/\[hr\]/g, '<hr>')
          .replace(/\[p\]/g, '<p>').replace(/\[\/p\]/g, '</p>')
          .replace(/\[center\]/g, '').replace(/\[\/center\]/g, '')
          .replace(/\[cta-button[^\]]*\][^[]*\[\/cta-button\]/g, '')
          .replace(/\[screenshot[^\]]*\]/g, '')
          .replace(/\[table[^\]]*\]/g, '<table>').replace(/\[\/table\]/g, '</table>')
          .replace(/\[tr\]/g, '<tr>').replace(/\[\/tr\]/g, '</tr>')
          .replace(/\[td[^\]]*\]/g, '<td>').replace(/\[\/td\]/g, '</td>')
          .replace(/\[th[^\]]*\]/g, '<th>').replace(/\[\/th\]/g, '</th>')
          .replace(/\[[a-z]+-[a-z]+[^\]]*\][^[]*\[\/[a-z]+-[a-z]+\]/g, '') // Remove unknown compound tags
          .replace(/\[\/?[a-z]+[^\]]*\]/g, '') // Remove any remaining unknown tags
          .replace(/\n/g, '<br>');
      } catch (_) {}
    }

    // Fallback: extract from rendered HTML
    if (!content || content.replace(/<[^>]+>/g, '').trim().length < 100) {
      const bodyMatch = html.match(/class="news-post-content[^"]*"[^>]*>([\s\S]*?)(?:<div[^>]*class="[^"]*(?:news-post-newsletter|news-post-footer|news-recent|comments)[^"]*")/i);
      if (bodyMatch) {
        content = bodyMatch[1]
          .replace(/<script[\s\S]*?<\/script>/gi, '')
          .replace(/<style[\s\S]*?<\/style>/gi, '');
      }
    }

    const authorMatch = html.match(/class="[^"]*news-post-header-details-author[^"]*"[^>]*>([\s\S]*?)<\/a>/i);
    author = authorMatch ? authorMatch[1].replace(/<[^>]+>/g, '').trim() : null;
  } else if (hostname.includes('mmo-champion')) {
    const cleaned = html.replace(/<script[\s\S]*?<\/script>/gi, '');
    // MMO-C forum posts use pcm_content or post body divs
    const bodyMatch = cleaned.match(/<div[^>]*class="[^"]*(?:pcm_content|content|post-body|postcontent)[^"]*"[^>]*>([\s\S]*?)(?:<\/div>\s*<div class="(?:post-footer|comment|signature)|<\/blockquote>|$)/i)
      || cleaned.match(/<blockquote[^>]*class="[^"]*postcontent[^"]*"[^>]*>([\s\S]*?)<\/blockquote>/i);
    content = bodyMatch ? bodyMatch[1] : '';
  } else if (hostname.includes('icy-veins')) {
    const cleaned = html.replace(/<script[\s\S]*?<\/script>/gi, '');
    const bodyMatch = cleaned.match(/<div[^>]*class="[^"]*(?:news_body|article-content|entry-content|post-content)[^"]*"[^>]*>([\s\S]*?)(?:<\/div>\s*<div[^>]*class="[^"]*(?:comment|related|disqus|share)|<div id="(?:comment|disqus))/i)
      || cleaned.match(/<article[^>]*>([\s\S]*?)<\/article>/i);
    content = bodyMatch ? bodyMatch[1] : '';
  }

  // Clean up the content HTML — keep structure tags for reader rendering
  content = content
    .replace(/<(?:nav|header|footer|aside|iframe|noscript|script|style)[\s\S]*?<\/(?:nav|header|footer|aside|iframe|noscript|script|style)>/gi, '')
    .replace(/class="[^"]*"/g, '')
    .replace(/style="[^"]*"/g, '')
    .replace(/id="[^"]*"/g, '')
    .replace(/data-[a-z-]+="[^"]*"/g, '')
    .trim();

  return { content, imageUrl, summary, author };
}

// --- Shared RSS parser ---
function parseRSS(xml, source, baseUrl) {
  const articles = [];
  const itemRegex = /<item>([\s\S]*?)<\/item>/gi;
  let match;

  while ((match = itemRegex.exec(xml)) !== null) {
    const item = match[1];
    const title = extractTag(item, 'title');
    const link = extractTag(item, 'link') || extractTag(item, 'guid');
    const description = extractTag(item, 'description');
    const contentEncoded = extractTag(item, 'content:encoded');
    const pubDate = extractTag(item, 'pubDate');
    const creator = extractTag(item, 'dc:creator') || extractTag(item, 'author');
    const category = extractTag(item, 'category');

    // Try to extract image from various RSS image patterns
    const mediaMatch = item.match(/<media:content[^>]*url="([^"]*)"[^>]*>/i)
      || item.match(/<media:thumbnail[^>]*url="([^"]*)"[^>]*>/i)
      || item.match(/<enclosure[^>]*url="([^"]*)"[^>]*type="image/i)
      || item.match(/<featured-image>([\s\S]*?)<\/featured-image>/i)
      || (description && description.match(/<img[^>]*src="([^"]*)"[^>]*>/i));
    const imageUrl = mediaMatch ? mediaMatch[1].trim() : null;

    // Clean description of HTML for summary
    const summary = description
      ? description.replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, '$1').replace(/<[^>]+>/g, '').trim().substring(0, 300)
      : '';

    // Full article content from content:encoded (CDATA stripped, HTML preserved)
    const fullContent = contentEncoded
      ? contentEncoded.replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, '$1').trim()
      : '';

    if (title && link) {
      articles.push({
        id: `${source}_${articles.length}`,
        title: title.replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, '$1').trim(),
        source,
        category: category ? category.replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, '$1').trim() : detectCategory(title),
        imageUrl,
        summary,
        content: fullContent,
        author: creator ? creator.replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, '$1').trim() : null,
        publishedAt: pubDate ? new Date(pubDate).toISOString() : new Date().toISOString(),
        url: link.startsWith('http') ? link : `${baseUrl}${link}`,
      });
    }
  }

  return articles;
}

function extractTag(xml, tagName) {
  const regex = new RegExp(`<${tagName}[^>]*>([\\s\\S]*?)<\\/${tagName}>`, 'i');
  const match = xml.match(regex);
  return match ? match[1].trim() : null;
}

function detectCategory(title) {
  const lower = title.toLowerCase();
  if (lower.includes('hotfix')) return 'Hotfix';
  if (lower.includes('patch notes') || lower.includes('patch ')) return 'Patch Notes';
  if (lower.includes('blue post') || lower.includes('blue tracker')) return 'Blue Post';
  if (lower.includes('guide')) return 'Guide';
  if (lower.includes('datamin')) return 'Datamining';
  if (lower.includes('maintenance') || lower.includes('downtime')) return 'Maintenance';
  if (lower.includes('pvp') || lower.includes('arena')) return 'PvP';
  if (lower.includes('raid') || lower.includes('mythic')) return 'Raid & Dungeons';
  return 'News';
}

// ---------------------------------------------------------------------------
// Image proxy (bypass geo-blocking for Wowhead/IcyVeins images)
// ---------------------------------------------------------------------------

const ALLOWED_IMAGE_DOMAINS = new Set([
  'wow.zamimg.com', 'zamimg.com',
  'media.mmo-champion.com', 'static.mmo-champion.com',
  'wp.icy-veins.com', 'static.icy-veins.com',
  'bnetcmsus-a.akamaihd.net', 'blz-contentstack-images.akamaized.net',
]);

async function handleImageProxy(request, env) {
  const url = new URL(request.url);
  const imageUrl = url.searchParams.get('url');
  if (!imageUrl) {
    return json({ error: 'Missing url parameter' }, 400);
  }

  try {
    const parsedUrl = new URL(imageUrl);
    if (!ALLOWED_IMAGE_DOMAINS.has(parsedUrl.hostname)) {
      return json({ error: 'Domain not allowed' }, 403);
    }

    // Check KV cache (images cached 24h)
    const cacheKey = `img_${imageUrl.substring(0, 200)}`;
    const cached = await env.CACHE.get(cacheKey, { type: 'arrayBuffer' });
    if (cached) {
      const contentType = imageUrl.match(/\.webp$/i) ? 'image/webp'
        : imageUrl.match(/\.png$/i) ? 'image/png'
        : 'image/jpeg';
      return new Response(cached, {
        headers: { 'Content-Type': contentType, 'Cache-Control': 'public, max-age=86400', ...CORS_HEADERS },
      });
    }

    const response = await fetch(imageUrl, {
      headers: { 'User-Agent': 'WoWCompanion/1.0' },
    });

    if (!response.ok) {
      return new Response(null, { status: response.status, headers: CORS_HEADERS });
    }

    const contentType = response.headers.get('content-type') || 'image/jpeg';
    const buffer = await response.arrayBuffer();

    // Cache in KV (24h, max 10MB)
    if (buffer.byteLength < 10 * 1024 * 1024) {
      await env.CACHE.put(cacheKey, buffer, { expirationTtl: 86400 });
    }

    return new Response(buffer, {
      headers: { 'Content-Type': contentType, 'Cache-Control': 'public, max-age=86400', ...CORS_HEADERS },
    });
  } catch (e) {
    return json({ error: 'Image proxy error' }, 500);
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
  });
}
