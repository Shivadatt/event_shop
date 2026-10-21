'use strict';

// A deliberately small in-memory Firestore, used ONLY by `functions/test/**`.
//
// What it is for: letting the REAL handlers in `functions/index.js` run in plain Node, so a regression
// can assert what a callable actually returns (F1 replay ownership, F2 coupon windows, F3 serviceability,
// F4 the price epsilon) instead of only the pure helpers those rules were extracted into.
//
// What it does NOT emulate — do not let a green test suite imply otherwise:
//   * security rules. None. Rules are a Firestore-server feature and are tested separately, against the
//     strict `firebase.json` config, never against `firebase.local.json` (which intentionally has no
//     `rules` key) and never against this object.
//   * real transaction semantics. Transactions here are write-queues that apply on success and are
//     discarded on throw. There is no snapshot version, no conflict detection and no retry, so this CANNOT
//     prove the concurrency claim in ordersCreate's stock reservation ("two buyers on the last unit
//     serialize"). Only the emulator or a deploy can.
//   * query correctness: `where` filters in JS over the whole collection; `orderBy`, `limit`, `startAfter`
//     and `select` are accepted but do nothing, so a paging bug would not be caught here.
//   * FieldValue.serverTimestamp() wall-clock truth, `.set` deep-merge edge cases, batched writes,
//     listeners, persistence, or any network.

// A per-call discriminator mixed into `nanoseconds`. `server.js#newId()` seeds its 21 characters from
// `Date.now() ^ Timestamp.now().nanoseconds`, so two ids minted inside the same millisecond would come
// out IDENTICAL and the second document would overwrite the first — which in a test means a phantom
// "only one order exists" or a flaky stock assertion. Real Firestore has nanosecond resolution; the
// process clock here does not, so the counter supplies the missing entropy. Kept under 1e9 so the
// value stays a legal nanosecond field, and under 1e6 of drift per call so `toMillis()` is unaffected.
let timestampTick = 0;

class Timestamp {
  constructor(seconds, nanoseconds = 0) {
    this._seconds = seconds;
    this._nanoseconds = nanoseconds;
  }
  static now() {
    const ms = Date.now();
    return new Timestamp(Math.floor(ms / 1000), (ms % 1000) * 1e6 + (timestampTick++ % 1000) * 999);
  }
  static fromDate(date) {
    const ms = date.getTime();
    return new Timestamp(Math.floor(ms / 1000), (ms % 1000) * 1e6);
  }
  // The real Timestamp exposes `seconds`/`nanoseconds` getters. `server.js#newId()` reads
  // `Timestamp.now().nanoseconds` as its seed, so without them every generated id in a test run would
  // be identical and documents would overwrite each other.
  get seconds() {
    return this._seconds;
  }
  get nanoseconds() {
    return this._nanoseconds;
  }
  toMillis() {
    return this._seconds * 1000 + Math.floor(this._nanoseconds / 1e6);
  }
  toDate() {
    return new Date(this.toMillis());
  }
}

// Write sentinels. `applyWrite` resolves these against the current document, exactly as the server would.
const FieldValue = {
  increment: (n) => ({ __op: 'increment', n }),
  arrayUnion: (...items) => ({ __op: 'arrayUnion', items }),
  arrayRemove: (...items) => ({ __op: 'arrayRemove', items }),
  delete: () => ({ __op: 'delete' }),
  serverTimestamp: () => ({ __op: 'serverTimestamp' }),
};

class NotFoundError extends Error {
  constructor(path) {
    super(`No document to update: ${path}`);
    this.code = 'not-found';
  }
}

let autoIdCounter = 0;
function nextId() {
  autoIdCounter += 1;
  return `gen${autoIdCounter.toString(36).padStart(6, '0')}`;
}

function deepGet(data, fieldPath) {
  return fieldPath.split('.').reduce((acc, key) => (acc == null ? undefined : acc[key]), data);
}

// Firestore accepts dotted field paths in `set`/`update`. `ordersCreate` writes flat keys, but
// `admin*` handlers use dotted paths, so the fake supports them rather than throwing later.
function setField(target, fieldPath, value) {
  const keys = fieldPath.split('.');
  let node = target;
  for (let i = 0; i < keys.length - 1; i += 1) {
    if (node[keys[i]] == null || typeof node[keys[i]] !== 'object') node[keys[i]] = {};
    node = node[keys[i]];
  }
  node[keys[keys.length - 1]] = value;
}

const OPS = {
  '==': (a, b) => a === b,
  '!=': (a, b) => a !== b,
  '>': (a, b) => a > b,
  '>=': (a, b) => a >= b,
  '<': (a, b) => a < b,
  '<=': (a, b) => a <= b,
  in: (a, b) => Array.isArray(b) && b.includes(a),
  'not-in': (a, b) => Array.isArray(b) && !b.includes(a),
  'array-contains': (a, b) => Array.isArray(a) && a.includes(b),
};

class Store {
  constructor() {
    this.docs = new Map();
  }

  clear() {
    this.docs.clear();
    autoIdCounter = 0;
    timestampTick = 0;
  }

  // `path` is slash-free: 'orders' + 'abc', or 'orders' + 'abc/history' + 'xyz'.
  collection(name) {
    return new Collection(this, name);
  }

  doc(path) {
    return new DocRef(this, path);
  }

  seed(path, data) {
    this.docs.set(path, structuredClone(data));
    return this.doc(path);
  }

  snapshot(path) {
    const data = this.docs.get(path);
    return data === undefined ? null : structuredClone(data);
  }

  write(path, data, options = {}) {
    const base = options.merge && this.docs.has(path) ? structuredClone(this.docs.get(path)) : {};
    for (const [key, value] of Object.entries(data || {})) {
      setField(base, key, resolveValue(value));
    }
    this.docs.set(path, base);
  }

  update(path, data) {
    const existing = this.docs.get(path);
    if (!existing) throw new NotFoundError(path);
    const next = structuredClone(existing);
    for (const [key, value] of Object.entries(data || {})) {
      setField(next, key, applyField(deepGet(next, key), value));
    }
    this.docs.set(path, next);
  }

  remove(path) {
    this.docs.delete(path);
  }

  // Direct reads and transactional reads are the same thing here: no isolation, no versions.
  async get(ref) {
    return new DocSnapshot(ref, this.snapshot(ref.path));
  }
}

function resolveValue(value) {
  if (value && typeof value === 'object' && value.__op) {
    if (value.__op === 'serverTimestamp') return Timestamp.now();
    if (value.__op === 'delete') return undefined;
    return value;
  }
  return structuredClone(value);
}

function applyField(current, value) {
  if (value && typeof value === 'object' && value.__op) {
    if (value.__op === 'increment') return (typeof current === 'number' ? current : 0) + value.n;
    if (value.__op === 'arrayUnion') return [...new Set([...(Array.isArray(current) ? current : []), ...value.items])];
    if (value.__op === 'arrayRemove') return (Array.isArray(current) ? current : []).filter((x) => !value.items.includes(x));
    if (value.__op === 'serverTimestamp') return Timestamp.now();
    if (value.__op === 'delete') return undefined;
  }
  return structuredClone(value);
}

class Collection {
  constructor(store, name) {
    this.store = store;
    this.name = name;
    this.filters = [];
  }

  get path() {
    return this.name;
  }

  doc(id) {
    const key = id || nextId();
    return new DocRef(this.store, `${this.name}/${key}`);
  }

  where(field, op, value) {
    if (!OPS[op]) throw new Error(`fake-firestore: unsupported query operator ${op}`);
    return new Collection(this.store, this.name, [...this.filters, { field, op, value }]);
  }

  orderBy() {
    return this;
  }
  limit() {
    return this;
  }
  startAfter() {
    return this;
  }
  select() {
    return this;
  }

  async get() {
    const prefix = `${this.name}/`;
    const docs = [];
    for (const [path, data] of this.store.docs.entries()) {
      if (!path.startsWith(prefix)) continue;
      const id = path.slice(prefix.length);
      if (id.includes('/')) continue; // a subcollection document, not one of ours
      const snapshot = { id, ref: this.doc(id), data: () => structuredClone(data), exists: true };
      if (this.filters.every((f) => OPS[f.op](deepGet(data, f.field), f.value))) docs.push(snapshot);
    }
    return new QuerySnapshot(docs);
  }
}

class QuerySnapshot {
  constructor(docs) {
    this.docs = docs;
    this.size = docs.length;
    this.empty = docs.length === 0;
  }
  forEach(fn) {
    this.docs.forEach(fn);
  }
}

class DocRef {
  constructor(store, path) {
    this.store = store;
    this.path = path;
    this.id = path.split('/').pop();
  }

  collection(name) {
    return new Collection(this.store, `${this.path}/${name}`);
  }

  async get() {
    return this.store.get(this);
  }

  async set(data, options = {}) {
    this.store.write(this.path, data, options);
    return { writeTime: Timestamp.now() };
  }

  async update(data) {
    this.store.update(this.path, data);
    return { writeTime: Timestamp.now() };
  }

  async delete() {
    this.store.remove(this.path);
  }
}

class DocSnapshot {
  constructor(ref, data) {
    this.ref = ref;
    this.id = ref.id;
    this.exists = data !== null;
    this._data = data;
  }
  data() {
    return this._data === null ? undefined : structuredClone(this._data);
  }
  get(field) {
    return this._data === null ? undefined : deepGet(this._data, field);
  }
}

// Transaction: queue writes, apply on success, discard on throw. `tx.get` sees queued writes so
// read-modify-write inside one transaction behaves, which is what ordersCreate's stock and counter
// updates rely on.
class Transaction {
  constructor(store) {
    this.store = store;
    this.queue = [];
  }

  async get(refOrRefs, ...rest) {
    const refs = Array.isArray(refOrRefs) ? refOrRefs : [refOrRefs, ...rest];
    const results = refs.map((ref) => this._snapshotFor(ref));
    return Array.isArray(refOrRefs) || rest.length > 0 ? results : results[0];
  }

  _snapshotFor(ref) {
    for (let i = this.queue.length - 1; i >= 0; i -= 1) {
      const write = this.queue[i];
      if (write.path !== ref.path) continue;
      if (write.kind === 'delete') return new DocSnapshot(ref, null);
      if (write.kind === 'set' && !write.merge) return new DocSnapshot(ref, structuredClone(write.data));
      const base = this.store.snapshot(write.path) || {};
      return new DocSnapshot(ref, mergeFields(base, write.data, write.kind === 'set'));
    }
    return new DocSnapshot(ref, this.store.snapshot(ref.path));
  }

  set(ref, data, options = {}) {
    this.queue.push({ kind: 'set', path: ref.path, data: structuredClone(data), merge: options.merge === true });
  }

  update(ref, data) {
    this.queue.push({ kind: 'update', path: ref.path, data: structuredClone(data) });
  }

  delete(ref) {
    this.queue.push({ kind: 'delete', path: ref.path });
  }

  commit() {
    for (const write of this.queue) {
      if (write.kind === 'delete') this.store.remove(write.path);
      else if (write.kind === 'set') this.store.write(write.path, write.data, { merge: write.merge });
      else this.store.update(write.path, write.data);
    }
  }
}

function mergeFields(base, patch, isSet) {
  const next = structuredClone(base);
  for (const [key, value] of Object.entries(patch || {})) {
    if (!isSet && (value && typeof value === 'object' && value.__op === 'increment')) {
      next[key] = (typeof next[key] === 'number' ? next[key] : 0) + value.n;
    } else {
      next[key] = value;
    }
  }
  return next;
}

function createFirestore() {
  const store = new Store();
  const db = Object.assign(
    (settings) => db,
    {
      store,
      collection: (name) => store.collection(name),
      doc: (path) => store.doc(path),
      runTransaction: async (fn) => {
        const tx = new Transaction(store);
        const result = await fn(tx);
        tx.commit();
        return result;
      },
      FieldValue,
      Timestamp,
    },
  );
  return db;
}

module.exports = { createFirestore, FieldValue, Timestamp, Store, DocSnapshot, deepGet };
