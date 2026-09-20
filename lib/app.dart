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
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  String? _lastInviteId;

  @override
  void initState() {
    super.initState();
    _listenForInviteLinks();
  }

  Future<void> _listenForInviteLinks() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _queueInvite(initial);
    } catch (_) {}

    _linkSubscription = _appLinks.uriLinkStream.listen(
      _queueInvite,
      onError: (_) {},
    );
  }

  void _queueInvite(Uri uri) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _openInvite(uri));
  }

  Future<void> _openInvite(Uri uri) async {
    final segments =
        uri.pathSegments.where((segment) => segment.isNotEmpty).toList();
    final accountId = segments.isNotEmpty
        ? segments.last
        : (uri.host != 'u' ? uri.host : '');

    if (!RegExp(r'^vc[0-9a-f]{64}$').hasMatch(accountId) ||
        accountId == _lastInviteId) {
      return;
    }

    final session = await ref.read(appSessionProvider.future);
    if (session == null || session.accountId == accountId) return;

    try {
      final service = ref.read(chatServiceProvider);
      final peer = await service.lookupAccount(accountId);
      if (peer == null) return;
      final conversationId = await service.openDm(accountId);
      _lastInviteId = accountId;
      ref.invalidate(conversationsProvider);

      final navigator = _navigatorKey.currentState;
      if (navigator == null) return;
      await navigator.push(
        MaterialPageRoute(
          builder: (_) =>
              ChatScreen(conversationId: conversationId, peer: peer),
        ),
      );
      _lastInviteId = null;
    } catch (_) {
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
    final session = ref.watch(appSessionProvider);

    return MaterialApp(
      navigatorKey: _navigatorKey,
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
