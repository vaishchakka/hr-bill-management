import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizeGtEmail, sendEmailCode, verifyEmailCode } from '../../frontend/email-auth.js';
test('GT email validation normalizes case but rejects lookalike domains', () => {
 assert.equal(normalizeGtEmail(' Person@GATECH.edu '),'person@gatech.edu');
 for (const value of ['person@example.com','person@gatech.edu.evil','person@@gatech.edu','@gatech.edu']) assert.throws(()=>normalizeGtEmail(value));
});
test('email verification uses OTP without claiming membership from email alone', async () => {
 const calls=[]; const client={auth:{signInWithOtp:async input=>{calls.push(input);return {error:null};},verifyOtp:async input=>{calls.push(input);return {error:null};}}};
 assert.equal(await sendEmailCode(client,'Person@gatech.edu'),'person@gatech.edu');
 await verifyEmailCode(client,'person@gatech.edu','123456');
 assert.deepEqual(calls,[{email:'person@gatech.edu',options:{shouldCreateUser:true}},{email:'person@gatech.edu',token:'123456',type:'email'}]);
 await assert.rejects(verifyEmailCode(client,'person@gatech.edu','bad'),/numeric code/);
});
test('email delivery errors surface to the user', async()=>{
 await assert.rejects(sendEmailCode({auth:{signInWithOtp:async()=>({error:{message:'Rate limit'}})}},'person@gatech.edu'),/Rate limit/);
});
