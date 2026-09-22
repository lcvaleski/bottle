import { saveLock } from '../../_lib/store.js';
import { authorize, only, publicView } from '../../_lib/http.js';

// The person the user chose says yes. Releases immediately, timer or not.
export default async function handler(req, res) {
  if (!only('POST', req, res)) return;
  const lock = await authorize(req, res, 'approverToken');
  if (!lock) return;
  if (lock.state !== 'released') {
    lock.state = 'released';
    lock.releasedAt = Date.now();
    lock.approvedAt = lock.releasedAt;
    await saveLock(lock);
  }
  res.status(200).json(publicView(lock));
}
