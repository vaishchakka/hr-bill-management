export function normalizeGtEmail(value) {
  const email = String(value).trim().toLowerCase();
  if (!/^[^\s@]+@gatech\.edu$/.test(email)) throw new Error('Enter your @gatech.edu email address.');
  return email;
}
export async function sendEmailCode(client, value) {
  const email = normalizeGtEmail(value);
  const { error } = await client.auth.signInWithOtp({ email, options: { shouldCreateUser: true } });
  if (error) throw new Error(error.message);
  return email;
}
export async function verifyEmailCode(client, email, value) {
  const token = String(value).trim();
  if (!/^\d{6,10}$/.test(token)) throw new Error('Enter the numeric code from your email.');
  const { error } = await client.auth.verifyOtp({ email: normalizeGtEmail(email), token, type: 'email' });
  if (error) throw new Error(error.message);
}
