import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state/providers.dart';
import 'ui/chat/chat_screen.dart';
import 'ui/home/home_screen.dart';
import 'ui/onboarding/onboarding_screen.dart';
import 'ui/theme.dart';

class NyvoxApp extends ConsumerStatefulWidget {
  const NyvoxApp({super.key});

  @override
  ConsumerState<NyvoxApp> createState() => _NyvoxAppState();
}

class _NyvoxAppState extends ConsumerState<NyvoxApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  String? _lastInviteId;

  /// An invite that arrived before onboarding finished. It is replayed as
  /// soon as an identity exists, so scanning a QR on a fresh install still
  /// opens the chat instead of silently doing nothing.
  Uri? _pendingInvite;

  @override
  void initState() {
    super.initState();
    _listenForInviteLinks();
  }

  Future<void> _listenForInviteLinks() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _queueInvite(initial);
    } catch (e) {
      _report('Invite link error: $e');
    }

    _linkSubscription = _appLinks.uriLinkStream.listen(
      _queueInvite,
      onError: (Object e) => _report('Invite link error: $e'),
    );
  }

  /// Invite handling used to fail silently, which looked like "the app just
  /// opens and nothing happens". Every outcome is now surfaced.
  void _report(String message) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _messengerKey.currentState
        ?..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 4),
          ),
        );
    });
  }

  /// The navigator can still be null for a few frames on a cold start that was
  /// launched *by* the invite link.
  Future<NavigatorState?> _waitForNavigator() async {
    for (var attempt = 0; attempt < 40; attempt++) {
      final navigator = _navigatorKey.currentState;
      if (navigator != null) return navigator;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return _navigatorKey.currentState;
  }

  void _queueInvite(Uri uri) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _openInvite(uri));
  }

  Future<void> _openInvite(Uri uri) async {
    final segments =
        uri.pathSegments.where((segment) => segment.isNotEmpty).toList();
    // Accept nyvox://u/<id>, nyvox://<id> and https://…/functions/v1/u/<id>.
    final accountId = (segments.isNotEmpty
            ? segments.last
            : (uri.host != 'u' ? uri.host : ''))
        .trim()
        .toLowerCase();

    if (accountId == _lastInviteId) return;

    if (!RegExp(r'^vc[0-9a-f]{64}$').hasMatch(accountId)) {
      _report('Invite link not recognised: $uri');
      return;
    }

    final session = await ref.read(appSessionProvider.future);
    if (session == null) {
      _pendingInvite = uri;
      _report('Finish setting up Nyvox — the invite will open after that.');
      return;
    }
    if (session.accountId == accountId) {
      _report('That invite link is your own.');
      return;
    }

    _lastInviteId = accountId;
    _report('Opening invite…');
    try {
      final service = ref.read(chatServiceProvider);
      final peer = await service.lookupAccount(accountId);
      if (peer == null) {
        _lastInviteId = null;
        _report('No Nyvox account found for that invite.');
        return;
      }
      final conversationId = await service.openDm(accountId);
      ref.invalidate(conversationsProvider);

      final navigator = await _waitForNavigator();
      if (navigator == null) {
        _lastInviteId = null;
        _report('Could not open the chat screen. Try the link again.');
        return;
      }
      await navigator.push(
        MaterialPageRoute(
          builder: (_) =>
              ChatScreen(conversationId: conversationId, peer: peer),
        ),
      );
    } catch (e) {
      _report('Could not open that invite: $e');
    } finally {
      _lastInviteId = null;
    }
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Replay an invite that arrived before the user had an identity.
    ref.listen(appSessionProvider, (previous, next) {
      final pending = _pendingInvite;
      if (pending != null && next.value != null) {
        _pendingInvite = null;
        _queueInvite(pending);
      }
    });

    final session = ref.watch(appSessionProvider);

    return MaterialApp(
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _messengerKey,
      title: 'Nyvox',
      debugShowCheckedModeBanner: false,
      theme: NyvoxTheme.dark(),
      home: switch (session) {
        AsyncData(:final value) =>
          value == null ? const OnboardingScreen() : const HomeScreen(),
        AsyncError(:final error) => Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not start Nyvox.\n\n$error',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        _ => const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
      },
    );
  }
}
