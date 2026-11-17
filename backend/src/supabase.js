// Uses only the public application key. Authenticated requests will also need
// the signed-in user's access token; this key does not grant admin privileges.
export function supabaseConfig(env = process.env) {
  const url = env.SUPABASE_URL;
  const key = env.SUPABASE_PUBLISHABLE_KEY;
  if (!url || !key) throw new Error('Set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY in .env');
  const parsed = new URL(url);
  if (parsed.protocol !== 'https:' || !parsed.hostname.endsWith('.supabase.co') || parsed.pathname !== '/') {
    throw new Error('SUPABASE_URL must be the HTTPS project API URL');
  }
  if (!key.startsWith('sb_publishable_')) throw new Error('Use a Supabase publishable key, not a secret key');
  return { url: parsed.origin, key };
}

export async function checkSupabase(env = process.env, fetcher = fetch) {
  const { url, key } = supabaseConfig(env);
  const response = await fetcher(`${url}/auth/v1/settings`, {
    headers: { apikey: key }, signal: AbortSignal.timeout(10000),
  });
  if (!response.ok) throw new Error(`Supabase connection failed (HTTP ${response.status})`);
  return { connected: true, project: new URL(url).hostname };
}
