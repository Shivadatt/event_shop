// P0 feasibility spike — DISPOSED AFTER READING. Not part of the Flutter app (`lib/`), not part of
// `functions/`, never deployed, never imported by production code.
//
// It answers exactly two questions, with evidence instead of assumptions:
//   TOKEN  : can a Supabase-Edge-shaped Deno isolate verify a Firebase ID token (RS256, Google x509
//            certs) using only WebCrypto + jose?
//   FIRESTORE: can a Deno isolate reach Cloud Firestore and run a TRANSACTION THAT READS INSIDE
//            ITSELF — the shape every one of the 9 `db.runTransaction` sites in functions/index.js
//            depends on — and does it actually prevent lost updates under concurrency?
//
// Three transports are probed independently. Nothing here assumes any of them works; each is
// attempted and reported as PASS / FAIL / BLOCKED / SKIP with the runtime's own words.
//
//   T1  npm:firebase-admin          (what functions/lib/server.js uses today, gRPC by default)
//   T2  npm:@google-cloud/firestore (the underlying client, probed on gRPC and on its REST transport)
//   T3  raw Firestore REST + self-minted service-account JWT (zero npm deps)
//
// Usage: see README.md. Default target is `emulator`; a `live` target refuses to write unless
// --allow-live-write is passed.

import * as jose from 'jose';
import {
  exportJWK,
  generateKeyPair,
  importJWK,
  importPKCS8,
  importX509,
  jwtVerify,
  SignJWT,
} from 'jose';

// --------------------------------------------------------------------------------------------
// Verdict log
// --------------------------------------------------------------------------------------------
type Result = 'PASS' | 'FAIL' | 'BLOCKED' | 'SKIP';
type Verdict = { id: string; result: Result; ms: number; detail: string };
const verdicts: Verdict[] = [];

function record(id: string, result: Result, started: number, detail: string): void {
  verdicts.push({ id, result, ms: Math.round(performance.now() - started), detail: detail.slice(0, 400) });
  console.log(`[${result.padEnd(7)}] ${id.padEnd(34)} ${Math.round(performance.now() - started)}ms  ${detail.slice(0, 200)}`);
}

async function attempt(id: string, fn: () => Promise<[Result, string]>): Promise<void> {
  const started = performance.now();
  try {
    const [result, detail] = await fn();
    record(id, result, started, detail);
  } catch (error) {
    const name = (error as Error)?.name ?? 'Error';
    const message = (error as Error)?.message ?? String(error);
    // A thrown import/parse error is itself the answer: this runtime cannot load that package.
    record(id, 'FAIL', started, `${name}: ${message}`);
  }
}

// --------------------------------------------------------------------------------------------
// Config (env only; no secret is ever printed)
// --------------------------------------------------------------------------------------------
const args = Deno.args;
const TARGET = arg('--target') ?? Deno.env.get('SPIKE_TARGET') ?? 'emulator';
const ALLOW_LIVE_WRITE = args.includes('--allow-live-write') || Deno.env.get('I_ALLOW_LIVE_WRITE') === '1';
const ROUNDS = Number(arg('--rounds') ?? Deno.env.get('SPIKE_TX_ROUNDS') ?? '8');
const DATABASE = Deno.env.get('SPIKE_FIRESTORE_DB') ?? '(default)';
const DOC = 'spike_tx/probe';

function arg(flag: string): string | undefined {
  const hit = args.find((a) => a.startsWith(`${flag}=`));
  return hit ? hit.slice(flag.length + 1) : undefined;
}

const PROJECT_ID = Deno.env.get('SPIKE_PROJECT_ID') ?? (TARGET === 'emulator' ? 'demo-om-events' : '');

// Emulator never has real credentials; the probe mints a throwaway RSA key pair so the client
// libraries have *a* credential object to accept. Live uses SPIKE_SA_JSON (path to a file).
const saJsonPath = Deno.env.get('SPIKE_SA_JSON') ?? '';

type ServiceAccount = { projectId: string; clientEmail: string; privateKey: string };

function derToPem(der: ArrayBuffer, label: string): string {
  const bytes = new Uint8Array(der);
  let binary = '';
  for (let i = 0; i < bytes.length; i += 1) binary += String.fromCharCode(bytes[i]);
  const b64 = btoa(binary);
  const body = b64.replace(/(.{64})/g, '$1\n').trim();
  return `-----BEGIN ${label}-----\n${body}\n-----END ${label}-----\n`;
}

async function throwawayServiceAccount(): Promise<ServiceAccount> {
  const pair = (await crypto.subtle.generateKey(
    { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
    true,
    ['sign', 'verify'],
  )) as CryptoKeyPair;
  const pkcs8 = await crypto.subtle.exportKey('pkcs8', pair.privateKey);
  return {
    projectId: PROJECT_ID || 'spike-local',
    clientEmail: `spike@${PROJECT_ID || 'spike-local'}.iam.gserviceaccount.com`,
    privateKey: derToPem(pkcs8, 'PRIVATE KEY'),
  };
}

async function loadServiceAccount(): Promise<ServiceAccount> {
  if (TARGET === 'emulator') return await throwawayServiceAccount();
  if (!saJsonPath) throw new Error('live target needs SPIKE_SA_JSON=/path/to/service-account.json');
  const raw = await Deno.readTextFile(saJsonPath);
  const parsed = JSON.parse(raw);
  return { projectId: parsed.project_id, clientEmail: parsed.client_email, privateKey: parsed.private_key };
}

let sa: ServiceAccount | null = null;
async function serviceAccount(): Promise<ServiceAccount> {
  if (!sa) sa = await loadServiceAccount();
  return sa;
}

const emulatorHost = Deno.env.get('FIRESTORE_EMULATOR_HOST') ?? '127.0.0.1:8080';
if (TARGET === 'emulator') Deno.env.set('FIRESTORE_EMULATOR_HOST', emulatorHost);

const restOrigin = TARGET === 'emulator'
  ? `http://${emulatorHost}`
  : `https://${PROJECT_ID}.firestore.googleapis.com`;

// The default database id is written `(default)` in gRPC/display but may need `__default__` in a
// REST path. Not assumed: probeRestSurface() asks both and uses the one that answers.
const dbIdCandidates = DATABASE === '(default)' ? ['(default)', '__default__'] : [DATABASE];
let activeDbId = dbIdCandidates[0];

function restDocumentsFor(dbId: string): string {
  return `${restOrigin}/v1/projects/${PROJECT_ID}/databases/${dbId}/documents`;
}

// --------------------------------------------------------------------------------------------
// TOKEN probes
// --------------------------------------------------------------------------------------------
async function probeToken(): Promise<void> {
  // T-a: jose + WebCrypto can mint and verify an RS256 token with our own checks. Offline, so a
  // FAIL here means the verifier itself cannot run in Deno — nothing else matters.
  await attempt('token/self-signed-roundtrip', async () => {
    const { privateKey, publicKey } = await generateKeyPair('RS256', { extractable: true });
    const publicJwk = await exportJWK(publicKey);
    const token = await new SignJWT({ uid: 'spike', firebase: { sign_in_provider: 'password' } })
      .setProtectedHeader({ alg: 'RS256', kid: 'spike-key' })
      .setIssuer('https://securetoken.google.com/spike-project')
      .setAudience('spike-project')
      .setSubject('a'.repeat(42))
      .setIssuedAt()
      .setExpirationTime('5m')
      .sign(privateKey);
    const jwt = await jwtVerify(
      token,
      await importJWK({ ...publicJwk, kid: 'spike-key', alg: 'RS256', use: 'sig' }, 'RS256'),
    );
    const p = jwt.payload;
    const ok = p.sub === 'a'.repeat(42) && p.aud === 'spike-project' &&
      p.iss === 'https://securetoken.google.com/spike-project';
    return [ok ? 'PASS' : 'FAIL', `claims present: sub/aud/iss=${Boolean(p.sub)}/${Boolean(p.aud)}/${Boolean(p.iss)}`];
  });

  // T-b: can the isolate reach Google's Firebase cert endpoint AND turn a returned PEM into a
  // verify key? That is the whole credential path except a real token, which T-c covers.
  await attempt('token/google-cert-endpoint', async () => {
    const res = await fetch('https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com');
    if (!res.ok) return ['FAIL', `HTTP ${res.status}`];
    const certs = await res.json() as Record<string, string>;
    const kids = Object.keys(certs);
    if (kids.length === 0) return ['FAIL', 'no kids returned'];
    const key = await importX509(certs[kids[0]], 'RS256');
    const shape = key instanceof CryptoKey ? `CryptoKey/${key.algorithm.name}` : typeof key;
    return ['PASS', `${kids.length} cert(s), importX509 -> ${shape}, cache-control="${res.headers.get('cache-control') ?? ''}"`];
  });

  // T-c: full verification of a real Firebase ID token, kid -> cert -> jwtVerify, with the exact
  // issuer/audience assertions the trusted tier must make. Needs a live token; never fabricated.
  const real = Deno.env.get('SPIKE_REAL_ID_TOKEN') ?? '';
  if (!real) {
    record('token/real-firebase-id-token', 'BLOCKED', performance.now(), 'set SPIKE_REAL_ID_TOKEN (from a browser session) to run');
    return;
  }
  await attempt('token/real-firebase-id-token', async () => {
    const res = await fetch('https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com');
    const certs = await res.json() as Record<string, string>;
    // JWT headers are base64URL, which atob rejects (- and _ are not base64 chars).
    const header = JSON.parse(atob(real.split('.')[0].replace(/-/g, '+').replace(/_/g, '/')));
    const pem = certs[header.kid];
    if (!pem) return ['FAIL', `kid ${header.kid} not in the cert set (cache it and refresh on miss)`];
    const key = await importX509(pem, 'RS256');
    const { payload } = await jwtVerify(real, key, {
      issuer: `https://securetoken.google.com/${PROJECT_ID}`,
      audience: PROJECT_ID,
    });
    const claims = (payload.firebase ?? {}) as Record<string, unknown>;
    const ok = typeof payload.sub === 'string' && payload.sub.length > 0 && payload.sub.length <= 128 &&
      claims.sign_in_provider !== undefined;
    return [
      ok ? 'PASS' : 'FAIL',
      `sub=${String(payload.sub).slice(0, 6)}…, provider=${String(claims.sign_in_provider)}, hasRoleClaim=${payload.role !== undefined}`,
    ];
  });
}

// --------------------------------------------------------------------------------------------
// Firestore transports. Each returns the same tiny capability surface so the harness below can
// ask all three the same questions.
// --------------------------------------------------------------------------------------------
type Bump = { committed: boolean; read: number; native: 'transaction' | 'no-transaction' };

type Transport = {
  name: string;
  seed: (n: number) => Promise<void>;
  read: () => Promise<number | null>;
  bump: () => Promise<Bump>;
  note: string;
};

async function transportFirebaseAdmin(): Promise<Transport> {
  const account = await serviceAccount();
  const adminMod = await import('npm:firebase-admin@^13.0.1');
  const admin = adminMod.default ?? adminMod;
  if (admin.apps.length === 0) {
    // Mirrors functions/lib/server.js as closely as a Deno isolate can: ADC replaced by an explicit
    // credential, because Deno has no metadata server and no ADC file.
    admin.initializeApp({
      credential: admin.credential.cert({
        projectId: account.projectId,
        clientEmail: account.clientEmail,
        privateKey: account.privateKey,
      }),
      projectId: account.projectId,
    });
  }
  const db = admin.firestore();
  const ref = db.doc(DOC);
  return {
    name: 'T1 firebase-admin (gRPC)',
    note: 'the library functions/lib/server.js uses today. `preferRest` is probed on T2 only — it is a @google-cloud/firestore option, and claiming the admin wrapper forwards it would be an assumption.',
    seed: async (n: number) => { await ref.set({ n, at: admin.firestore.Timestamp.now() }); },
    read: async () => {
      const snap = await ref.get();
      return snap.exists ? Number(snap.data()?.n ?? -1) : null;
    },
    bump: async () => db.runTransaction(async (tx) => {
      const snap = await tx.get(ref); // <-- the inner read the 9 production tx sites require
      const n = snap.exists ? Number(snap.data()?.n ?? 0) : 0;
      tx.set(ref, { n: n + 1 }, { merge: true });
      return { committed: true, read: n, native: 'transaction' as const };
    }),
  };
}

async function transportGcpClient(preferRest: boolean): Promise<Transport> {
  const account = await serviceAccount();
  const { Firestore } = await import('npm:@google-cloud/firestore@^7.10.0');
  // On an emulator, passing explicit credentials can force an auth path the emulator never answers.
  // The library is supposed to switch to unauthenticated credentials from FIRESTORE_EMULATOR_HOST
  // alone — so the credentials object is deliberately withheld there, and the result is the finding.
  const db = new Firestore({
    projectId: account.projectId,
    ...(TARGET === 'emulator' ? {} : {
      credentials: { client_email: account.clientEmail, private_key: account.privateKey },
    }),
    preferRest,
  });
  const ref = db.doc(DOC);
  return {
    name: preferRest ? 'T2 @google-cloud/firestore (REST)' : 'T2 @google-cloud/firestore (gRPC)',
    note: 'underlying client, no firebase-admin wrapper',
    seed: async (n: number) => { await ref.set({ n }); },
    read: async () => {
      const snap = await ref.get();
      return snap.exists ? Number(snap.data()?.n ?? -1) : null;
    },
    bump: async () => db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const n = snap.exists ? Number(snap.data()?.n ?? 0) : 0;
      tx.set(ref, { n: n + 1 });
      return { committed: true, read: n, native: 'transaction' as const };
    }),
  };
}

async function restToken(): Promise<string> {
  if (TARGET === 'emulator') return ''; // the emulator ignores credentials
  const account = await serviceAccount();
  // Google service-account keys are PKCS#1 ("BEGIN RSA PRIVATE KEY"). Deno WebCrypto `importKey`
  // only takes PKCS#8, so a PKCS#1 importer is needed — and `importPKCS1` only exists in jose v6.
  // Looked up defensively rather than assumed, and reported as BLOCKED when absent.
  const pkcs1 = (jose as Record<string, unknown>).importPKCS1 as
    | ((pem: string, alg: string) => Promise<unknown>)
    | undefined;
  let key;
  try {
    key = await importPKCS8(account.privateKey, 'RS256');
  } catch (pkcs8Error) {
    if (!pkcs1) {
      throw new Error(
        `service-account key is not PKCS#8 (${(pkcs8Error as Error).message}) and this jose build has no importPKCS1 — bump jose to ^6, or convert with: openssl pkcs8 -topk8 -nocrypt -in key.json-derived.pem`,
      );
    }
    key = await pkcs1(account.privateKey, 'RS256');
  }
  const now = Math.floor(Date.now() / 1000);
  const assertion = await new SignJWT({ scope: 'https://www.googleapis.com/auth/datastore' })
    .setProtectedHeader({ alg: 'RS256' })
    .setIssuer(account.clientEmail)
    .setSubject(account.clientEmail)
    .setAudience('https://oauth2.googleapis.com/token')
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(key);
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${assertion}`,
  });
  if (!res.ok) throw new Error(`token exchange HTTP ${res.status}: ${(await res.text()).slice(0, 160)}`);
  const body = await res.json() as { access_token?: string };
  if (!body.access_token) throw new Error('token exchange returned no access_token');
  return body.access_token;
}

async function transportRawRest(): Promise<Transport> {
  const token = await restToken();
  const headers: Record<string, string> = { 'content-type': 'application/json' };
  if (token) headers.authorization = `Bearer ${token}`;

  // Firestore REST resource names are host-less: projects/p/databases/d/documents/coll/id.
  const docs = restDocumentsFor(activeDbId);
  const [coll, id] = DOC.split('/');
  const docName = `projects/${PROJECT_ID}/databases/${activeDbId}/documents/${coll}/${id}`;
  const docUrl = `${docs}/${coll}/${id}`;
  const commitUrl = `${docs}:commit`;
  const beginUrl = `${docs}:beginTransaction`;

  async function readNow(): Promise<number | null> {
    const res = await fetch(docUrl, { headers });
    if (res.status === 404) return null;
    if (!res.ok) throw new Error(`read HTTP ${res.status}`);
    const body = await res.json() as { fields?: Record<string, { integerValue?: string }> };
    return Number(body.fields?.n?.integerValue ?? -1);
  }

  async function commit(body: Record<string, unknown>): Promise<{ status: number; text: string }> {
    const res = await fetch(commitUrl, { method: 'POST', headers, body: JSON.stringify(body) });
    return { status: res.status, text: await res.text() };
  }

  const write = (value: number) => ({
    update: { name: docName, fields: { n: { integerValue: String(value) } } },
  });

  let transaction = '';
  let note = `no npm dependencies; db="${activeDbId}"`;
  // Discover, do not assume: does the REST surface hand out a transaction handle at all?
  try {
    const res = await fetch(beginUrl, { method: 'POST', headers, body: '{}' });
    const text = await res.text();
    note += `; :beginTransaction -> HTTP ${res.status}`;
    if (res.ok) {
      const body = JSON.parse(text) as { transaction?: string };
      transaction = body.transaction ?? '';
      if (!transaction) note += ' but no transaction id in the body';
    }
  } catch (error) {
    note += `; :beginTransaction threw ${(error as Error).name}`;
  }

  return {
    name: 'T3 raw Firestore REST',
    note,
    seed: async (n: number) => {
      const committed = await commit({ writes: [write(n)] });
      if (committed.status !== 200) {
        throw new Error(`seed commit HTTP ${committed.status}: ${committed.text.slice(0, 140)}`);
      }
    },
    read: readNow,
    bump: async () => {
      if (!transaction) {
        // Unconditional read-then-write: expressible, but NOT safe for the money path. The
        // lost-update probe below is expected to catch exactly this.
        const before = await readNow() ?? 0;
        const committed = await commit({ writes: [write(before + 1)] });
        if (committed.status !== 200) throw new Error(`commit HTTP ${committed.status}`);
        return { committed: true, read: before, native: 'no-transaction' as const };
      }
      const res = await fetch(`${docUrl}?transaction=${encodeURIComponent(transaction)}`, { headers });
      if (!res.ok) throw new Error(`transaction read HTTP ${res.status}`);
      const body = await res.json() as { fields?: Record<string, { integerValue?: string }> };
      const before = Number(body.fields?.n?.integerValue ?? 0);
      const committed = await commit({ transaction, writes: [write(before + 1)] });
      if (committed.status !== 200) throw new Error(`commit HTTP ${committed.status}: ${committed.text.slice(0, 140)}`);
      return { committed: true, read: before, native: 'transaction' as const };
    },
  };
}

// --------------------------------------------------------------------------------------------
// REST surface discovery: which database id does this project's REST path actually accept?
// --------------------------------------------------------------------------------------------
async function probeRestSurface(): Promise<void> {
  let token = '';
  try {
    token = await restToken();
  } catch (error) {
    record('T3 raw REST :: credentials', 'FAIL', performance.now(), `${(error as Error).name}: ${(error as Error).message}`);
    return;
  }
  const headers: Record<string, string> = { 'content-type': 'application/json' };
  if (token) headers.authorization = `Bearer ${token}`;

  for (const dbId of dbIdCandidates) {
    const started = performance.now();
    const docs = restDocumentsFor(dbId);
    let body = '';
    let status = 0;
    try {
      const res = await fetch(`${docs}/${DOC}`, { headers });
      status = res.status;
      body = await res.text();
    } catch (error) {
      record(`T3 raw REST :: db="${dbId}"`, 'FAIL', started, `fetch threw ${(error as Error).name}: ${(error as Error).message}`);
      continue;
    }
    let begin = '';
    let txHandle = false;
    try {
      const res = await fetch(`${docs}:beginTransaction`, { method: 'POST', headers, body: '{}' });
      const text = await res.text();
      txHandle = res.ok && /"transaction"\s*:/.test(text);
      begin = `:beginTransaction HTTP ${res.status}${txHandle ? ' + transaction handle' : ''} ${text.slice(0, 70)}`;
    } catch (error) {
      begin = `:beginTransaction threw ${(error as Error).name}`;
    }

    // Unambiguous classification. A 404 alone proves nothing: Firestore answers 404 both for "no
    // such document" (database id is right) and for "no such database" (id is wrong).
    const lower = body.toLowerCase();
    const databaseRejected = status === 404 && lower.includes('database');
    const documentMissing = status === 404 && !databaseRejected;
    const works = status === 200 || documentMissing;
    record(
      `T3 raw REST :: db="${dbId}"`,
      works ? 'PASS' : 'FAIL',
      started,
      `read HTTP ${status}${status === 200 ? ' (doc exists)' : documentMissing ? ' (doc absent, database id ACCEPTED)' : ''}; ${begin}; body=${body.slice(0, 110)}`,
    );
    if (works && activeDbId !== dbId) activeDbId = dbId;
  }
  console.log(`(raw REST will use database id "${activeDbId}")`);
}

// --------------------------------------------------------------------------------------------
// The two decisive Firestore assertions, run identically against every transport
// --------------------------------------------------------------------------------------------
async function harness(transport: Transport): Promise<void> {
  const writesAllowed = TARGET === 'emulator' || ALLOW_LIVE_WRITE;

  await attempt(`${transport.name} :: import+connect`, async () => {
    const value = await transport.read();
    return ['PASS', `read ok (doc ${value === null ? 'absent' : `n=${value}`})`];
  });

  if (!writesAllowed) {
    record(`${transport.name} :: tx-with-inner-read`, 'BLOCKED', performance.now(), 'live target without --allow-live-write');
    record(`${transport.name} :: lost-update-guard`, 'BLOCKED', performance.now(), 'live target without --allow-live-write');
    return;
  }

  await attempt(`${transport.name} :: tx-with-inner-read`, async () => {
    await transport.seed(0);
    const bump = await transport.bump();
    const after = await transport.read();
    const ok = after === 1 && bump.read === 0;
    return [
      ok ? 'PASS' : 'FAIL',
      `mode=${bump.native}; readInside=${bump.read}; after=${after}; ${transport.note}`,
    ];
  });

  // The money-path test. ROUNDS concurrent increments must land as ROUNDS, never fewer. A transport
  // whose "transaction" does not re-read fails here even though the tx probe above passed.
  // Three outcomes are distinguished on purpose, because they demand different designs:
  //   final == ROUNDS        -> serialises, safe to port the 9 tx sites as-is
  //   final == committed < R -> serialises but aborts under contention -> needs an outer retry loop
  //   final < committed      -> LOST UPDATE, never safe for stock or money
  await attempt(`${transport.name} :: lost-update-guard`, async () => {
    await transport.seed(0);
    const outcomes = await Promise.all(
      Array.from({ length: ROUNDS }, () => transport.bump().then(() => 'ok').catch((e: Error) => e.name)),
    );
    const final = await transport.read();
    const committed = outcomes.filter((o) => o === 'ok').length;
    const aborts = outcomes.filter((o) => /abort|conflict|unavailable/i.test(o)).length;
    const detail = `rounds=${ROUNDS}; committed=${committed}; final=${final}; aborts=${aborts}; outcomes=${outcomes.slice(0, 8).join(',')}`;
    if (final === ROUNDS && committed === ROUNDS) return ['PASS', `serialised cleanly — ${detail}`];
    if (final === committed && committed < ROUNDS) return ['FAIL', `SERIALISED BUT ABORTED (needs retry/backoff, not a redesign) — ${detail}`];
    if (final !== null && final < committed) return ['FAIL', `LOST UPDATE (final < committed) — ${detail}`];
    return ['FAIL', `UNEXPLAINED — ${detail}`];
  });
}

// --------------------------------------------------------------------------------------------
// Main
// --------------------------------------------------------------------------------------------
console.log(`target=${TARGET} project=${PROJECT_ID || '(unset)'} db=${DATABASE} host=${TARGET === 'emulator' ? emulatorHost : 'googleapis'} rounds=${ROUNDS}`);
console.log(TARGET === 'live' && !ALLOW_LIVE_WRITE ? 'live target: WRITE probes blocked (read-only run)' : '');
console.log('');

await probeToken();
await probeRestSurface();

const transports: Array<{ label: string; build: () => Promise<Transport> }> = [
  { label: 'T1 firebase-admin (gRPC)', build: () => transportFirebaseAdmin() },
  { label: 'T2 @google-cloud/firestore (gRPC)', build: () => transportGcpClient(false) },
  { label: 'T2 @google-cloud/firestore (REST)', build: () => transportGcpClient(true) },
  { label: 'T3 raw Firestore REST', build: () => transportRawRest() },
];

for (const { label, build } of transports) {
  const started = performance.now();
  let transport: Transport | undefined;
  try {
    transport = await build();
  } catch (error) {
    // Failing to even construct the client is the finding — reported, never swallowed.
    record(`${label} :: load`, 'FAIL', started, `${(error as Error).name}: ${(error as Error).message}`);
    continue;
  }
  if (!transport) continue;
  await harness(transport);
}

const tally = verdicts.reduce((acc, v) => {
  acc[v.result] = (acc[v.result] ?? 0) + 1;
  return acc;
}, {} as Record<string, number>);
console.log(`\n=== ${tally.PASS ?? 0} PASS, ${tally.FAIL ?? 0} FAIL, ${tally.BLOCKED ?? 0} BLOCKED, ${tally.SKIP ?? 0} SKIP ===`);
const safe = verdicts.filter((v) => v.result === 'PASS' && v.id.endsWith(':: lost-update-guard')).map((v) => v.id.split(' :: ')[0]);
if (safe.length) {
  console.log(`LOST-UPDATE-SAFE TRANSPORTS: ${safe.join('  |  ')}`);
} else {
  console.log('NO TRANSPORT PASSED THE LOST-UPDATE GUARD. Do not choose one from this list — read every FAIL detail first.');
}
console.log('This spike writes only the `spike_tx/probe` document; on an emulator you can ignore or delete it.');

Deno.exit(0);
