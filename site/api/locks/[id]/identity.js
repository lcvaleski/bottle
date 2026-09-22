import { saveLock } from '../../_lib/store.js';
import { authorize, only, readJSON } from '../../_lib/http.js';

// Escrow the Mac's supervision identity. Called once, right before the Mac
// deletes its own copy. Both parts are base64 DER.
export default async function handler(req, res) {
  if (!only('PUT', req, res)) return;
  const lock = await authorize(req, res);
  if (!lock) return;
  let body;
  try { body = await readJSON(req); } catch { return res.status(400).json({ error: 'Bad JSON' }); }
  const { certificate, privateKey, organizationName } = body;
  if (typeof certificate !== 'string' || typeof privateKey !== 'string' || certificate.length > 20000 || privateKey.length > 20000) {
    return res.status(400).json({ error: 'certificate and privateKey (base64) required' });
  }
  if (lock.identity) return res.status(409).json({ error: 'Identity already escrowed' });
  lock.identity = { certificate, privateKey, organizationName: organizationName || lock.organizationName || null, escrowedAt: Date.now() };
  await saveLock(lock);
  res.status(200).json({ ok: true, escrowedAt: lock.identity.escrowedAt });
}
