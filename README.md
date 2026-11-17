# GT House Leadership

A bare-bones session and voting prototype. The local application now separates the frontend from a shared backend. No framework or package installation is required; use Node 22 or later.

## Run locally

```sh
npm run dev
```

Open http://localhost:4317. `npm start` runs without file watching. `npm test` runs backend behavior tests.

Open two tabs, put one in Admin and the other in Member. Present a bill in Admin, then set its status to Voting open. The member screen follows within about 1.5 seconds. Ending the session hides the bill and closes voting. Import buttons remain inactive wireframe placeholders.

## Source layout

- `frontend/index.html`: page structure.
- `frontend/style.css`: layout, GT colors, light/dark themes.
- `frontend/app.js`: UI rendering and event handlers; keeps only presentation state in memory and theme preference in local storage.
- `frontend/api.js`: HTTP client; the only frontend module that calls the API.
- `backend/src/server.js`: HTTP routes, local demo identity, static frontend serving.
- `backend/src/service.js`: session/bill/vote rules and role checks; members receive only the current bill and their own vote.
- `backend/src/store.js`: atomic JSON persistence adapter; runtime data goes in ignored `backend/data/state.json`.
- `backend/test/`: permission, visibility, voting, and session isolation tests.

The backend serves the frontend on one origin, but the modules are separate. No need for separate servers, CORS configuration, or a framework for this prototype.

## API

`GET /api/state` returns the role-filtered session, bills, and current user's vote.

`POST /api/commands` accepts JSON with a `type`: `start-session`, `end-session`, `present-bill` (billId), `hide-bill`, `set-status` (billId, status), or `vote` (billId, choice). Errors use an HTTP error status and `{ "error": "message" }`.

The backend owns all shared state. Votes are keyed by session, bill, and member, so changing a choice replaces it and a new session starts a new ballot. Voting can open only for the presented bill. Status changes and votes are validated server-side.

## Prototype boundaries

This is a **local development server**, bound to 127.0.0.1. `X-Demo-Role` and the role switcher deliberately simulate one user and are not authentication. Do not expose this server publicly. Other tabs share session state but also share the single demo voting identity.

For a real launch: replace the demo identity with verified login and server-side role assignments, replace the JSON adapter with a transactional database, and deploy the backend to an appropriate server runtime. Deploy this application to a hosting service that supports Node.js. Import processing, real membership, audit history, quorum/majority rules, and finalized ballot results are not implemented. Manual status changes remain part of the wireframe.

JSON storage is suitable for one local process. It is not a multi-process database. Set `DATA_FILE` to change its location, and `PORT` to change the port.

## Supabase setup (in progress)

Copy `.env.example` to `.env` and fill in the project URL and publishable key. `.env` is ignored by Git. Run `npm run check:supabase` to verify project access; this probes Auth settings, not database tables or login.

In your Supabase project's SQL Editor, run `supabase/migrations/202611170001_initial_schema.sql` once. It creates memberships, bills, sessions, ballots, and votes. A unique vote key prevents duplicate member votes per ballot. Row-level security is enabled and application data is denied by default; users can only read their own assigned membership.

This is a connection/schema foundation. The running app still uses the JSON demo backend. Database commands, authenticated login, membership assignment, and Realtime subscriptions are not wired yet. Do not disable row-level security to make the demo work. The next migration will add authenticated read policies and transactional RPCs before enabling database voting. Do not run the demo role switcher as an authorization mechanism against Supabase.
