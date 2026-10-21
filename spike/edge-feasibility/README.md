# P0 feasibility spike — can a Deno Edge Function do what Cloud Functions do today?

**Disposable. Not integrated. Nothing under `lib/` or `functions/` depends on this directory, and it
is not a Supabase project layout.** Delete it once the decision below is recorded. If a variant wins,
its winning 20 lines get rewritten inside `supabase/functions/<name>/` — they are not lifted as-is.

It exists because two load-bearing assumptions in the migration plan are **unproven**:

| # | Assumption at risk | Why it matters |
|---|---|---|
| Q1 | "The Edge Function verifies a Firebase ID token with jose + Google's x509 certs" | every trusted call depends on it |
| Q2 | "`firebase-admin` (or a REST fallback) runs in a Deno isolate and can do a **transaction that reads inside itself**" | **9 sites** in `functions/index.js` use `db.runTransaction` with inner `tx.get` — `173` (stock/coupon/counter/idempotency), `515`, `670`, `704`, `838`, `870`, `920`, `955`, `1493`. If inner reads do not work, checkout is a redesign, not a port |

Nothing here is asserted on behalf of the runtime — each transport is *attempted* and reported.

---

## Prerequisites (measured on this machine, 2026-10-21)

- `deno` **is on PATH**: `C:\Users\ASUS\AppData\Local\Microsoft\WinGet\Links\deno`. Version **not checked**.
- `docker` **is NOT on PATH** → `supabase functions serve` cannot run locally. This spike therefore runs
  under plain Deno. That is **necessary but not sufficient** evidence: Supabase's Edge runtime is Deno
  with its own module resolution and Node-compat behaviour, so a PASS here means "the code can work",
  not "it works in `supabase functions deploy`". Record a second observation from a real deployment
  before trusting it.
- Firestore emulator (the stack in `docs/local-demo.md`) for the default target: it listens on `8080`,
  which is what this spike expects.

## Run it — read/write against the local emulator only

```bash
cd spike/edge-feasibility
deno task emulator          # = deno run --allow-env --allow-net --allow-read probe.ts --target=emulator
```

Optional: `--rounds=16` (contention level), `FIRESTORE_EMULATOR_HOST=127.0.0.1:8080`.

Against the emulator you need **no credentials at all** — the spike mints a throwaway RSA key pair
locally so the client libraries have something to hold, and never contacts Google for auth.

## Run the read-only live probe (touches a real project, writes nothing)

```bash
cd spike/edge-feasibility
export SPIKE_PROJECT_ID=om-events-store
export SPIKE_SA_JSON=/d/path/to/service-account.json     # outside the repo; never committed
deno task live-read
```

`live-read` performs GETs and one `:beginTransaction` discovery call. The two write probes are
**BLOCKED** unless you also pass `--allow-live-write` (or `I_ALLOW_LIVE_WRITE=1`) — that is deliberate,
it is the only thing that keeps this spike from creating documents in a real database.

## The token probe needs one thing the spike cannot fabricate

```bash
export SPIKE_REAL_ID_TOKEN=<a real Firebase ID token>    # then re-run any target
```

Get it from a signed-in browser session (DevTools console of the hosted app):
`await firebase.auth().currentUser.getIdToken()`. It is a short-lived bearer credential — paste it into
an environment variable for one run, do not commit it, do not paste it into a chat or a log.

**Emulator tokens will not pass this probe.** The Auth emulator mints JWTs that are not signed by
Google's private keys, so `token/real-firebase-id-token` correctly FAILs against `demo-om-events`.
That is why Q1 can only be closed against a real project — and it is also the reason the eventual
Edge Function needs an explicit `emulator | prod` verification switch that can never be enabled in a
production build.

## Reading the output

```
[PASS   ] token/self-signed-roundtrip        12ms  claims present: sub/aud/iss=true/true/true
[FAIL   ] T1 firebase-admin (gRPC) :: load   830ms  TypeError: ...
[FAIL   ] T3 raw Firestore REST :: lost-update-guard  LOST UPDATE (final < committed) — rounds=8; committed=8; final=3
```

| Verdict | Meaning |
|---|---|
| `PASS` | the runtime itself reported success — but read the detail, `tx-with-inner-read` PASS says *which* mode it used |
| `FAIL` | attempted and refused. The detail carries the runtime's own words |
| `BLOCKED` | not attempted because a required input (env var, `--allow-live-write`) was absent. Not a negative result |
| `SKIP` | intentionally not run |

The last two lines of the run are the answer: which transports survived `lost-update-guard`, or
`NO TRANSPORT PASSED THE LOST-UPDATE GUARD`.

## Decision table — do this with the result

| Observation | Consequence for the migration |
|---|---|
| T1 **and** T2 pass `lost-update-guard` cleanly | Port `requireCaller`/`requireRole`/`runTransaction` mostly as-is. Keep `functions/` as the rollback target |
| Only T2 `(REST)` passes | Same port, but pin `preferRest` and re-run the contention probe at `--rounds=32` before accepting it |
| T1/T2 load fine but report `SERIALISED BUT ABORTED` | Usable, but the Edge handler needs an explicit retry/backoff wrapper around every one of the 9 tx sites. That is new code, so add it to the estimate |
| Only T3 (`raw REST`) survives, and its `native=no-transaction` | **The migration is not a port.** Firestore REST gave no transaction handle, so stock, coupon redemption, the order-number counter and the idempotency lock must be redesigned around commit preconditions — or those 9 sites stay on Cloud Functions, which means Blaze billing and the decision you already declined |
| Nothing passes | Stop. Supabase Edge Functions cannot host the trusted tier for this schema. Revisit Cloud Functions (Blaze) or a different trusted host |
| `token/*` probes FAIL while Firestore passes | No trusted tier is safe without verified identity. Fix verification first, ignore everything else |

## What this spike does **not** prove

Cold-start latency; whether Supabase Secrets injection works; `supabase functions deploy` module
resolution; region round-trip time from `ap-south-1` to Firestore `asia-south1`; request size limits;
rate limiting across isolates; authorization correctness; anything about the 3 Firestore triggers;
and whether checkout works. It answers Q1 and Q2 only.

## Constraints this spike obeys

No Firebase Admin or service-role credential is ever printed (only `client_email`-free messages, key
ids and lengths); the service-account file is read from a path **outside** the repo; writes to a real
project require an explicit, separate flag; the document it touches is `spike_tx/probe`, which is
meaningless to the app and safe to delete.
