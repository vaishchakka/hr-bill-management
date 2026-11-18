// Events are hints: always fetch the authorized database snapshot afterward.
export function watchSession(client, { refresh, status }, timers = globalThis) {
  let disposed = false, channel, running = false, pending = false;
  async function requestRefresh() {
    if (disposed) return;
    pending = true;
    if (running) return;
    running = true;
    try {
      while (pending && !disposed) {
        pending = false;
        await refresh();
      }
    } finally { running = false; }
  }
  async function connect() {
    try {
      await client.realtime.setAuth();
      if (disposed) return;
      channel = client.channel('house:session', { config: { private: true } })
        .on('broadcast', { event: 'state_changed' }, requestRefresh)
        .subscribe(value => {
          if (disposed) return;
          status(value === 'SUBSCRIBED' ? 'Live updates connected' : 'Reconnecting · periodic refresh active');
          if (value === 'SUBSCRIBED') void requestRefresh();
        });
    } catch {
      if (!disposed) status('Live updates unavailable · periodic refresh active');
    }
  }
  status('Connecting live updates…');
  void connect();
  // Subscribe first; reconcile on join/rejoin. Also fetch immediately for outages.
  void requestRefresh();
  const timer = timers.setInterval(requestRefresh, 15000);
  return {
    refresh: requestRefresh,
    dispose() {
      disposed = true;
      timers.clearInterval(timer);
      if (channel) void client.removeChannel(channel);
    },
  };
}
