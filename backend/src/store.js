import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';

export function initialState() {
  return {
    bills: [1, 2, 3].map(id => ({ id, title: `Bill ${id}`, category: 'Bill', status: 'Draft' })),
    session: { active: false, billId: null, id: 0 },
    votes: {},
  };
}

// Synchronous transactions are serialized by Node's event loop. Replace this
// adapter with a database before running multiple server processes.
export function createStore(file) {
  let state = file && existsSync(file) ? JSON.parse(readFileSync(file, 'utf8')) : initialState();
  return {
    read: () => structuredClone(state),
    transaction(change) {
      const next = structuredClone(state);
      change(next);
      if (file) {
        mkdirSync(dirname(file), { recursive: true });
        writeFileSync(`${file}.tmp`, JSON.stringify(next, null, 2));
        renameSync(`${file}.tmp`, file);
      }
      state = next;
    },
  };
}
