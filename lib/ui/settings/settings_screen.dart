import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/supabase_client.dart';
import '../../state/app_session.dart';
import '../../state/providers.dart';
import '../theme.dart';
import 'qr_scan_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, required this.session});

  final AppSession session;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _busy = false;
  final _qrKey = GlobalKey();
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _avatarUrl = widget.session.profile.avatarUrl;
  }

  /// One-click invite: opens Nyvox directly (deep link) with a manual
  /// Account-ID fallback for people who don't have the app yet.
  String get _inviteUrl =>
      '$kSupabaseUrl/functions/v1/u/${widget.session.profile.accountId}';

  Future<void> _changePhoto() async {
    setState(() => _busy = true);
    try {
      final bytes = await ref
          .read(avatarServiceProvider)
          .pickAndCompress(maxSide: 512, quality: 70);
      if (bytes == null) return;
      final url = await ref.read(avatarServiceProvider).uploadAvatar(
          widget.session.profile.accountId, bytes);
      setState(() => _avatarUrl = url);
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
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeName() async {
    final controller = TextEditingController(
        text: widget.session.profile.displayName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change display name'),
        content: TextField(
          controller: controller,
          maxLength: 32,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Display name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (name == null ||
        name.isEmpty ||
        name == widget.session.profile.displayName) {
      return;
    }
    await ref
        .read(authServiceProvider)
        .updateDisplayName(widget.session.profile.accountId, name);
    ref.invalidate(appSessionProvider);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Display name updated')));
    }
  }

  void _showRecoveryPhrase() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recovery phrase'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Anyone with these 12 words can take over your account. Never share them.',
              style: TextStyle(color: NyvoxTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            SelectableText(
              widget.session.identity.mnemonic,
              style: const TextStyle(fontFamily: 'monospace', height: 1.6),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(
                  ClipboardData(text: widget.session.identity.mnemonic));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied')),
              );
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This permanently deletes your profile, memberships and messages from the server. If you have your recovery phrase, you can restore the account later.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete forever',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(authServiceProvider).deleteAccount();
      ref.invalidate(appSessionProvider);
    } catch (e) {
      setState(() => _busy = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
    }
  }

  /// Renders the QR card to a PNG and shares it as an image.
  Future<void> _shareQrImage() async {
    try {
      final boundary = _qrKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final path = await ref.read(fileServiceProvider).writeTempFile(
          'nyvox-invite.png', byteData.buffer.asUint8List());
      await Share.shareXFiles([XFile(path)],
          text: 'Chat with me on Nyvox — end-to-end encrypted:\n$_inviteUrl');
    } catch (_) {}
  }

  Future<void> _scanQr() async {
    final result = await Navigator.of(context).push<String?>(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (result == null || result.isEmpty) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Scanned: ${result.substring(0, result.length > 24 ? 24 : result.length)}…')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.session.profile;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              UserAvatar(
                  avatarUrl: _avatarUrl,
                  fallbackText: profile.displayName,
                  radius: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(profile.displayName,
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w700),
                              overflow: TextOverflow.ellipsis),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit,
                              size: 18, color: NyvoxTheme.accent),
                          onPressed: _changeName,
                          tooltip: 'Change display name',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.photo_camera,
                color: NyvoxTheme.accent),
            title: const Text('Update profile photo'),
            subtitle: const Text(
                'Compressed on your phone before upload',
                style: TextStyle(fontSize: 12)),
            onTap: _busy ? null : _changePhoto,
          ),
          const SizedBox(height: 12),
          const Text('Invite & QR',
              style: TextStyle(color: NyvoxTheme.textSecondary)),
          const SizedBox(height: 8),
          RepaintBoundary(
            key: _qrKey,
            child: Container(
              color: NyvoxTheme.bg,
              padding: const EdgeInsets.all(8),
              child: _QrCard(session: widget.session, inviteUrl: _inviteUrl),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy link'),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _inviteUrl));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Invite link copied')),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.share, size: 18),
                  label: const Text('Share QR image'),
                  onPressed: _shareQrImage,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: const Text('Scan QR'),
                  onPressed: _scanQr,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.ios_share, size: 18),
                  label: const Text('Share link'),
                  onPressed: () => Share.share(
                    'Chat with me on Nyvox — end-to-end encrypted, no phone number needed.\nTap to open a chat with me: $_inviteUrl',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.lock_outline,
                color: NyvoxTheme.accent),
            title: const Text('App lock'),
            subtitle: const Text(
              'Require device unlock (fingerprint / face) every time Nyvox opens',
              style: TextStyle(fontSize: 12),
            ),
            value: ref.watch(appLockProvider),
            onChanged: (v) =>
                ref.read(appLockProvider.notifier).state = v,
          ),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.vpn_key, color: NyvoxTheme.accent),
            title: const Text('Recovery phrase'),
            subtitle: const Text('Show my 12 words'),
            onTap: _showRecoveryPhrase,
          ),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.delete_forever,
                color: Colors.redAccent),
            title: const Text('Delete account',
                style: TextStyle(color: Colors.redAccent)),
            subtitle: const Text(
                'Erase your data from the server and this device'),
            onTap: _busy ? null : _deleteAccount,
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

/// Branded QR invite card: avatar + name + QR + Nyvox watermark.
class _QrCard extends StatelessWidget {
  const _QrCard({required this.session, required this.inviteUrl});

  final AppSession session;
  final String inviteUrl;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            UserAvatar(
                avatarUrl: session.profile.avatarUrl,
                fallbackText: session.profile.displayName,
                radius: 26),
            const SizedBox(height: 10),
            Text(
              session.profile.displayName,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            const Text(
              'Scan to chat on Nyvox',
              style: TextStyle(
                  color: NyvoxTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 14),
            Stack(
              alignment: Alignment.center,
              children: [
                QrImageView(
                  data: inviteUrl,
                  version: QrVersions.auto,
                  size: 220,
                  errorCorrectionLevel: QrErrorCorrectLevel.H,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Color(0xFF0B0E11)),
                  dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Color(0xFF0B0E11)),
                ),
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: NyvoxTheme.bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'N',
                    style: TextStyle(
                      color: NyvoxTheme.accent,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'NYVOX · send messages, not metadata',
              style: TextStyle(
                color: NyvoxTheme.accent,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
