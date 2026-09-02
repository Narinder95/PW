// Firebase Cloud Messaging HTTP v1 - zero npm dependencies.
//
// Auth flow (what firebase-admin does under the hood):
//   1. build a self-signed RS256 JWT from the service-account private key
//   2. exchange it at https://oauth2.googleapis.com/token for an access token
//   3. POST the message to
//      https://fcm.googleapis.com/v1/projects/{PROJECT_ID}/messages:send
//
// The access token is cached until ~5 minutes before it expires.
//
// NOTE: credential contents are never logged. Only the file path and generic
// failure reasons ever reach the log.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const TOKEN_URL = 'https://oauth2.googleapis.com/token';
const SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';
const JWT_GRANT = 'urn:ietf:params:oauth:grant-type:jwt-bearer';
const EXPIRY_SKEW_MS = 5 * 60 * 1000; // refresh 5 min early

function b64url(input) {
  return Buffer.from(input).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/**
 * Load + validate a service-account JSON file.
 * @throws {Error} with a message that never contains key material.
 */
export function loadServiceAccount(filePath, cwd = process.cwd()) {
  const resolved = path.isAbsolute(filePath) ? filePath : path.resolve(cwd, filePath);
  let raw;
  try {
    raw = fs.readFileSync(resolved, 'utf8');
  } catch {
    throw new Error(`service account file not readable at ${resolved}`);
  }
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new Error(`service account file at ${resolved} is not valid JSON`);
  }
  if (!parsed || typeof parsed.client_email !== 'string' || typeof parsed.private_key !== 'string') {
    throw new Error(`service account file at ${resolved} is missing client_email/private_key`);
  }
  return { client_email: parsed.client_email, private_key: parsed.private_key, project_id: parsed.project_id };
}

export class FcmProvider {
  /**
   * @param {object}   opts
   * @param {string}   opts.projectId
   * @param {object}   opts.serviceAccount  from loadServiceAccount()
   * @param {Function} [opts.fetchImpl]     injectable for tests
   * @param {Function} [opts.now]           injectable clock
   */
  constructor({ projectId, serviceAccount, fetchImpl = globalThis.fetch, logger = console, now = () => Date.now() }) {
    if (!projectId) throw new Error('FCM_PROJECT_ID is required');
    if (!serviceAccount) throw new Error('service account is required');
    this.name = 'fcm';
    this.projectId = projectId;
    this.serviceAccount = serviceAccount;
    this.fetchImpl = fetchImpl;
    this.logger = logger;
    this.now = now;
    this._token = null;      // { accessToken, expiresAtMs }
    this._inFlight = null;   // de-dupe concurrent refreshes
  }

  /** Build (and sign) the assertion JWT. */
  buildAssertion() {
    const iat = Math.floor(this.now() / 1000);
    const header = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
    const claims = b64url(
      JSON.stringify({
        iss: this.serviceAccount.client_email,
        scope: SCOPE,
        aud: TOKEN_URL,
        iat,
        exp: iat + 3600,
      })
    );
    const signingInput = `${header}.${claims}`;
    const signature = crypto
      .createSign('RSA-SHA256')
      .update(signingInput)
      .sign(this.serviceAccount.private_key)
      .toString('base64')
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=+$/, '');
    return `${signingInput}.${signature}`;
  }

  async accessToken() {
    if (this._token && this._token.expiresAtMs - EXPIRY_SKEW_MS > this.now()) {
      return this._token.accessToken;
    }
    if (this._inFlight) return this._inFlight;
    this._inFlight = (async () => {
      const body = new URLSearchParams({ grant_type: JWT_GRANT, assertion: this.buildAssertion() });
      const res = await this.fetchImpl(TOKEN_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: body.toString(),
      });
      if (!res.ok) {
        throw new Error(`oauth token exchange failed with HTTP ${res.status}`);
      }
      const json = await res.json();
      if (!json || typeof json.access_token !== 'string') {
        throw new Error('oauth token exchange returned no access_token');
      }
      const ttlMs = (Number(json.expires_in) || 3600) * 1000;
      this._token = { accessToken: json.access_token, expiresAtMs: this.now() + ttlMs };
      return this._token.accessToken;
    })().finally(() => {
      this._inFlight = null;
    });
    return this._inFlight;
  }

  /** Provider-neutral payload -> FCM HTTP v1 message. */
  buildMessage(payload) {
    const message = {
      token: payload.deviceToken,
      notification: { title: payload.title, body: payload.body },
      data: payload.data ?? {},
    };
    if (payload.collapseKey) {
      message.android = { collapse_key: payload.collapseKey };
      message.apns = { headers: { 'apns-collapse-id': payload.collapseKey } };
    }
    if (typeof payload.badge === 'number') {
      message.apns = message.apns ?? {};
      message.apns.payload = { aps: { badge: payload.badge, sound: 'default' } };
      message.android = message.android ?? {};
      message.android.notification = { notification_count: payload.badge };
    }
    return { message };
  }

  async send(payload) {
    let token;
    try {
      token = await this.accessToken();
    } catch (err) {
      return { status: 'failed', error: `auth: ${err.message}` };
    }

    let res;
    try {
      res = await this.fetchImpl(`https://fcm.googleapis.com/v1/projects/${this.projectId}/messages:send`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify(this.buildMessage(payload)),
      });
    } catch (err) {
      return { status: 'failed', error: `network: ${err.message}` };
    }

    if (res.ok) return { status: 'sent' };

    let detail = '';
    let fcmStatus = '';
    try {
      const json = await res.json();
      fcmStatus = json?.error?.status ?? '';
      detail = json?.error?.message ?? '';
      const reasons = (json?.error?.details ?? [])
        .map((d) => d?.errorCode)
        .filter(Boolean);
      if (reasons.includes('UNREGISTERED')) fcmStatus = 'UNREGISTERED';
    } catch {
      detail = `HTTP ${res.status}`;
    }

    if (fcmStatus === 'UNREGISTERED' || fcmStatus === 'NOT_FOUND' || fcmStatus === 'INVALID_ARGUMENT') {
      return { status: 'invalid_token', error: `${fcmStatus}: ${detail}`.trim() };
    }
    // 401 means our cached token went stale - drop it so the retry re-auths.
    if (res.status === 401) this._token = null;
    return { status: 'failed', error: `HTTP ${res.status} ${fcmStatus} ${detail}`.trim() };
  }
}
