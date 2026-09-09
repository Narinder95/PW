import { ApiError, sendJson, newId, nowISO, requireString, optionalString, normalizeColor } from '../http.js';
import { getUser, areFriends, nudgeToJson } from '../domain.js';
import { createNotification } from '../notifications.js';

const COOLDOWN_MS = 60 * 60 * 1000; // 60 minutes, same sender+recipient+habitName
const SENT_LIMIT = 30;

async function withSenderName(db, row) {
  const from = await getUser(db, row.from_user_id);
  return nudgeToJson({ ...row, from_user_name: from ? from.name : null });
}

export function registerNudgeRoutes(router, ctx) {
  const { db } = ctx;

  router.get('/api/nudges', async ({ res, me }) => {
    const receivedRows = await db
      .prepare("SELECT * FROM nudges WHERE to_user_id = ? AND status = 'pending' ORDER BY created_at DESC")
      .all(me.id);
    const sentRows = await db
      .prepare('SELECT * FROM nudges WHERE from_user_id = ? ORDER BY created_at DESC LIMIT ?')
      .all(me.id, SENT_LIMIT);
    const received = await Promise.all(receivedRows.map((r) => withSenderName(db, r)));
    const sent = await Promise.all(sentRows.map((r) => withSenderName(db, r)));
    sendJson(res, 200, { received, sent });
  }, { auth: true });

  router.post('/api/nudges', async ({ res, body, me }) => {
    const toUserId = body.toUserId;
    if (typeof toUserId !== 'string' || toUserId.trim() === '') {
      throw ApiError.validation('toUserId is required', 'toUserId');
    }
    if (toUserId === me.id) throw ApiError.validation('You cannot nudge yourself', 'toUserId');

    const habitName = requireString(body, 'habitName', { min: 1, max: 60 });
    const type = body.type === undefined || body.type === null ? 'nudge' : body.type;
    if (type !== 'nudge' && type !== 'cheer') {
      throw ApiError.validation("type must be 'nudge' or 'cheer'", 'type');
    }
    const message = optionalString(body, 'message', { max: 140 });
    const habitId = optionalString(body, 'habitId', { max: 64 });
    const habitIcon = optionalString(body, 'habitIcon', { max: 16 });
    const habitColor = normalizeColor(body.habitColor, 'habitColor');

    const target = await getUser(db, toUserId);
    if (!target) throw ApiError.notFound('User not found');
    if (!(await areFriends(db, me.id, target.id))) throw ApiError.forbidden('You can only nudge your friends');

    const recent = await db
      .prepare(
        'SELECT created_at FROM nudges WHERE from_user_id = ? AND to_user_id = ? AND habit_name = ? ORDER BY created_at DESC LIMIT 1'
      )
      .get(me.id, target.id, habitName);
    if (recent) {
      const elapsed = Date.now() - new Date(recent.created_at).getTime();
      if (elapsed < COOLDOWN_MS) {
        const retryAfterSeconds = Math.max(1, Math.ceil((COOLDOWN_MS - elapsed) / 1000));
        throw ApiError.rateLimited(
          `You already nudged ${target.name} about ${habitName}. Try again later.`,
          retryAfterSeconds
        );
      }
    }

    const row = {
      id: newId('n'),
      type,
      from_user_id: me.id,
      to_user_id: target.id,
      habit_id: habitId,
      habit_name: habitName,
      habit_icon: habitIcon,
      habit_color: habitColor,
      message,
      status: 'pending',
      created_at: nowISO(),
      accepted_at: null,
    };
    await db.prepare(
      `INSERT INTO nudges
         (id, type, from_user_id, to_user_id, habit_id, habit_name, habit_icon, habit_color,
          message, status, created_at, accepted_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, NULL)`
    ).run(
      row.id, row.type, row.from_user_id, row.to_user_id, row.habit_id, row.habit_name,
      row.habit_icon, row.habit_color, row.message, row.created_at
    );

    const isCheer = type === 'cheer';
    await createNotification(ctx, {
      userId: target.id,
      type,
      title: isCheer ? `${me.name} cheered you on` : `${me.name} nudged you`,
      body: message || (isCheer ? `${me.name} cheered your ${habitName}` : `${me.name} nudged you to ${habitName}`),
      actorId: me.id,
      actorName: me.name,
      avatarColor: me.avatar_color,
      icon: habitIcon,
      color: habitColor,
      refType: 'nudge',
      refId: row.id,
    });

    sendJson(res, 201, { nudge: await withSenderName(db, row) });
  }, { auth: true });

  router.post('/api/nudges/:id/accept', async ({ res, params, me }) => {
    const nudge = await db.prepare('SELECT * FROM nudges WHERE id = ?').get(params.id);
    if (!nudge) throw ApiError.notFound('Nudge not found');
    if (nudge.to_user_id !== me.id) throw ApiError.forbidden('Only the recipient can accept this nudge');
    if (nudge.status !== 'pending') throw ApiError.conflict('That nudge has already been accepted');
    // A nudge can only be sent between friends (above), but the two may have
    // unfriended each other since — accepting it now would still notify
    // someone who is no longer your friend.
    if (!(await areFriends(db, nudge.from_user_id, nudge.to_user_id))) {
      throw ApiError.forbidden('You are no longer friends, so this nudge cannot be accepted');
    }

    const at = nowISO();
    await db.prepare("UPDATE nudges SET status = 'accepted', accepted_at = ? WHERE id = ?").run(at, nudge.id);

    await createNotification(ctx, {
      userId: nudge.from_user_id,
      type: 'nudge_accepted',
      title: `${me.name} accepted your nudge`,
      body: `${me.name} is on it: ${nudge.habit_name}`,
      actorId: me.id,
      actorName: me.name,
      avatarColor: me.avatar_color,
      icon: nudge.habit_icon,
      color: nudge.habit_color,
      refType: 'nudge',
      refId: nudge.id,
    });

    const fresh = await db.prepare('SELECT * FROM nudges WHERE id = ?').get(nudge.id);
    sendJson(res, 200, { nudge: await withSenderName(db, fresh) });
  }, { auth: true });
}
