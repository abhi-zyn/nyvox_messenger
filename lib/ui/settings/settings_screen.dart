import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/models.dart';
import '../../services/profile_service.dart';
import '../../state/providers.dart';
import '../theme.dart';

/// One-click invite links resolve through the `u` edge function, which
/// redirects into the app using the nyvox:// deep-link scheme.
const String kInviteBase =
    'https://vodttlhalrzqpsmowpaz.supabase.co/functions/v1/u';

String inviteUrlFor(String accountId) => '$kInviteBase/$accountId';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  /// Wraps the QR card so it can be rasterised and shared as a PNG.
  final GlobalKey _qrKey = GlobalKey();

  Profile? _me;
  bool _uploadingPhoto = false;
  bool _sharingQr = false;

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

  // ------------------------------------------------------------ display name
  Future<void> _changeName() async {
    final session = await ref.read(appSessionProvider.future);
    if (session == null) return;
    final controller = TextEditingController(text: _me?.displayName ?? '');

    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change display name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(hintText: 'Your name'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (name == null || name.trim().isEmpty) return;
    try {
      await ref
          .read(authServiceProvider)
          .updateDisplayName(session.accountId, name);
      await _loadProfile();
      ref.invalidate(conversationsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Display name updated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update name: $e')),
        );
      }
    }
  }

  // ----------------------------------------------------------- profile photo
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

  // ----------------------------------------------------------------- sharing
  String _inviteText(String accountId) {
    final name = _me?.displayName ?? 'A Nyvox user';
    return '🕶️ $name invited you to chat privately on Nyvox — end-to-end '
        'encrypted, no phone number needed.\n\n'
        'Tap to start chatting:\n${inviteUrlFor(accountId)}\n\n'
        'Or add me manually with this Account ID:\n$accountId';
  }

  void _shareInvite(String accountId) {
    Share.share(_inviteText(accountId));
  }

  /// Rasterise the branded QR card and share it as a real image.
  Future<void> _shareQrImage(String accountId) async {
    if (_sharingQr) return;
    setState(() => _sharingQr = true);
    try {
      final boundary =
          _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();
      final path = await ref
          .read(fileServiceProvider)
          .writeTempFile('nyvox-invite.png', bytes);
      await Share.shareXFiles(
        [XFile(path)],
        text: _inviteText(accountId),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not share QR: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharingQr = false);
    }
  }

  // -------------------------------------------------------------------- wipe
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
          final accountId = identity.accountId;
          final inviteUrl = inviteUrlFor(accountId);

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // ----------------------------------------------------- profile
              const _SectionTitle('Profile'),
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
                    const SizedBox(height: 10),
                    Text(
                      _me?.displayName ?? 'Nyvox user',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      alignment: WrapAlignment.center,
                      children: [
                        TextButton.icon(
                          icon: _uploadingPhoto
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.photo_camera_outlined,
                                  size: 18),
                          label: Text(
                              _uploadingPhoto ? 'Uploading…' : 'Change photo'),
                          onPressed: _uploadingPhoto ? null : _changePhoto,
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Change name'),
                          onPressed: _changeName,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 40),

              // -------------------------------------------------- invite/QR
              const _SectionTitle('Invite someone'),
              const SizedBox(height: 8),
              const Text(
                'Share your link or QR — one tap opens a chat with you. Neither reveals anything about you.',
                style: TextStyle(color: NyvoxTheme.textSecondary),
              ),
              const SizedBox(height: 16),
              RepaintBoundary(
                key: _qrKey,
                child: _QrCard(
                  data: inviteUrl,
                  name: _me?.displayName ?? 'Nyvox user',
                  emoji: _me?.avatarEmoji ?? '🕶️',
                  avatarUrl: _me?.avatarUrl,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 4,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.link, size: 18),
                    label: const Text('Copy link'),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: inviteUrl));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Invite link copied')),
                        );
                      }
                    },
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.share_outlined, size: 18),
                    label: const Text('Share link'),
                    onPressed: () => _shareInvite(accountId),
                  ),
                  TextButton.icon(
                    icon: _sharingQr
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.qr_code_2, size: 18),
                    label: const Text('Share QR image'),
                    onPressed: _sharingQr ? null : () => _shareQrImage(accountId),
                  ),
                ],
              ),
              const Divider(height: 40),

              // -------------------------------------------------- account id
              const _SectionTitle('Your Account ID'),
              const SizedBox(height: 8),
              SelectableText(
                accountId,
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy ID'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: accountId));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Account ID copied')),
                      );
                    }
                  },
                ),
              ),
              const Divider(height: 40),

              // -------------------------------------------- recovery phrase
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

              // ------------------------------------------------- danger zone
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
                  style:
                      TextStyle(color: NyvoxTheme.textSecondary, fontSize: 12),
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

/// Branded invite card: avatar + name on top, the Nyvox logo watermarked in
/// the centre of the code, tagline beneath. High error correction keeps the
/// code scannable with the embedded logo. Rendered on an opaque background so
/// it rasterises cleanly when shared as a PNG.
class _QrCard extends StatelessWidget {
  const _QrCard({
    required this.data,
    required this.name,
    required this.emoji,
    this.avatarUrl,
  });

  final String data;
  final String name;
  final String emoji;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: NyvoxTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NyvoxTheme.border),
      ),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      child: Column(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: NyvoxTheme.surfaceRaised,
            backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl!) : null,
            child: avatarUrl == null
                ? Text(emoji, style: const TextStyle(fontSize: 22))
                : null,
          ),
          const SizedBox(height: 8),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: QrImageView(
              data: data,
              size: 190,
              backgroundColor: Colors.white,
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
