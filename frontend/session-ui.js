import { createSessionApi } from './session-api.js';
const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const placeholder = '<div class="placeholder-document" aria-label="Bill content placeholder"><span></span><span></span><span></span><span></span><span></span></div>';
const documentBody = bill => bill.body ? `<div class="body-copy">${esc(bill.body)}</div>` : placeholder;

export function mountSessionUI(client, main) {
  const api = createSessionApi(client);
  let disposed = false, state, busy = false, reading = false, last = '', selected = null;
  main.innerHTML = '<h1>House session</h1><p>Loading session…</p>';
  const message = (text, isError = false) => {
    const el = main.querySelector('#session-message');
    if (el) { el.textContent = text; el.setAttribute('role', isError ? 'alert' : 'status'); }
  };
  function buttonsDisabled(value) {
    main.querySelectorAll('[data-command]').forEach(el => { el.disabled = value; });
  }
  async function read(force = false) {
    if (disposed || reading || (busy && !force)) return;
    reading = true;
    try {
      const data = await api.read();
      if (disposed) return;
      state = data;
      if (force || JSON.stringify(data) !== last) { last = JSON.stringify(data); render(); }
    } catch (error) {
      if (disposed) return;
      // Never retain stale data or actionable controls after access/read failure.
      last = '';
      state = null;
      main.innerHTML = '<h1>Session unavailable</h1><p id="session-message" role="alert"></p><button id="retry-session" class="secondary">Retry</button>';
      message(error.message, true);
      main.querySelector('#retry-session').onclick = () => read();
    } finally { reading = false; }
  }
  async function command(action) {
    if (disposed || busy || reading || !state || state.role !== 'admin') return;
    busy = true;
    buttonsDisabled(true);
    message('Saving…');
    try {
      await action();
      if (disposed) return;
      await read(true);
      if (!disposed && state) message('Saved');
    } catch (error) {
      if (!disposed) message(error.message, true);
    } finally {
      busy = false;
      if (!disposed) buttonsDisabled(reading);
    }
  }
  function openBill(id) {
    const bill = state?.bills.find(b => b.id === id);
    if (!bill || state.role !== 'admin') return;
    selected = id;
    const dialog = main.querySelector('#session-bill');
    dialog.innerHTML = `<div class="modal-top"><strong>Bill</strong><button class="close" aria-label="Close bill">×</button></div><h2>${esc(bill.title)}</h2>${documentBody(bill)}<div class="actions"><button class="secondary" data-command="hide" ${state.session?.current_bill_id !== id ? 'disabled' : ''}>Hide bill</button><button class="primary" data-command="present" ${!state.session ? 'disabled' : ''}>Present bill</button></div><p class="dialog-message" role="status"></p>`;
    dialog.querySelector('.close').onclick = () => { selected = null; dialog.close(); };
    dialog.oncancel = () => { selected = null; };
    dialog.querySelector('[data-command="present"]').onclick = () => {
      const sessionId = state.session?.id;
      if (sessionId) { selected = null; dialog.close(); command(() => api.present(sessionId, id)); }
    };
    dialog.querySelector('[data-command="hide"]').onclick = () => {
      const sessionId = state.session?.id;
      if (sessionId) { selected = null; dialog.close(); command(() => api.hide(sessionId)); }
    };
    dialog.showModal();
  }
  function render() {
    if (!state || disposed) return;
    const { session, bills, role, ballot } = state;
    const admin = role === 'admin', current = bills.find(b => b.id === session?.current_bill_id);
    document.querySelector('#crumb').textContent = admin ? 'Admin workspace' : 'Member view';
    main.querySelector('dialog')?.close();
    main.innerHTML = `<div class="heading"><div><h1>${admin ? 'Manage session' : 'House session'}</h1></div>${admin ? '<button class="secondary" disabled>Import agenda / plan</button><button class="secondary" disabled>Import bill</button>' : ''}</div><p id="session-message" role="status"></p>${admin ? `<section id="session-controls"><div><strong>${session ? 'Session active' : 'No active session'}</strong><p>${current ? 'Presenting: '+esc(current.title) : session ? 'Select a bill to present.' : ''}</p></div><button class="${session ? 'secondary' : 'primary'}" data-command="toggle">${session ? 'End session' : 'Start session'}</button></section><div id="bills">${bills.map(b => `<button class="bill connected-bill" data-bill="${esc(b.id)}"><span><strong>${esc(b.title)}</strong></span><span class="pill">${esc(b.status)}</span><span class="vote">${session?.current_bill_id === b.id ? 'Presenting' : 'Hidden'}</span><span>↗</span></button>`).join('') || '<div class="empty">No bills yet.</div>'}</div><dialog id="session-bill"></dialog>` : `<section id="presenter">${!session ? '<div class="waiting"><h2>No active session</h2></div>' : !current ? '<div class="waiting"><h2>Waiting for the next bill</h2></div>' : `<div class="presenter-top"><span class="pill Open">Currently being reviewed</span><span>${ballot?.status === 'open' ? 'Voting open' : 'Voting closed'}</span></div><h2>${esc(current.title)}</h2>${documentBody(current)}<p class="muted">Voting controls are not connected yet.</p>`}</section>`}<p class="demo">Session updates refresh every 3 seconds.</p>`;
    if (admin) {
      const sessionId = session?.id;
      main.querySelector('[data-command="toggle"]').onclick = () => command(() => sessionId ? api.end(sessionId) : api.start());
      main.querySelectorAll('[data-bill]').forEach(el => { el.onclick = () => openBill(el.dataset.bill); });
      if (selected && bills.some(b => b.id === selected)) openBill(selected);
    }
    if (busy || reading) buttonsDisabled(true);
  }
  // Re-enable after a successful refresh; respect per-control conditions.
  async function refresh() {
    if (disposed || busy || reading || document.hidden || main.querySelector('dialog[open]')) return;
    await read();
    if (!disposed && state) {
      const toggle = main.querySelector('[data-command="toggle"]');
      if (toggle) toggle.disabled = false;
    }
  }
  read().then(() => { const button = main.querySelector('[data-command="toggle"]'); if (button) button.disabled = false; });
  const timer = setInterval(refresh, 3000);
  document.addEventListener('visibilitychange', refresh);
  return () => { disposed = true; clearInterval(timer); document.removeEventListener('visibilitychange', refresh); main.querySelector('dialog')?.close(); };
}
