import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { resolve, extname } from 'node:path';
import { supabaseConfig } from './supabase.js';
import { createStore } from './store.js';
import { ApiError, execute, snapshot } from './service.js';

const demoMode = process.env.APP_MODE === 'demo';
const root = fileURLToPath(new URL('../../frontend/', import.meta.url));
const store = createStore(process.env.DATA_FILE || fileURLToPath(new URL('../data/state.json', import.meta.url)));
const port = Number(process.env.PORT || 4317);
const allowedOrigin = `http://localhost:${port}`;
const json = (res, status, body) => {
  res.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
  res.end(JSON.stringify(body));
};

createServer(async (req, res) => {
  try {
    // Local demo only: do not expose header-based identities on a public server.
    if (![ `localhost:${port}`, `127.0.0.1:${port}` ].includes(req.headers.host)) throw new ApiError(403, 'Local access only');
    const path = new URL(req.url, allowedOrigin).pathname;
    if (path.startsWith('/api/')) {
      if (req.headers.origin && ![allowedOrigin, `http://127.0.0.1:${port}`].includes(req.headers.origin)) {
        throw new ApiError(403, 'Origin not allowed');
      }
      if (path === '/api/config' && req.method === 'GET') {
        if (demoMode) return json(res, 200, { mode: 'demo' });
        try {
          const config = supabaseConfig();
          return json(res, 200, { mode: 'supabase', url: config.url, publishableKey: config.key });
        } catch { throw new ApiError(503, 'Configure Supabase in .env, or explicitly set APP_MODE=demo'); }
      }
      if (!demoMode) throw new ApiError(503, 'Session API is not connected yet');
      const role = req.headers['x-demo-role'];
      if (!['admin', 'member'].includes(role)) throw new ApiError(401, 'Demo role required');
      // Both preview roles represent the same demo user. Replace with verified
      // identity from a server session before enabling real authentication.
      const user = { id: 'demo-user', role };
      if (path === '/api/state' && req.method === 'GET') return json(res, 200, snapshot(store.read(), user));
      if (path === '/api/commands' && req.method === 'POST') {
        if (req.headers['content-type'] !== 'application/json') throw new ApiError(415, 'JSON required');
        let body = '';
        for await (const chunk of req) {
          body += chunk;
          if (body.length > 16384) throw new ApiError(413, 'Request too large');
        }
        let command;
        try { command = JSON.parse(body); } catch { throw new ApiError(400, 'Invalid JSON'); }
        return json(res, 200, execute(store, user, command));
      }
      throw new ApiError(404, 'API route not found');
    }
    if (req.method !== 'GET' && req.method !== 'HEAD') throw new ApiError(405, 'Method not allowed');
    const files = { '/': 'index.html', '/index.html': 'index.html', '/app.js': 'app.js', '/style.css': 'style.css', '/api.js': 'api.js', '/generated/connected.js': 'generated/connected.js' };
    if (!files[path]) throw new ApiError(404, 'Not found');
    const file = resolve(root, files[path]);
    const content = await readFile(file);
    res.writeHead(200, { 'Content-Type': { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css' }[extname(file)], 'Cache-Control': 'no-store' });
    res.end(req.method === 'HEAD' ? undefined : content);
  } catch (error) {
    if (!(error instanceof ApiError)) console.error(error);
    json(res, error.status || 500, { error: error.status ? error.message : 'Internal server error' });
  }
}).listen(port, '127.0.0.1', () => console.log(`House Leadership: ${allowedOrigin}`));
