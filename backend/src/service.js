export class ApiError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}
const requireAdmin = user => {
  if (user.role !== 'admin') throw new ApiError(403, 'Admin access required');
};
const findBill = (state, id) => {
  const bill = state.bills.find(b => b.id === id);
  if (!bill) throw new ApiError(404, 'Bill not found');
  return bill;
};
const ballotKey = state => `${state.session.id}:${state.session.billId}`;

export function snapshot(state, user) {
  const current = state.session.active && state.bills.find(b => b.id === state.session.billId);
  return {
    session: state.session,
    bills: user.role === 'admin' ? state.bills : current ? [current] : [],
    votes: current && state.votes[ballotKey(state)]?.[user.id]
      ? { [current.id]: state.votes[ballotKey(state)][user.id] } : {},
  };
}

export function execute(store, user, command) {
  if (!command || typeof command !== 'object') throw new ApiError(400, 'Invalid command');
  if (command.type !== 'vote') requireAdmin(user);
  store.transaction(state => {
    switch (command.type) {
      case 'start-session':
        if (!state.session.active) {
          state.session = { active: true, billId: null, id: state.session.id + 1 };
          // An open ballot must never carry over into another session.
          state.bills.forEach(b => { if (b.status === 'Open') b.status = 'Review'; });
        }
        break;
      case 'end-session':
        state.session.active = false;
        state.session.billId = null;
        state.bills.forEach(b => { if (b.status === 'Open') b.status = 'Review'; });
        break;
      case 'present-bill': {
        findBill(state, command.billId);
        if (!state.session.active) {
          state.session = { active: true, billId: null, id: state.session.id + 1 };
          state.bills.forEach(b => { if (b.status === 'Open') b.status = 'Review'; });
        }
        state.session.billId = command.billId;
        break;
      }
      case 'hide-bill':
        state.session.billId = null;
        break;
      case 'set-status': {
        if (!['Draft', 'Review', 'Open', 'Passed', 'Not passed'].includes(command.status)) {
          throw new ApiError(400, 'Invalid bill status');
        }
        const bill = findBill(state, command.billId);
        if (command.status === 'Open' && (!state.session.active || state.session.billId !== bill.id)) {
          throw new ApiError(409, 'Present the bill before opening voting');
        }
        bill.status = command.status;
        break;
      }
      case 'vote': {
        if (!['Yea', 'Nay', 'Abstain'].includes(command.choice)) throw new ApiError(400, 'Invalid vote');
        if (!state.session.active || state.session.billId !== command.billId) {
          throw new ApiError(409, 'This bill is not being presented');
        }
        if (findBill(state, command.billId).status !== 'Open') throw new ApiError(409, 'Voting is closed');
        const key = ballotKey(state);
        state.votes[key] ||= {};
        // Updating a vote replaces the member's existing choice rather than counting twice.
        state.votes[key][user.id] = command.choice;
        break;
      }
      default: throw new ApiError(400, 'Unknown command');
    }
  });
  return snapshot(store.read(), user);
}
