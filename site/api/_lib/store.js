// One encrypted JSON blob per lock in a private Vercel Blob store.
// Everything sensitive (removal password, escrowed supervision identity)
// is AES-256-GCM encrypted with LOCK_SECRET before it touches storage.
import crypto from 'node:crypto';
import { get, put } from '@vercel/blob';

function key() {
  const secret = process.env.LOCK_SECRET;
  if (!secret) throw new Error('LOCK_SECRET is not set');
  return crypto.createHash('sha256').update(secret).digest();
}

function encrypt(obj) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key(), iv);
  const data = Buffer.concat([cipher.update(JSON.stringify(obj), 'utf8'), cipher.final()]);
  return JSON.stringify({ v: 1, iv: iv.toString('base64'), tag: cipher.getAuthTag().toString('base64'), data: data.toString('base64') });
}

function decrypt(text) {
  const { iv, tag, data } = JSON.parse(text);
  const decipher = crypto.createDecipheriv('aes-256-gcm', key(), Buffer.from(iv, 'base64'));
  decipher.setAuthTag(Buffer.from(tag, 'base64'));
  return JSON.parse(Buffer.concat([decipher.update(Buffer.from(data, 'base64')), decipher.final()]).toString('utf8'));
}

const pathFor = (id) => `locks/${id}.json`;

export async function loadLock(id) {
  if (!/^[a-z0-9]{20,}$/.test(id)) return null;
  const result = await get(pathFor(id), { access: 'private', useCache: false });
  if (!result) return null;
  const text = await new Response(result.stream).text();
  return decrypt(text);
}

export async function saveLock(lock) {
  await put(pathFor(lock.id), encrypt(lock), {
    access: 'private',
    addRandomSuffix: false,
    allowOverwrite: true,
    contentType: 'application/json',
  });
  return lock;
}

export const randomId = () => crypto.randomBytes(15).toString('base64url').toLowerCase().replace(/[^a-z0-9]/g, '').slice(0, 20).padEnd(20, '0');
export const randomToken = () => crypto.randomBytes(32).toString('base64url');

// Typed on an iPhone, so: no ambiguous glyphs, all lowercase.
export function randomPassword(length = 10) {
  const alphabet = 'abcdefghjkmnpqrstuvwxyz23456789';
  const bytes = crypto.randomBytes(length);
  return Array.from(bytes, (b) => alphabet[b % alphabet.length]).join('');
}

export function tokenMatches(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;
  return crypto.timingSafeEqual(Buffer.from(a), Buffer.from(b));
}
