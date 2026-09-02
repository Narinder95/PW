import 'dart:async';

import 'package:flutter/material.dart';

import 'screens/friends_screen.dart';
import 'screens/journal_screen.dart';
import 'screens/journey_screen.dart';
import 'screens/profile_screen.dart';
import 'services/api/api_client.dart';
import 'services/api/api_config.dart';
import 'services/api/pw_api.dart';
import 'services/auth_service.dart';
import 'services/friends_repository.dart';
import 'services/notification_service.dart';
import 'services/push_service.dart';
import 'utils/journal_theme.dart';
import 'widgets/app_scope.dart';
import 'widgets/notification_banner.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // TODO(release): Firebase.initializeApp() goes here, before anything touches
  // FirebaseMessaging — see StubPushTokenSource's release note in
  // lib/services/push_service.dart. The client swap is then one line: pass
  // `tokenSource: FirebaseMessagingTokenSource()` to the PushService below.
  //   await Firebase.initializeApp();

  // Pick up a persisted base-URL override before the first request is made,
  // so a QA build pointed at staging never briefly talks to localhost.
  final config = ApiConfig();
  await config.load();

  // With no explicit override, find out which host actually answers. On a
  // physical Android handset the emulator-only `10.0.2.2` default just fails,
  // so we probe `localhost` first (what `adb reverse tcp:8080 tcp:8080`
  // exposes) and fall back to the emulator alias. Bounded to ~2.4s worst case
  // and it never throws, so a totally offline start still reaches the UI and
  // shows the normal retry panel.
  await config.autoDetect();

  runApp(PwApp(config: config));
}

/// Owns every service for the life of the process and hands them down through
/// [AppScope].
///
/// No state-management package: the services are `ChangeNotifier`s, provided by
/// an `InheritedWidget` and consumed with `ListenableBuilder`.
class PwApp extends StatefulWidget {
  final ApiConfig config;

  const PwApp({super.key, required this.config});

  @override
  State<PwApp> createState() => _PwAppState();
}

class _PwAppState extends State<PwApp> {
  late final AppServices _services;
  StreamSubscription<PushOpen>? _pushOpens;

  /// Tracks the previous auth state so the start/stop wiring only fires on a
  /// real transition, not on every profile refresh.
  AuthState _lastAuthState = AuthState.unknown;

  @override
  void initState() {
    super.initState();

    final client = ApiClient(config: widget.config);
    final api = PwApi(client);

    final push = PushService(
      api: api,
      // Explicit, so the release swap is exactly this one argument.
      tokenSource: const StubPushTokenSource(),
    );

    final auth = AuthService(client: client, api: api, pushService: push);

    _services = AppServices(
      client: client,
      api: api,
      auth: auth,
      friends: FriendsRepository(api: api),
      notifications: NotificationService(api: api, client: client),
      push: push,
      navigatorKey: GlobalKey<NavigatorState>(),
    );

    // A tapped push and a tapped in-app notification share one deep-link path.
    _pushOpens = push.onOpen.listen(_services.openPush);

    _services.auth.addListener(_onAuthChanged);
    unawaited(_services.auth.ensureAccount());
  }

  void _onAuthChanged() {
    final state = _services.auth.state;
    if (state == _lastAuthState) return;
    final previous = _lastAuthState;
    _lastAuthState = state;

    if (state == AuthState.signedIn) {
      unawaited(_services.notifications.start());
    } else if (previous == AuthState.signedIn) {
      unawaited(_services.onSignedOut());
    }
  }

  @override
  void dispose() {
    _pushOpens?.cancel();
    _services.auth.removeListener(_onAuthChanged);
    _services.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: _services,
      child: MaterialApp(
        title: 'PW',
        navigatorKey: _services.navigatorKey,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.purple),
          useMaterial3: true,
        ),
        // Without a darkTheme, Flutter renders `theme` no matter what the phone
        // is set to, so the Journal palette could never see Brightness.dark.
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.purple,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        themeMode: ThemeMode.system,
        builder: (context, child) => NotificationBannerHost(
          services: _services,
          child: child ?? const SizedBox.shrink(),
        ),
        home: const _AuthGate(),
      ),
    );
  }
}

/// Splash while the session is being restored, then login or the app.
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);

    return ListenableBuilder(
      listenable: services.auth,
      builder: (context, _) {
        switch (services.auth.state) {
          case AuthState.unknown:
            return const _SplashScreen();
          case AuthState.signedOut:
            // There is no login screen. The only way to be signed out is that
            // provisioning an account could not reach the server, so offer a
            // retry rather than asking for credentials the user never set.
            return const _AccountSetupFailed();
          case AuthState.signedIn:
            return const HomeScreen();
        }
      },
    );
  }
}

/// Shown when we could not reach the server to provision an account.
///
/// This replaces what used to be the login screen: the user has no
/// credentials to type, so the only useful thing to offer is a retry and the
/// address we tried.
class _AccountSetupFailed extends StatefulWidget {
  const _AccountSetupFailed();

  @override
  State<_AccountSetupFailed> createState() => _AccountSetupFailedState();
}

class _AccountSetupFailedState extends State<_AccountSetupFailed> {
  bool _retrying = false;

  Future<void> _retry() async {
    setState(() => _retrying = true);
    await AppScope.of(context).auth.ensureAccount();
    if (mounted) setState(() => _retrying = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = JournalTheme.of(context);
    final services = AppScope.of(context);
    final error = services.auth.lastError;

    return Scaffold(
      backgroundColor: t.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, size: 48, color: t.textMuted),
              const SizedBox(height: 20),
              Text(
                "Couldn't reach the server",
                style: t.headline.copyWith(fontSize: 22),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                error != null && error.isNetwork
                    ? 'Your account is set up automatically the first time you '
                        'open the app, but nothing answered at\n'
                        '${services.client.config.baseUrl}'
                    : error?.message ?? 'Something went wrong setting up your account.',
                style: t.subhead,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _retrying ? null : _retry,
                style: FilledButton.styleFrom(
                  backgroundColor: t.action,
                  foregroundColor: t.onAccent(t.action),
                ),
                child: _retrying
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final t = JournalTheme.of(context);

    return Scaffold(
      backgroundColor: t.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('PW', style: t.headline),
            const SizedBox(height: 20),
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, color: t.action),
            ),
          ],
        ),
      ),
    );
  }
}

/// The four-tab shell. Unchanged in structure — the Journey tab in particular
/// is untouched.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const List<Widget> _screens = <Widget>[
    JournalScreen(),
    JourneyScreen(),
    FriendsScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final t = JournalTheme.of(context);
    final services = AppScope.of(context);

    // The selected tab lives on AppServices so a deep-link can switch to the
    // Friends tab from outside the widget tree.
    return ValueListenableBuilder<int>(
      valueListenable: services.tab,
      builder: (context, index, _) {
        final safeIndex = index.clamp(0, _screens.length - 1);
        return Scaffold(
          // Only the visible tab is built, as before — the Journey tab drives
          // animation tickers that must not run while it is off screen.
          body: _screens[safeIndex],
          bottomNavigationBar: BottomNavigationBar(
            items: const <BottomNavigationBarItem>[
              BottomNavigationBarItem(icon: Icon(Icons.book), label: 'Journal'),
              BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Journey'),
              BottomNavigationBarItem(
                icon: Icon(Icons.people),
                label: 'Friends',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person),
                label: 'Profile',
              ),
            ],
            currentIndex: safeIndex,
            onTap: (value) => services.tab.value = value,
            type: BottomNavigationBarType.fixed,
            backgroundColor: t.background,
            selectedItemColor: t.action,
            unselectedItemColor: t.textMuted,
          ),
        );
      },
    );
  }
}
