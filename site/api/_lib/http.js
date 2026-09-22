import { loadLock, tokenMatches } from './store.js';

export function bearer(req) {
  const h = req.headers.authorization || '';
  return h.startsWith('Bearer ') ? h.slice(7) : null;
}

export async function readJSON(req) {
  if (req.body && typeof req.body === 'object') return req.body;
  const chunks = [];
  for await (const c of req) chunks.push(c);
  const text = Buffer.concat(chunks).toString('utf8');
  return text ? JSON.parse(text) : {};
}

/// Loads the lock and checks the caller's token against the given field.
export async function authorize(req, res, field = 'token') {
  const id = req.query.id;
  const lock = await loadLock(id);
  if (!lock) { res.status(404).json({ error: 'No such lock' }); return null; }
  if (!tokenMatches(bearer(req) || req.query.t, lock[field])) { res.status(403).json({ error: 'Bad token' }); return null; }
  return lock;
}

/// Moves a lock whose timer has expired into the released state.
export function settle(lock, now = Date.now()) {
  if (lock.state === 'unlocking' && lock.unlockAt && now >= lock.unlockAt) {
    lock.state = 'released';
    lock.releasedAt = lock.releasedAt || now;
  }
  return lock;
}

/// What the phone/Mac are allowed to see. Password and identity only once released.
export function publicView(lock, { includeIdentity = false } = {}) {
  const view = {
    id: lock.id,
    state: lock.state,
    delayHours: lock.delayHours,
    createdAt: lock.createdAt,
    unlockRequestedAt: lock.unlockRequestedAt || null,
    unlockAt: lock.unlockAt || null,
    releasedAt: lock.releasedAt || null,
    hasIdentity: Boolean(lock.identity),
    hasApprover: Boolean(lock.approverToken),
    mode: lock.mode,
    apps: lock.apps,
    sites: lock.sites,
    organizationName: lock.organizationName,
  };
  if (lock.state === 'released') {
    view.password = lock.password;
    if (includeIdentity && lock.identity) view.identity = lock.identity;
  }
  return view;
}

export function only(method, req, res) {
  if (req.method === method) return true;
  res.setHeader('Allow', method);
  res.status(405).json({ error: `Use ${method}` });
  return false;
}
