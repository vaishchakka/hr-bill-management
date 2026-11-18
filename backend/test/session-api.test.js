import test from 'node:test';
import assert from 'node:assert/strict';
import { createSessionApi } from '../../frontend/session-api.js';
test('session client sends exact database commands and IDs', async () => {
  const calls = [];
  const api = createSessionApi({ rpc: async (...args) => { calls.push(args); return {data:{id:'s'},error:null}; } });
  await api.read(); await api.start(); await api.end('s'); await api.present('s','b'); await api.hide('s');
  assert.deepEqual(calls, [
    ['get_house_state',undefined], ['start_house_session',undefined],
    ['end_house_session',{p_session_id:'s'}],
    ['present_house_bill',{p_session_id:'s',p_bill_id:'b'}],
    ['hide_house_bill',{p_session_id:'s'}],
  ]);
});
test('session client surfaces database permission errors instead of returning success', async () => {
  const api = createSessionApi({rpc:async()=>({data:null,error:{message:'Admin access required'}})});
  await assert.rejects(api.start(), /Admin access required/);
});
