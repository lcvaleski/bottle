import { saveLock } from '../../_lib/store.js';
import { authorize, only, publicView, settle } from '../../_lib/http.js';

// Status. Once the timer has run out this is also where the password (and,
// with ?identity=1, the escrowed supervision identity) comes back.
export default async function handler(req, res) {
  if (!only('GET', req, res)) return;
  const lock = await authorize(req, res);
  if (!lock) return;
  const before = lock.state;
  settle(lock);
  if (lock.state !== before) await saveLock(lock);
  res.setHeader('Cache-Control', 'no-store');
  res.status(200).json(publicView(lock, { includeIdentity: req.query.identity === '1' }));
}
