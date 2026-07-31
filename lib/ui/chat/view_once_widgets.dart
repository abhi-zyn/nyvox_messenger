import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../state/providers.dart';
import '../theme.dart';

/// A view-once photo bubble. Tapping opens the photo full-screen; the moment
/// the recipient opens it, it is deleted from the server AND from both
/// devices (the row disappears via realtime). Photos cannot be saved —
/// decryption happens in memory only, and the app blocks screenshots.
class ViewOnceTile extends ConsumerStatefulWidget {
  const ViewOnceTile({
    super.key,
    required this.message,
    required this.peer,
  });

  final ChatMessage message;
  final Profile peer;

  @override
  ConsumerState<ViewOnceTile> createState() => _ViewOnceTileState();
}

class _ViewOnceTileState extends ConsumerState<ViewOnceTile> {
  bool _opening = false;

  Future<void> _open() async {
    if (_opening) return;
    final session = await ref.read(appSessionProvider.future);
    if (session == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('View photo?'),
        content: const Text(
          'This photo can be opened once. It is destroyed everywhere as soon as you open it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('View'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _opening = true);
    try {
      final bytes = await ref.read(chatServiceProvider).openViewOnceImage(
            identity: session.identity,
            decryptWithPublicKeyHex: widget.peer.publicKey,
            message: widget.message,
            destroy: !widget.message.isMine,
          );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ViewOnceViewer(bytes: bytes)),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Photo could not be opened (already viewed?)')),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMine = widget.message.isMine;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: _open,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isMine ? NyvoxTheme.accent : NyvoxTheme.surfaceRaised,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isMine ? 18 : 4),
              bottomRight: Radius.circular(isMine ? 4 : 18),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_opening)
                const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  Icons.photo_outlined,
                  size: 20,
                  color: isMine ? Colors.black : NyvoxTheme.accent,
                ),
              const SizedBox(width: 8),
              Text(
                isMine ? 'Photo · view once' : 'Photo · tap to view once',
                style: TextStyle(
                  fontSize: 15,
                  color: isMine ? Colors.black : NyvoxTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen viewer for a view-once photo. The decrypted bytes live only in
/// memory; closing destroys the photo everywhere (handled at open time), and
/// FLAG_SECURE blocks screenshots and screen recording app-wide.
class ViewOnceViewer extends StatelessWidget {
  const ViewOnceViewer({super.key, required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            InteractiveViewer(
              child: Center(child: Image.memory(bytes)),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Text(
                'This photo is destroyed after viewing',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
