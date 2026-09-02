import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../utils/journal_theme.dart';
import 'friends/pw_avatar.dart';

/// The signed-in user's identity, straight from `AuthService.user`.
///
/// Previously this rendered a hard-coded "Alex Johnson",
/// "alex.johnson@email.com", a "Consistent Tracker" badge and
/// "3,847 activities logged" — none of which came from anywhere.
class UserHeader extends StatelessWidget {
  final UserProfile? user;

  const UserHeader({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    final t = JournalTheme.of(context);
    final profile = user;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (profile == null)
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: t.inertCell,
              ),
              child: Icon(
                Icons.person_outline,
                size: 40,
                color: t.textMuted,
              ),
            )
          else
            PwAvatar(
              name: profile.name,
              color: profile.avatarColor,
              size: 88,
            ),
          const SizedBox(height: 16),
          Text(
            profile == null || profile.name.trim().isEmpty
                ? 'Not signed in'
                : profile.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: t.textPrimary,
            ),
          ),
          if (profile != null && profile.handle.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              profile.handle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: t.textSecondary),
            ),
          ],
          if (profile?.email != null && profile!.email!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              profile.email!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: t.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}
