// Provider selection, mirroring push/index.js's createPushProvider.
import { NoneProvider, LogProvider, MemoryProvider } from './providers.js';
import { ResendProvider } from './resend.js';

export { NoneProvider, LogProvider, MemoryProvider, ResendProvider };

/**
 * Build the provider named by MAIL_PROVIDER. Never throws: a misconfigured
 * `resend` provider logs a warning and degrades to `none` so the server
 * still boots.
 */
export function createMailProvider(env = process.env, logger = console) {
  const name = String(env.MAIL_PROVIDER ?? 'none').trim().toLowerCase();
  switch (name) {
    case 'log':
      return new LogProvider(logger);
    case 'memory':
      return new MemoryProvider();
    case 'resend': {
      const apiKey = env.RESEND_API_KEY;
      const from = env.MAIL_FROM;
      if (!apiKey || !from) {
        logger.warn(
          '[mail] MAIL_PROVIDER=resend but RESEND_API_KEY/MAIL_FROM are not set. ' +
            'Falling back to MAIL_PROVIDER=none.'
        );
        return new NoneProvider();
      }
      return new ResendProvider({ apiKey, from, logger });
    }
    case 'none':
      return new NoneProvider();
    default:
      logger.warn(`[mail] unknown MAIL_PROVIDER "${name}", using "none".`);
      return new NoneProvider();
  }
}
