import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../models/models.dart';
import '../../state/providers.dart';
import '../chat/chat_screen.dart';
import '../theme.dart';

/// Start a chat by entering an Account ID ("vc…") or scanning a QR code —
/// exactly how Session adds contacts, with no address-book upload.
class AddContactScreen extends ConsumerStatefulWidget {
  const AddContactScreen({super.key});

  @override
  ConsumerState<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends ConsumerState<AddContactScreen> {
  final _idController = TextEditingController();
  bool _searching = false;
  bool _opening = false;
  Profile? _found;
  String? _error;

  @override
  void dispose() {
    _idController.dispose();
    super.dispose();
  }

  Future<void> _lookup([String? rawId]) async {
    final id = (rawId ?? _idController.text).trim();
    if (id.isEmpty) return;
    if (rawId != null) _idController.text = rawId;

    setState(() {
      _searching = true;
      _error = null;
      _found = null;
    });
    try {
      final profile = await ref.read(chatServiceProvider).lookupAccount(id);
      if (!mounted) return;
      if (profile == null) {
        setState(() => _error = 'No account found with that ID.');
      } else {
        setState(() => _found = profile);
      }
    } catch (e) {
      setState(() => _error = 'Lookup failed: $e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _openChat() async {
    final peer = _found;
    if (peer == null || _opening) return;
    setState(() => _opening = true);
    try {
      final convoId = await ref.read(chatServiceProvider).openDm(peer.accountId);
      ref.invalidate(conversationsProvider);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChatScreen(conversationId: convoId, peer: peer),
        ),
      );
    } catch (e) {
      setState(() => _error = 'Could not open chat: $e');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _scanQr() async {
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _QrScanScreen()),
    );
    if (scanned != null && scanned.isNotEmpty) {
      await _lookup(scanned);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New conversation')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter an Account ID',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ask your contact to share their ID or QR code from Settings. Your address book is never uploaded.',
              style: TextStyle(color: NyvoxTheme.textSecondary),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _idController,
                    autocorrect: false,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    decoration: const InputDecoration(hintText: 'vc…'),
                    onSubmitted: (_) => _lookup(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Scan QR code',
                  icon: const Icon(Icons.qr_code_scanner),
                  onPressed: _scanQr,
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _searching ? null : () => _lookup(),
              child: _searching
                  ? const SizedBox(
                      height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Find account'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            ],
            if (_found != null) ...[
              const SizedBox(height: 24),
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: NyvoxTheme.surfaceRaised,
                    child: Text(_found!.avatarEmoji, style: const TextStyle(fontSize: 22)),
                  ),
                  title: Text(_found!.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(_found!.shortId,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                  trailing: FilledButton.tonal(
                    onPressed: _opening ? null : _openChat,
                    child: _opening
                        ? const SizedBox(
                            height: 16, width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Message'),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QrScanScreen extends StatefulWidget {
  const _QrScanScreen();

  @override
  State<_QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<_QrScanScreen> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Account QR')),
      body: MobileScanner(
        onDetect: (capture) {
          if (_handled) return;
          final value = capture.barcodes.isEmpty
              ? null
              : capture.barcodes.first.rawValue;
          if (value != null && value.isNotEmpty) {
            _handled = true;
            Navigator.of(context).pop(value);
          }
        },
      ),
    );
  }
}
