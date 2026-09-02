import { ApiError, sendJson, sendNoContent, newId, nowISO } from '../http.js';
import {
  todayISO, getUser, areFriends, addFriendship, friendRequestToJson, friendSummary,
} from '../domain.js';
import { createNotification } from '../notifications.js';

function pendingBetween(db, fromId, toId) {
  return db
    .prepare("SELECT * FROM friend_requests WHERE from_user_id = ? AND to_user_id = ? AND status = 'pending'")
    .get(fromId, toId) ?? null;
}

function acceptRequest(ctx, request, accepter) {
  const { db } = ctx;
  const at = nowISO();
  db.prepare("UPDATE friend_requests SET status = 'accepted', responded_at = ? WHERE id = ?").run(at, request.id);
  addFriendship(db, request.from_user_id, request.to_user_id, at);

  // Any mirror request in the other direction is now moot.
  db.prepare(
    "UPDATE friend_requests SET status = 'accepted', responded_at = ? WHERE from_user_id = ? AND to_user_id = ? AND status = 'pending'"
  ).run(at, request.to_user_id, request.from_user_id);

  const sender = getUser(db, request.from_user_id);
  createNotification(ctx, {
    userId: request.from_user_id,
    type: 'friend_request_accepted',
    title: `${accepter.name} accepted your friend request`,
    body: `You and ${accepter.name} are now friends`,
    actorId: accepter.id,
    actorName: accepter.name,
    avatarColor: accepter.avatar_color,
    refType: 'user',
    refId: accepter.id,
  });
  return sender;
}

export function registerRequestRoutes(router, ctx) {
  const { db } = ctx;

  router.get('/api/friend-requests', async ({ res, me }) => {
    const incoming = db
      .prepare("SELECT * FROM friend_requests WHERE to_user_id = ? AND status = 'pending' ORDER BY created_at DESC")
      .all(me.id)
      .map((r) => friendRequestToJson(db, r));
    const outgoing = db
      .prepare("SELECT * FROM friend_requests WHERE from_user_id = ? AND status = 'pending' ORDER BY created_at DESC")
      .all(me.id)
      .map((r) => friendRequestToJson(db, r));
    sendJson(res, 200, { incoming, outgoing });
  }, { auth: true });

  router.post('/api/friend-requests', async ({ res, body, me }) => {
    const toUserId = body.toUserId;
    if (typeof toUserId !== 'string' || toUserId.trim() === '') {
      throw ApiError.validation('toUserId is required', 'toUserId');
    }
    if (toUserId === me.id) throw ApiError.validation('You cannot send yourself a friend request', 'toUserId');

    const target = getUser(db, toUserId);
    if (!target) throw ApiError.notFound('User not found');
    if (areFriends(db, me.id, target.id)) throw ApiError.conflict('You are already friends');

    // They already asked you -> auto-accept instead of creating a mirror request.
    const reciprocal = pendingBetween(db, target.id, me.id);
    if (reciprocal) {
      acceptRequest(ctx, reciprocal, me);
      const fresh = db.prepare('SELECT * FROM friend_requests WHERE id = ?').get(reciprocal.id);
      sendJson(res, 200, {
        request: friendRequestToJson(db, fresh),
        friend: friendSummary(db, getUser(db, target.id), todayISO()),
        autoAccepted: true,
      });
      return;
    }

    if (pendingBetween(db, me.id, target.id)) {
      throw ApiError.conflict('You already have a pending request to that user');
    }

    const row = {
      id: newId('fr'),
      from_user_id: me.id,
      to_user_id: target.id,
      status: 'pending',
      created_at: nowISO(),
      responded_at: null,
    };
    db.prepare(
      'INSERT INTO friend_requests (id, from_user_id, to_user_id, status, created_at, responded_at) VALUES (?, ?, ?, ?, ?, NULL)'
    ).run(row.id, row.from_user_id, row.to_user_id, row.status, row.created_at);

    createNotification(ctx, {
      userId: target.id,
      type: 'friend_request',
      title: `${me.name} sent you a friend request`,
      body: `${me.name} (@${me.username}) wants to be friends`,
      actorId: me.id,
      actorName: me.name,
      avatarColor: me.avatar_color,
      refType: 'friend_request',
      refId: row.id,
    });

    sendJson(res, 201, { request: friendRequestToJson(db, row) });
  }, { auth: true });

  router.post('/api/friend-requests/:id/accept', async ({ res, params, me }) => {
    const request = db.prepare('SELECT * FROM friend_requests WHERE id = ?').get(params.id);
    if (!request) throw ApiError.notFound('Friend request not found');
    if (request.to_user_id !== me.id) throw ApiError.forbidden('Only the recipient can accept this request');
    if (request.status !== 'pending') throw ApiError.conflict(`Request is already ${request.status}`);

    acceptRequest(ctx, request, me);
    const other = getUser(db, request.from_user_id);
    sendJson(res, 200, { friend: friendSummary(db, other, todayISO()) });
  }, { auth: true });

  router.post('/api/friend-requests/:id/decline', async ({ res, params, me }) => {
    const request = db.prepare('SELECT * FROM friend_requests WHERE id = ?').get(params.id);
    if (!request) throw ApiError.notFound('Friend request not found');
    if (request.to_user_id !== me.id) throw ApiError.forbidden('Only the recipient can decline this request');
    if (request.status !== 'pending') throw ApiError.conflict(`Request is already ${request.status}`);

    db.prepare("UPDATE friend_requests SET status = 'declined', responded_at = ? WHERE id = ?")
      .run(nowISO(), request.id);
    // Declining notifies nobody, by design.
    sendNoContent(res);
  }, { auth: true });

  router.delete('/api/friend-requests/:id', async ({ res, params, me }) => {
    const request = db.prepare('SELECT * FROM friend_requests WHERE id = ?').get(params.id);
    if (!request) throw ApiError.notFound('Friend request not found');
    if (request.from_user_id !== me.id) throw ApiError.forbidden('Only the sender can cancel this request');
    if (request.status !== 'pending') throw ApiError.conflict(`Request is already ${request.status}`);

    db.prepare("UPDATE friend_requests SET status = 'cancelled', responded_at = ? WHERE id = ?")
      .run(nowISO(), request.id);
    sendNoContent(res);
  }, { auth: true });
}
