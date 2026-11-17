import { createClient } from '@supabase/supabase-js';

const main = document.querySelector('main');
const crumb = document.querySelector('#crumb');
const mode = document.querySelector('.mode');
const escape = value => String(value).replace(/[&<>"']/g, c => ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' }[c]));
let client, generation = 0;
const showError = message => {
  const error = document.querySelector('#auth-error');
  if (error) error.textContent = message;
};

function login(message = '') {
  crumb.textContent = 'Sign in';
  mode.innerHTML = '';
  main.innerHTML = `<section class="auth-panel"><h1>Sign in</h1><p>House Leadership</p><form id="login-form"><label>Email<input type="email" name="email" autocomplete="username" required></label><label>Password<input type="password" name="password" autocomplete="current-password" required></label><p id="auth-error" role="alert">${escape(message)}</p><button class="primary" type="submit">Sign in</button></form></section>`;
  document.querySelector('#login-form').onsubmit = async event => {
    event.preventDefault();
    const form = event.currentTarget, button = form.querySelector('button');
    button.disabled = true;
    showError('');
    const values = new FormData(form);
    try {
      const { error } = await client.auth.signInWithPassword({ email: values.get('email'), password: values.get('password') });
      if (error) throw error;
      form.reset();
      await updateIdentity();
    } catch (error) { showError(error.message); }
    finally { button.disabled = false; }
  };
}

async function updateIdentity() {
  const currentGeneration = ++generation;
  crumb.textContent = 'Checking access…';
  main.innerHTML = '<section class="auth-panel"><p>Checking your account…</p></section>';
  mode.innerHTML = '';
  try {
    // Verify identity with Auth; never authorize from local session data alone.
    const { data: { user }, error } = await client.auth.getUser();
    if (currentGeneration !== generation) return;
    if (error || !user) { login(); return; }
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
    main.innerHTML = `<section class="auth-panel"><h1>${approved ? 'Signed in' : 'Access pending'}</h1><p>${escape(user.email || '')}</p><p>${approved ? `Your role: <strong>${escape(membership.role)}</strong>` : 'An administrator must approve your membership.'}</p><p class="muted">${approved ? 'Account access is connected. Session and voting controls are being connected next.' : 'Contact House leadership for access.'}</p><p id="auth-error" role="alert"></p></section>`;
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
