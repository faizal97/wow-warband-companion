/**
 * WoW Companion Auth Proxy — Cloudflare Worker
 *
 * Exchanges Battle.net OAuth authorization codes for access tokens,
 * keeping the client secret server-side.
 *
 * Secrets (set via `wrangler secret put`):
 *   BNET_CLIENT_ID
 *   BNET_CLIENT_SECRET
 */

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
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

    // Health check
    if (url.pathname === '/' && request.method === 'GET') {
      return json({ status: 'ok', service: 'wow-companion-auth' });
    }

    return json({ error: 'Not found' }, 404);
  },
};

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

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json', ...CORS_HEADERS },
  });
}
