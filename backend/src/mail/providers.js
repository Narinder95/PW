// Mail providers. Every provider implements the same interface:
//
//   name: string
//   async send({ to, subject, text }) -> { status, error? }
//     status: 'sent' | 'skipped' | 'failed'
//
// A provider never throws for an expected delivery failure - it returns a
// status. Mirrors push/providers.js.

/** Default. Records the attempt without sending, so the whole path stays testable. */
export class NoneProvider {
  constructor() {
    this.name = 'none';
  }
  async send() {
    return { status: 'skipped' };
  }
}

/** Prints the fully rendered message. Used by local dev + `MAIL_PROVIDER=log`. */
export class LogProvider {
  constructor(logger = console) {
    this.name = 'log';
    this.logger = logger;
  }
  async send(message) {
    this.logger.log(`[mail:log] ${JSON.stringify(message)}`);
    return { status: 'sent' };
  }
}

/**
 * In-process capture for node:test.
 *   provider.sent       - every message handed to send()
 *   provider.nextStatus - force one specific result
 *   provider.throwTimes  - throw (not return) on the next call
 */
export class MemoryProvider {
  constructor() {
    this.name = 'memory';
    this.sent = [];
    this.nextStatus = null;
    this.throwTimes = 0;
  }

  reset() {
    this.sent = [];
    this.nextStatus = null;
    this.throwTimes = 0;
  }

  async send(message) {
    this.sent.push(message);
    if (this.throwTimes > 0) {
      this.throwTimes -= 1;
      throw new Error('memory mail provider: simulated crash');
    }
    if (this.nextStatus) {
      const s = this.nextStatus;
      this.nextStatus = null;
      return { status: s, error: s === 'sent' ? undefined : s };
    }
    return { status: 'sent' };
  }
}
