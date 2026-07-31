import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../state/providers.dart';
import '../theme.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _wipe(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Wipe this device?'),
        content: const Text(
          'Your identity will be removed from this device. You can only get it '
          'back with your 12-word recovery phrase.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Wipe', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(authServiceProvider).signOutAndWipe();
    ref.invalidate(appSessionProvider);
    ref.invalidate(conversationsProvider);
    if (context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(appSessionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: sessionAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (session) {
          if (session == null) {
            return const Center(child: Text('No account on this device.'));
          }
          final identity = session.identity;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // -------------------------------------------------- Account ID
              const _SectionTitle('Your Account ID'),
              const SizedBox(height: 8),
              const Text(
                'Share this — or the QR — with people you want to chat with. It reveals nothing about you.',
                style: TextStyle(color: NyvoxTheme.textSecondary),
              ),
              const SizedBox(height: 16),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: QrImageView(
                    data: identity.accountId,
                    size: 180,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SelectableText(
                identity.accountId,
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy Account ID'),
                  onPressed: () async {
                    await Clipboard.setData(
                        ClipboardData(text: identity.accountId));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Account ID copied')),
                      );
                    }
                  },
                ),
              ),
              const Divider(height: 40),

              // -------------------------------------------- Recovery phrase
              const _SectionTitle('Recovery phrase'),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.key_outlined),
                title: const Text('Reveal recovery phrase'),
                subtitle: const Text('The only way to restore your account'),
                onTap: () => _showPhrase(context, identity.mnemonic),
              ),
              const Divider(height: 40),

              // --------------------------------------------------- Danger zone
              const _SectionTitle('Danger zone'),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.delete_forever_outlined,
                    color: Colors.redAccent),
                title: const Text('Sign out & wipe this device',
                    style: TextStyle(color: Colors.redAccent)),
                subtitle: const Text('Removes your identity from this device'),
                onTap: () => _wipe(context, ref),
              ),
              const SizedBox(height: 40),
              const Center(
                child: Text(
                  'Nyvox · send messages, not metadata',
                  style: TextStyle(color: NyvoxTheme.textSecondary, fontSize: 12),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showPhrase(BuildContext context, String mnemonic) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recovery phrase'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Never share these words. Anyone with them controls your account.',
              style: TextStyle(color: NyvoxTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            SelectableText(
              mnemonic,
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 15),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: mnemonic));
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: NyvoxTheme.accent,
        letterSpacing: 0.4,
      ),
    );
  }
}
