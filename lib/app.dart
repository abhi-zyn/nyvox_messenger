import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state/providers.dart';
import 'ui/home/home_screen.dart';
import 'ui/onboarding/onboarding_screen.dart';
import 'ui/theme.dart';

class NyvoxApp extends ConsumerWidget {
  const NyvoxApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(appSessionProvider);

    return MaterialApp(
      title: 'Nyvox',
      debugShowCheckedModeBanner: false,
      theme: NyvoxTheme.dark(),
      home: switch (session) {
        // Identity found on this device → chats; none → onboarding.
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
        // Loading and any other state.
        _ => const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
      },
    );
  }
}
