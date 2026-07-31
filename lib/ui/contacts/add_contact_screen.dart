import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
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
                    backgroundImage: _found!.avatarUrl != null
                        ? NetworkImage(_found!.avatarUrl!)
                        : null,
                    child: _found!.avatarUrl == null
                        ? Text(_found!.avatarEmoji,
                            style: const TextStyle(fontSize: 22))
                        : null,
                  ),
                  title: Text(
                    _found!.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    _found!.shortId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  ),
                  // Icon-sized button: the old text button got squeezed by the
                  // ListTile and wrapped to one letter per line.
                  trailing: IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: NyvoxTheme.accent,
                      foregroundColor: Colors.black,
                    ),
                    tooltip: 'Message',
                    icon: _opening
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.chat_bubble_outline),
                    onPressed: _opening ? null : _openChat,
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
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    // Start the camera after the first frame — starting too early can leave
    // the scanner stuck on its error placeholder even with permission granted.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await _controller.start();
      } catch (_) {
        // Already running or no camera — errorBuilder below shows the state.
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickFromGallery() async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null) return;
      final capture = await _controller.analyzeImage(file.path);
      if (!mounted) return;
      final value = (capture != null && capture.barcodes.isNotEmpty)
          ? capture.barcodes.first.rawValue
          : null;
      if (value != null && value.isNotEmpty) {
        Navigator.of(context).pop(value);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No QR code found in that image')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not scan that image')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Account QR'),
        actions: [
          IconButton(
            tooltip: 'Pick from gallery',
            icon: const Icon(Icons.photo_library_outlined),
            onPressed: _pickFromGallery,
          ),
        ],
      ),
      body: MobileScanner(
        controller: _controller,
        errorBuilder: (context, error, child) => const _ScannerErrorView(),
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

class _ScannerErrorView extends StatelessWidget {
  const _ScannerErrorView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off_outlined,
                size: 48, color: NyvoxTheme.textSecondary),
            SizedBox(height: 16),
            Text(
              'Camera unavailable',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Text(
              'Check camera permission in system Settings, then close and reopen this screen.',
              textAlign: TextAlign.center,
              style: TextStyle(color: NyvoxTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
