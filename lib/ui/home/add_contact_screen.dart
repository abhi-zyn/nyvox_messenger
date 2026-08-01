import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../data/models.dart';
import '../../state/providers.dart';
import '../theme.dart';
import 'qr_scan_screen.dart';

class AddContactScreen extends ConsumerStatefulWidget {
  const AddContactScreen({super.key});

  @override
  ConsumerState<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends ConsumerState<AddContactScreen> {
  final _controller = TextEditingController();
  Profile? _found;
  bool _searching = false;
  String? _error;

  /// Accepts a raw Account ID (vc…), a nyvox://u/<id> link, or an
  /// https invite URL — extracts the Account ID from any of them.
  String _extractAccountId(String input) {
    final t = input.trim();
    if (t.startsWith('nyvox://u/')) {
      return t.substring('nyvox://u/'.length).split('?').first;
    }
    final idx = t.indexOf('/u/');
    if (idx != -1) return t.substring(idx + 3).split('?').first;
    return t;
  }

  Future<void> _search([String? preset]) async {
    final id = _extractAccountId(preset ?? _controller.text);
    if (id.isEmpty) return;
    setState(() {
      _searching = true;
      _error = null;
      _found = null;
    });
    final profile = await ref.read(chatServiceProvider).lookupProfile(id);
    setState(() {
      _searching = false;
      _found = profile;
      if (profile == null) {
        _error = 'No user found for that ID. Double-check and try again.';
      }
    });
  }

  Future<void> _scanQr() async {
    final result = await Navigator.of(context).push<String?>(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (result == null || result.isEmpty) return;
    _controller.text = result;
    _search(result);
  }

  Future<void> _startChat() async {
    final session = await ref.read(appSessionProvider.future);
    final peer = _found;
    if (session == null || peer == null) return;
    final convoId = await ref
        .read(chatServiceProvider)
        .getOrCreateDm(session.profile.accountId, peer.accountId);
    if (!mounted) return;
    Navigator.of(context).pop((conversationId: convoId, peer: peer));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New chat')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Enter your contact's Account ID or paste their invite link.",
              style: TextStyle(color: NyvoxTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    autocorrect: false,
                    decoration: const InputDecoration(
                        hintText: 'vc…  or  https://…/u/vc…'),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.search, color: NyvoxTheme.accent),
                  onPressed: _searching ? null : () => _search(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton.icon(
                icon: const Icon(Icons.qr_code_scanner, size: 18),
                label: const Text('Scan QR code instead'),
                onPressed: _scanQr,
              ),
            ),
            const SizedBox(height: 24),
            if (_searching)
              const Center(child: CircularProgressIndicator()),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            if (_found != null)
              Card(
                child: ListTile(
                  leading: UserAvatar(
                    avatarUrl: _found!.avatarUrl,
                    fallbackText: _found!.displayName,
                    radius: 22,
                  ),
                  title: Text(_found!.displayName),
                  subtitle: Text(
                    _found!.accountId.length > 24
                        ? '${_found!.accountId.substring(0, 24)}…'
                        : _found!.accountId,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  ),
                  trailing: FilledButton.tonal(
                    onPressed: _startChat,
                    child: const Text('Chat'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
