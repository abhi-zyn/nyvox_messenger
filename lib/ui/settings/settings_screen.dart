import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/models.dart';
import '../../services/profile_service.dart';
import '../../state/providers.dart';
import '../theme.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Profile? _me;
  bool _uploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final session = await ref.read(appSessionProvider.future);
    if (session == null) return;
    try {
      final me =
          await ref.read(chatServiceProvider).lookupAccount(session.accountId);
      if (mounted) setState(() => _me = me);
    } catch (_) {}
  }

  Future<void> _changePhoto() async {
    final session = await ref.read(appSessionProvider.future);
    if (session == null || _uploadingPhoto) return;
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        imageQuality: 85,
      );
      if (picked == null) return;
      setState(() => _uploadingPhoto = true);
      final bytes = await picked.readAsBytes();
      final compressed = ProfileService().compressAvatar(bytes);
      await ProfileService().uploadAvatar(session.accountId, compressed);
      await _loadProfile();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile photo updated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update photo: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  void _shareId(String accountId) {
    final name = _me?.displayName ?? 'A Nyvox user';
    Share.share(
      '🕶️ $name invited you to chat privately on Nyvox — end-to-end encrypted, no phone number needed.\n\n'
      'Nyvox Account ID:\n$accountId\n\n'
      'Add me in the app: New conversation → paste this ID or scan my QR.\n'
      'Get Nyvox: https://github.com/abhi-zyn/nyvox_messenger',
    );
  }

  Future<void> _wipe() async {
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
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
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
              // -------------------------------------------------- Profile photo
              const _SectionTitle('Profile photo'),
              const SizedBox(height: 12),
              Center(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 44,
                      backgroundColor: NyvoxTheme.surfaceRaised,
                      backgroundImage: _me?.avatarUrl != null
                          ? NetworkImage(_me!.avatarUrl!)
                          : null,
                      child: _me?.avatarUrl == null
                          ? Text(_me?.avatarEmoji ?? '🕶️',
                              style: const TextStyle(fontSize: 36))
                          : null,
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      icon: _uploadingPhoto
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.photo_camera_outlined, size: 18),
                      label: Text(_uploadingPhoto
                          ? 'Uploading…'
                          : 'Change photo'),
                      onPressed: _uploadingPhoto ? null : _changePhoto,
                    ),
                  ],
                ),
              ),
              const Divider(height: 40),

              // -------------------------------------------------- Account ID
              const _SectionTitle('Your Account ID'),
              const SizedBox(height: 8),
              const Text(
                'Share this — or the QR — with people you want to chat with. It reveals nothing about you.',
                style: TextStyle(color: NyvoxTheme.textSecondary),
              ),
              const SizedBox(height: 16),
              _QrCard(
                accountId: identity.accountId,
                name: _me?.displayName ?? 'Nyvox user',
                emoji: _me?.avatarEmoji ?? '🕶️',
                avatarUrl: _me?.avatarUrl,
              ),
              const SizedBox(height: 12),
              SelectableText(
                identity.accountId,
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy'),
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
                  const SizedBox(width: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.share_outlined, size: 18),
                    label: const Text('Share'),
                    onPressed: () => _shareId(identity.accountId),
                  ),
                ],
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
                onTap: _wipe,
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

/// Branded Account QR card: avatar + name on top, the Nyvox logo watermarked
/// in the centre of the code, and the tagline beneath. High error correction
/// keeps the code scannable even with the embedded logo.
class _QrCard extends StatelessWidget {
  const _QrCard({
    required this.accountId,
    required this.name,
    required this.emoji,
    this.avatarUrl,
  });

  final String accountId;
  final String name;
  final String emoji;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Column(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: NyvoxTheme.surfaceRaised,
              backgroundImage:
                  avatarUrl != null ? NetworkImage(avatarUrl!) : null,
              child: avatarUrl == null
                  ? Text(emoji, style: const TextStyle(fontSize: 22))
                  : null,
            ),
            const SizedBox(height: 8),
            Text(name,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                data: accountId,
                size: 190,
                errorCorrectionLevel: QrErrorCorrectLevel.H,
                embeddedImage: const AssetImage('assets/nyvox_logo.png'),
                embeddedImageStyle: const QrEmbeddedImageStyle(
                  size: Size(46, 46),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'NYVOX · send messages, not metadata',
              style: TextStyle(
                color: NyvoxTheme.textSecondary,
                fontSize: 10,
                letterSpacing: 1.6,
              ),
            ),
          ],
        ),
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
