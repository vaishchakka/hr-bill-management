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

## Connected sign-in

Run `npm install`, configure `.env`, then `npm run dev`. Node serves the bundled official Supabase client and sign-in screen. The browser signs in directly with Supabase Auth, verifies identity with `getUser`, and reads only the signed-in user's membership under the existing RLS policy. No extra migration is needed for this step.

Connected mode is now the default. Approved accounts see their database role; unapproved accounts see Access pending. Session and voting controls are deliberately unavailable until transactional database commands and read permissions are implemented. The old demo API is rejected in connected mode. To explicitly run the old local wireframe, use `APP_MODE=demo npm run dev`.

`npm run build` bundles browser dependencies into ignored `frontend/generated/`; `npm run dev` and `npm start` run it automatically. The public config endpoint exposes only the project URL and publishable key. Never add secret keys there. A successful build and unit tests do not validate a real account login; test sign-in/sign-out, wrong passwords, and an unapproved second account manually before deployment.

### Permission helpers (step 1)

Run `supabase/migrations/202611170002_permission_helpers.sql` in the SQL Editor after migration 001. It adds private `is_member`, `is_admin`, `require_member`, and `require_admin` helpers. Admins count as approved members. Checks use `auth.uid()` and the membership table, never client-provided roles or user metadata. Anonymous access is revoked. Do not add `house_private` to the Data API exposed schemas.

Then run `supabase/tests/permission_helpers.sql` as a separate query in the SQL Editor. It asserts admin, member, unapproved, missing-identity, and self-promotion behavior using fixtures in a rolled-back transaction. If an assertion fails, run `ROLLBACK;` before retrying. These SQL tests require PostgreSQL/Supabase and are not part of `npm test`. This step does not enable any session or voting operations and needs no frontend changes.

### Read session state (step 2)

Run migration `202611170003_read_session_state.sql`, then run `supabase/tests/read_session_state.sql` separately. The read-only `get_house_state()` RPC requires approved membership and returns `{role, session, bills, ballot}`. Members receive only the currently presented bill; admins receive all bills. No active session yields a null session; an active session without a selected bill yields an empty bill list for members. No individual votes are returned. Raw table grants remain unchanged. The frontend is not switched to this RPC yet.

The SQL checks use rolled-back fixtures and temporarily mark any existing active session inactive within that transaction only. Run the full test script; on error, issue `ROLLBACK;` before retrying. These are integration checks to execute against Supabase, not Node unit tests.

### Start a session (step 3a)

Run migration `202611170004_start_house_session.sql`, then separately run `supabase/tests/start_house_session.sql` in full. `start_house_session()` is an authenticated admin-only RPC returning the active session object. Repeated starts return that same object, preserving any presented bill and making no redundant update. A transaction-level advisory lock serializes simultaneous starts even when no session row exists; the existing partial unique index also enforces one active session. Future end/present functions must acquire the same `(712804, 1)` lifecycle lock before row locks.

The SQL checks cover creation, repeated starts, snapshot consistency, preserved presentation, blocked member/unapproved/missing/anonymous identities, and denied raw writes. They do not execute a multi-connection concurrency test. All fixtures roll back. Starting a session does not create a ballot or publish notifications yet; Realtime subscriptions and the UI button are separate steps.

### End a session (step 3b)

Run migration `202611170005_end_house_session.sql`, then separately run the entire `supabase/tests/end_house_session.sql`. `end_house_session(p_session_id)` is admin-only, takes the shared lifecycle lock, locks its session and ballots, closes open ballots, and marks that session ended with no presented bill. Repeated calls return the ended session. An old session ID never ends a newer active session. Null IDs and unknown sessions are rejected. Votes, bill documents, and finalized ballots are retained. The test fixtures all roll back; the test is not a multi-connection concurrency test. No UI/Realtime wiring is included in this step.

### Present a bill (step 4a)

Run migration `202611170006_present_house_bill.sql`, then separately run all of `supabase/tests/present_house_bill.sql`. `present_house_bill(p_session_id, p_bill_id)` requires admin membership, an existing active session, and an existing bill. It takes the lifecycle lock, session row lock, document lock, and ordered ballot locks. Switching to a different bill closes all open ballots in that session, then changes the displayed bill atomically. Retrying the same bill preserves voting. It does not change bill lifecycle, create ballots, or open voting. Any existing bill, including a draft, may be presented for discussion.

Tests assert display changes, member visibility, closed old voting, retained finalized ballots and votes, safe retries, rejected invalid inputs and ended sessions, and denied unauthorized callers. They roll back all fixture changes. They have not been run against Supabase automatically. No frontend or Realtime changes are included here.
