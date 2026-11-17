import test from 'node:test';
import assert from 'node:assert/strict';
import { supabaseConfig, checkSupabase } from '../src/supabase.js';
const env = { SUPABASE_URL: 'https://example.supabase.co', SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_test' };
test('configuration rejects missing config, dashboard URLs, and server secrets', () => {
  assert.throws(() => supabaseConfig({}));
  assert.throws(() => supabaseConfig({ ...env, SUPABASE_URL: 'https://supabase.com/dashboard/project/test' }));
  assert.throws(() => supabaseConfig({ ...env, SUPABASE_PUBLISHABLE_KEY: 'sb_secret_test' }));
});
test('connection probe passes public key and reports failures without printing it', async () => {
  const result = await checkSupabase(env, async (url, options) => {
    assert.equal(url, 'https://example.supabase.co/auth/v1/settings');
    assert.equal(options.headers.apikey, env.SUPABASE_PUBLISHABLE_KEY);
    return { ok: true };
  });
  assert.equal(result.connected, true);
  await assert.rejects(checkSupabase(env, async () => ({ ok: false, status: 401 })), /HTTP 401/);
});
