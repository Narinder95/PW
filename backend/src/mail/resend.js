// Resend (resend.com) transactional email over its plain HTTP API - one
// `fetch` call, an API key, nothing to `npm install`. Same shape as
// push/fcm.js: a thin HTTP client, no SDK.
export class ResendProvider {
  constructor({ apiKey, from, logger = console }) {
    this.name = 'resend';
    this.apiKey = apiKey;
    this.from = from;
    this.logger = logger;
  }

  async send({ to, subject, text }) {
    let res;
    try {
      res = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${this.apiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ from: this.from, to, subject, text }),
      });
    } catch (err) {
      return { status: 'failed', error: `network error: ${err.message}` };
    }
    if (res.ok) return { status: 'sent' };
    const body = await res.text().catch(() => '');
    return { status: 'failed', error: `resend ${res.status}: ${body.slice(0, 200)}` };
  }
}
