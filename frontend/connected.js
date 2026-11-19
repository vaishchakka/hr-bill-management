import { sendEmailCode, verifyEmailCode } from './email-auth.js';
import { mountSessionUI } from './session-ui.js';
import { createClient } from '@supabase/supabase-js';

const main = document.querySelector('main');
const crumb = document.querySelector('#crumb');
const mode = document.querySelector('.mode');
const escape = value => String(value).replace(/[&<>"']/g, c => ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' }[c]));
let client, generation = 0, disposeSession = () => {};
const showError = message => {
  const error = document.querySelector('#auth-error') || document.querySelector('#session-message');
  if (error) error.textContent = message;
};

function login(message = '') {
  disposeSession();
  disposeSession = () => {};
  crumb.textContent = 'Sign in / Join';
  mode.innerHTML = '';
  main.innerHTML = `<section class="auth-panel"><h1>Welcome</h1><p>Use your GT email to sign in or create an account. HR membership is required for access.</p><form id="email-form"><label>GT email<input type="email" name="email" autocomplete="email" placeholder="you@gatech.edu" required></label><p id="auth-error" role="alert">${escape(message)}</p><button class="primary">Email me a code</button></form><details class="password-option"><summary>Use an existing password instead</summary><form id="password-form"><label>Email<input type="email" name="email" autocomplete="username" required></label><label>Password<input type="password" name="password" autocomplete="current-password" required></label><button class="secondary">Sign in</button></form></details></section>`;
  document.querySelector('#email-form').onsubmit = async event => {
    event.preventDefault();
    const form = event.currentTarget, button = form.querySelector('button');
    button.disabled = true; showError('');
    try { const email = await sendEmailCode(client, new FormData(form).get('email')); codeForm(email); }
    catch (error) { showError(error.message); }
    finally { button.disabled = false; }
  };
  document.querySelector('#password-form').onsubmit = async event => {
    event.preventDefault();
    const form = event.currentTarget, button = form.querySelector('button'), values = new FormData(form);
    button.disabled = true; showError('');
    try {
      const { error } = await client.auth.signInWithPassword({ email: values.get('email'), password: values.get('password') });
      if (error) throw error;
      form.reset(); await updateIdentity();
    } catch (error) { showError(error.message); }
    finally { button.disabled = false; }
  };
}
function codeForm(email) {
  main.innerHTML = `<section class="auth-panel"><h1>Check your email</h1><p>Enter the code sent to ${escape(email)}.</p><form id="code-form"><label>Sign-in code<input name="code" inputmode="numeric" autocomplete="one-time-code" required></label><p id="auth-error" role="alert"></p><button class="primary">Verify and continue</button></form><p id="resend-status" role="status"></p><button id="resend-code" class="secondary" disabled>Resend code</button> <button id="change-email" class="secondary">Change email</button></section>`;
  const resend = document.querySelector('#resend-code');
  const cooldown = () => { resend.disabled = true; setTimeout(() => { if (resend.isConnected) resend.disabled = false; }, 60000); };
  cooldown();
  resend.onclick = async () => {
    resend.disabled = true; showError('');
    try { await sendEmailCode(client, email); document.querySelector('#resend-status').textContent = 'New code requested. Check your inbox.'; cooldown(); }
    catch (error) { showError(error.message); resend.disabled = false; }
  };
  document.querySelector('#change-email').onclick = () => login();
  document.querySelector('#code-form').onsubmit = async event => {
    event.preventDefault();
    const form = event.currentTarget, button = form.querySelector('button');
    button.disabled = true; showError('');
    try { await verifyEmailCode(client, email, new FormData(form).get('code')); form.reset(); await updateIdentity(); }
    catch (error) { showError(error.message); }
    finally { button.disabled = false; }
  };
}

async function updateIdentity() {
  const currentGeneration = ++generation;
  disposeSession();
  disposeSession = () => {};
  crumb.textContent = 'Checking access…';
  main.innerHTML = '<section class="auth-panel"><p>Checking your account…</p></section>';
  mode.innerHTML = '';
  try {
    // Verify identity with Auth; never authorize from local session data alone.
    const { data: { user }, error } = await client.auth.getUser();
    if (currentGeneration !== generation) return;
    if (error || !user) { login(); return; }
    const { error: claimError } = await client.rpc('claim_house_membership');
    if (currentGeneration !== generation) return;
    if (claimError) throw new Error('Membership setup is unavailable. Apply the email roster migration, then retry.');
    const { data: membership, error: membershipError } = await client
      .from('house_members').select('role').eq('user_id', user.id).maybeSingle();
    if (currentGeneration !== generation) return;
    if (membershipError) throw membershipError;
    const approved = ['admin', 'member'].includes(membership?.role);
    crumb.textContent = approved ? (membership.role === 'admin' ? 'Admin workspace' : 'Member view') : 'Access pending';
    mode.innerHTML = '<button id="sign-out" type="button">Sign out</button>';
    document.querySelector('#sign-out').onclick = async () => {
      const { error } = await client.auth.signOut();
      if (error) { showError(error.message); return; }
      ++generation;
      login();
    };
    if (approved) {
      disposeSession = mountSessionUI(client, main);
    } else {
      main.innerHTML = `<section class="auth-panel"><h1>Access pending</h1><p>${escape(user.email || '')}</p><p>An administrator must approve your membership.</p><p id="auth-error" role="alert"></p></section>`;
    }
  } catch (error) {
    if (currentGeneration !== generation) return;
    main.innerHTML = `<section class="auth-panel"><h1>Unable to check access</h1><p id="auth-error" role="alert">${escape(error.message)}</p><button id="retry-auth" class="primary">Retry</button></section>`;
    document.querySelector('#retry-auth').onclick = updateIdentity;
  }
}

let theme = localStorage.getItem('hf-theme') || (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
function applyTheme() {
  document.documentElement.dataset.theme = theme;
  document.documentElement.style.colorScheme = theme;
  document.querySelector('#theme-toggle').textContent = theme === 'dark' ? 'Light mode' : 'Dark mode';
}
document.querySelector('#theme-toggle').onclick = () => {
  theme = theme === 'dark' ? 'light' : 'dark';
  localStorage.setItem('hf-theme', theme);
  applyTheme();
};
applyTheme();
try {
  const response = await fetch('/api/config');
  const config = await response.json();
  if (!response.ok) throw new Error(config.error || 'Configuration unavailable');
  if (config.mode === 'demo') {
    await import('./app.js');
  } else {
    client = createClient(config.url, config.publishableKey);
    client.auth.onAuthStateChange(event => {
      // Defer async Supabase calls outside the auth event callback.
      if (['SIGNED_IN', 'SIGNED_OUT', 'USER_UPDATED'].includes(event)) setTimeout(updateIdentity, 0);
    });
    await updateIdentity();
  }
} catch (error) {
  main.innerHTML = `<section class="auth-panel"><h1>Setup required</h1><p role="alert">${escape(error.message)}</p></section>`;
}
