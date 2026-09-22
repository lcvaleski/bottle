import { saveLock } from '../../_lib/store.js';
import { authorize, only, publicView, settle } from '../../_lib/http.js';

// Start the clock. Idempotent: asking again doesn't reset it.
export default async function handler(req, res) {
  if (!only('POST', req, res)) return;
  const lock = await authorize(req, res);
  if (!lock) return;
  if (lock.state === 'locked') {
    lock.state = 'unlocking';
    lock.unlockRequestedAt = Date.now();
    lock.unlockAt = lock.unlockRequestedAt + lock.delayHours * 3600 * 1000;
  }
  settle(lock);
  await saveLock(lock);
  res.status(200).json(publicView(lock));
}
