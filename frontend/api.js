async function request(role, path, options = {}) {
  const response = await fetch(`/api/${path}`, {
    ...options,
    headers: { 'Content-Type': 'application/json', 'X-Demo-Role': role },
  });
  const data = await response.json();
  if (!response.ok) throw new Error(data.error || 'Request failed');
  return data;
}
export const getState = role => request(role, 'state');
export const sendCommand = (role, command) => request(role, 'commands', {
  method: 'POST', body: JSON.stringify(command),
});
