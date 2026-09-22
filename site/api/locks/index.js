import { saveLock, randomId, randomToken, randomPassword } from '../_lib/store.js';
import { readJSON, only, publicView } from '../_lib/http.js';

// Create a lock. Returns the removal password exactly once — the Mac app bakes
// it into the profile and forgets it.
export default async function handler(req, res) {
  if (!only('POST', req, res)) return;
  let body;
  try { body = await readJSON(req); } catch { return res.status(400).json({ error: 'Bad JSON' }); }

  const delayHours = Number(body.delayHours);
  if (!Number.isFinite(delayHours) || delayHours < 5 / 60 || delayHours > 24 * 365) {
    return res.status(400).json({ error: 'delayHours must be between 0.0833 (5 minutes) and 8760' });
  }
  const apps = Array.isArray(body.apps) ? body.apps.filter((s) => typeof s === 'string').slice(0, 500) : [];
  const sites = Array.isArray(body.sites) ? body.sites.filter((s) => typeof s === 'string').slice(0, 500) : [];
  const mode = body.mode === 'allow' ? 'allow' : 'block';

  const lock = {
    id: randomId(),
    token: randomToken(),
    approverToken: body.partner ? randomToken() : null,
    password: randomPassword(),
    delayHours,
    state: 'locked',
    createdAt: Date.now(),
    mode,
    apps,
    sites,
    organizationName: typeof body.organizationName === 'string' ? body.organizationName.slice(0, 100) : null,
    identity: null,
  };
  await saveLock(lock);

  const origin = `https://${req.headers.host}`;
  res.status(201).json({
    ...publicView(lock),
    token: lock.token,
    password: lock.password,
    statusUrl: `${origin}/l/${lock.id}#${lock.token}`,
    approverUrl: lock.approverToken ? `${origin}/a/${lock.id}#${lock.approverToken}` : null,
  });
}
