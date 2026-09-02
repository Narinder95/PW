import 'package:flutter/material.dart';

import '../models/habit.dart';
import '../models/user_profile.dart';
import '../services/api/api_exception.dart';
import '../utils/journal_theme.dart';
import 'link_account_screen.dart';
import '../widgets/app_scope.dart';
import '../widgets/settings_section.dart';
import '../widgets/stats_dashboard.dart';
import '../widgets/user_header.dart';

/// Account and preferences.
///
/// The header and the stats grid are driven by `AuthService.user` and the
/// user's real habits rather than by the invented profile they used to show.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool notificationsEnabled = true;
  bool streakReminderEnabled = true;
  String darkModePreference = 'auto'; // 'light', 'dark', 'auto'
  String notificationTime = '09:00';

  AppServices? _services;
  List<Habit> _habits = const <Habit>[];
  bool _loadingHabits = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.of(context);
    if (identical(_services, services)) return;
    _services = services;
    _loadHabits();
  }

  Future<void> _loadHabits() async {
    final services = _services;
    if (services == null || !services.auth.isSignedIn) {
      if (mounted) setState(() => _loadingHabits = false);
      return;
    }
    setState(() => _loadingHabits = true);
    try {
      final habits = await services.api.getHabits();
      if (!mounted) return;
      setState(() {
        _habits = habits;
        _loadingHabits = false;
      });
    } on ApiException {
      // The stats grid degrades to its "no habits yet" copy; a profile screen
      // is not the place to shout about a failed side-load.
      if (!mounted) return;
      setState(() => _loadingHabits = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = JournalTheme.of(context);
    final services = AppScope.of(context);

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text('Profile'),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: t.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: t.textPrimary,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: t.textPrimary,
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await services.auth.refreshProfile();
          await _loadHabits();
        },
        child: ListView(
          children: [
            ListenableBuilder(
              listenable: services.auth,
              builder: (context, _) => UserHeader(user: services.auth.user),
            ),
            const SizedBox(height: 24),
            StatsDashboard(habits: _habits, loading: _loadingHabits),
            const SizedBox(height: 24),
            SettingsSection(
              notificationsEnabled: notificationsEnabled,
              onNotificationsChanged: (value) =>
                  setState(() => notificationsEnabled = value),
              notificationTime: notificationTime,
              onNotificationTimeChanged: (value) =>
                  setState(() => notificationTime = value),
              darkModePreference: darkModePreference,
              onDarkModeChanged: (value) =>
                  setState(() => darkModePreference = value),
              streakReminderEnabled: streakReminderEnabled,
              onStreakReminderChanged: (value) =>
                  setState(() => streakReminderEnabled = value),
            ),
            const SizedBox(height: 24),
            _buildAccountSection(t),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountSection(JournalTheme t) {
    // Two shapes, because there is no login screen. An account starts
    // anonymous and device-bound; once claimed it can be recovered, and only
    // then does signing out stop being a way to lose everything.
    final profile = _services?.auth.user;
    final isAnonymous = profile?.isAnonymous ?? true;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Account',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          if (isAnonymous)
            _unclaimedCard(t)
          else
            _claimedCard(t, profile),
        ],
      ),
    );
  }

  /// The account exists only on this handset — say so plainly and offer the fix.
  Widget _unclaimedCard(JournalTheme t) {
    return Container(
      decoration: BoxDecoration(
        color: t.surfaceBright,
        borderRadius: BorderRadius.circular(JournalTheme.radiusCard),
        border: Border.all(color: t.action.withValues(alpha: 0.45)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded, color: t.action, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'This account is only on this phone',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: t.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Add an email or phone number so your habits, streaks and friends '
            'survive a reinstall or a new device.',
            style: TextStyle(fontSize: 13, height: 1.5, color: t.textSecondary),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _openLinkAccount,
              icon: const Icon(Icons.shield_outlined, size: 18),
              label: const Text('Save my account'),
              style: FilledButton.styleFrom(
                backgroundColor: t.action,
                foregroundColor: t.onAccent(t.action),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(JournalTheme.radiusTile),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Claimed: show what it is linked to, and allow signing out safely.
  Widget _claimedCard(JournalTheme t, UserProfile? profile) {
    final email = profile?.email;
    final phone = profile?.phone;

    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(JournalTheme.radiusTile),
        border: Border.all(color: t.outline),
      ),
      child: Column(
        children: [
          if (email != null && email.isNotEmpty)
            _accountRow(t, Icons.alternate_email, 'Email', email),
          if (phone != null && phone.isNotEmpty)
            _accountRow(t, Icons.phone_outlined, 'Phone', phone),
          Divider(height: 1, color: t.outline),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _confirmLogout,
              borderRadius: BorderRadius.circular(JournalTheme.radiusTile),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Icon(Icons.logout_rounded, color: t.incomplete, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Sign out',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: t.incomplete,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right, color: t.textMuted, size: 20),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _accountRow(JournalTheme t, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: t.textMuted, size: 20),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: t.textSecondary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: t.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openLinkAccount() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const LinkAccountScreen()),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account saved — you can restore it on another device.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _confirmLogout() async {
    final t = JournalTheme.of(context);
    final services = _services;
    if (services == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: t.background,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Sign out?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: t.textPrimary,
          ),
        ),
        content: Text(
          'You can sign back in with your email or phone number.',
          style: TextStyle(color: t.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            style: TextButton.styleFrom(foregroundColor: t.textSecondary),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: t.incomplete,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    // `AuthService.logout` retires the push device and revokes the token
    // server-side before clearing local state; `main.dart` then swaps in the
    // login screen.
    await services.auth.logout();
  }
}
