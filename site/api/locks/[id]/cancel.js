import { saveLock } from '../../_lib/store.js';
import { authorize, only, publicView } from '../../_lib/http.js';

// Changed your mind while the clock is running. Not allowed once released.
export default async function handler(req, res) {
  if (!only('POST', req, res)) return;
  const lock = await authorize(req, res);
  if (!lock) return;
  if (lock.state === 'unlocking' && Date.now() < lock.unlockAt) {
    lock.state = 'locked';
    lock.unlockRequestedAt = null;
    lock.unlockAt = null;
    await saveLock(lock);
  }
  res.status(200).json(publicView(lock));
}
