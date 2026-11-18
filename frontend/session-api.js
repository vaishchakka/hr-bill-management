export function createSessionApi(client) {
  async function rpc(name, args) {
    const { data, error } = await client.rpc(name, args);
    if (error) throw new Error(error.message || 'Unable to update session');
    return data;
  }
  return {
    read: () => rpc('get_house_state'),
    start: () => rpc('start_house_session'),
    end: sessionId => rpc('end_house_session', { p_session_id: sessionId }),
    present: (sessionId, billId) => rpc('present_house_bill', { p_session_id: sessionId, p_bill_id: billId }),
    hide: sessionId => rpc('hide_house_bill', { p_session_id: sessionId }),
  };
}
