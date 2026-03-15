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

    const index = await getCommoditiesIndex(region, env);

    const prices = {};
    for (const id of itemIds) {
      if (index[id]) {
        prices[id] = index[id];
      }
    }

    return json({ prices });
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
    const itemId = String(auction.item.id);
    const unitPrice = auction.unit_price;
    const quantity = auction.quantity;

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

  // Cache the processed index for 1 hour
  await env.CACHE.put(cacheKey, JSON.stringify(index), { expirationTtl: 3600 });

  return index;
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
