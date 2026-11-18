import test from 'node:test';
import assert from 'node:assert/strict';
import { watchSession } from '../../frontend/session-sync.js';
const settle = () => new Promise(resolve => setImmediate(resolve));
test('private subscription refreshes snapshots on events/reconnect and cleans up', async () => {
  let event, subscription, poll, removed, reads=0;
  const channel={on(type,filter,fn){assert.equal(type,'broadcast');assert.equal(filter.event,'state_changed');event=fn;return this;},subscribe(fn){subscription=fn;return this;}};
  const client={realtime:{setAuth:async()=>{}},channel(topic,options){assert.equal(topic,'house:session');assert.equal(options.config.private,true);return channel;},removeChannel(c){removed=c;}};
  const sync=watchSession(client,{refresh:async()=>{reads++;},status:()=>{}},{setInterval(fn,ms){assert.equal(ms,15000);poll=fn;return 1;},clearInterval(){}});
  await settle(); const initial=reads;
  subscription('SUBSCRIBED');await settle();
  await event();await poll();assert.equal(reads,initial+3);
  sync.dispose();await event();assert.equal(reads,initial+3);assert.equal(removed,channel);
});
test('subscription failure retains fallback refresh', async () => {
 let poll, reads=0, status;
 const sync=watchSession({realtime:{setAuth:async()=>{throw new Error('offline');}}},{refresh:async()=>{reads++;},status:s=>{status=s;}},{setInterval(fn){poll=fn;return 1;},clearInterval(){}});
 await settle();await poll();assert.equal(reads,2);assert.match(status,/unavailable/);sync.dispose();
});
