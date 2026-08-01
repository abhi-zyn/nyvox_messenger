import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

import '../../data/models.dart';
import '../../state/providers.dart';
import '../theme.dart';

String _fmtBytes(int? bytes) {
  if (bytes == null) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _fmtDur(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// Blurred view-once image tile — recipient taps to reveal; the image is
/// then destroyed everywhere. Sender sees a non-interactive "sent" state.
class ViewOnceTile extends ConsumerStatefulWidget {
  const ViewOnceTile({
    super.key,
    required this.message,
    required this.isMine,
    this.peer,
    this.groupKey,
  });

  final ChatMessage message;
  final bool isMine;
  final Profile? peer;
  final List<int>? groupKey;

  @override
  ConsumerState<ViewOnceTile> createState() => _ViewOnceTileState();
}

class _ViewOnceTileState extends ConsumerState<ViewOnceTile> {
  bool _opening = false;

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final session = await ref.read(appSessionProvider.future);
      if (session == null) return;
      final bytes = await ref.read(chatServiceProvider).openAttachment(
            message: widget.message,
            session: session,
            peer: widget.peer,
            groupKey: widget.groupKey,
          );
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            ViewOnceImagePage(imageBytes: Uint8List.fromList(bytes)),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the photo')),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.isMine ? 'You sent a photo' : 'Photo';
    return GestureDetector(
      onTap: widget.isMine || _opening ? null : _open,
      child: Container(
        width: 220,
        height: 150,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: NyvoxTheme.accent.withValues(alpha: 0.4)),
        ),
        child: Center(
          child: _opening
              ? const CircularProgressIndicator(strokeWidth: 2)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('📷', style: TextStyle(fontSize: 28)),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.isMine ? 'View-once' : 'Tap to view',
                      style: const TextStyle(
                        color: NyvoxTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Full-screen viewer for a view-once image. Nothing is written to disk.
class ViewOnceImagePage extends StatelessWidget {
  const ViewOnceImagePage({super.key, required this.imageBytes});

  final Uint8List imageBytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('View-once photo'),
      ),
      body: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              child: Center(child: Image.memory(imageBytes)),
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              '🔥 This photo is destroyed everywhere when you close it',
              textAlign: TextAlign.center,
              style: TextStyle(color: NyvoxTheme.textSecondary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// View-once file tile (PDF, documents…). Tapping decrypts the file,
/// opens it once in a temp viewer, then destroys it everywhere.
class ViewOnceFileTile extends ConsumerStatefulWidget {
  const ViewOnceFileTile({
    super.key,
    required this.message,
    required this.isMine,
    this.peer,
    this.groupKey,
  });

  final ChatMessage message;
  final bool isMine;
  final Profile? peer;
  final List<int>? groupKey;

  @override
  ConsumerState<ViewOnceFileTile> createState() => _ViewOnceFileTileState();
}

class _ViewOnceFileTileState extends ConsumerState<ViewOnceFileTile> {
  bool _opening = false;

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    String? tempPath;
    try {
      final session = await ref.read(appSessionProvider.future);
      if (session == null) return;
      final files = ref.read(fileServiceProvider);
      final bytes = await ref.read(chatServiceProvider).openAttachment(
            message: widget.message,
            session: session,
            peer: widget.peer,
            groupKey: widget.groupKey,
          );
      tempPath = await files.writeTempFile(
          widget.message.attachmentName ?? 'nyvox-file', bytes);
      await OpenFilex.open(tempPath);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the file')),
        );
      }
    } finally {
      if (tempPath != null) {
        await ref.read(fileServiceProvider).deleteTempFile(tempPath);
      }
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.isMine || _opening ? null : _open,
      child: Container(
        width: 240,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: NyvoxTheme.accent.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            _opening
                ? const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.insert_drive_file,
                    color: NyvoxTheme.accent, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.message.attachmentName ?? 'File',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_fmtBytes(widget.message.attachmentSize)} · '
                    '${widget.isMine ? 'View-once' : 'Tap to open once'}',
                    style: const TextStyle(
                      color: NyvoxTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// WhatsApp-style voice note bubble with play/pause and progress.
/// Voice notes are encrypted like everything else but persist in the chat.
class VoiceNoteBubble extends ConsumerStatefulWidget {
  const VoiceNoteBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.peer,
    this.groupKey,
  });

  final ChatMessage message;
  final bool isMine;
  final Profile? peer;
  final List<int>? groupKey;

  @override
  ConsumerState<VoiceNoteBubble> createState() => _VoiceNoteBubbleState();
}

class _VoiceNoteBubbleState extends ConsumerState<VoiceNoteBubble> {
  final AudioPlayer _player = AudioPlayer();
  bool _loading = false;
  bool _playing = false;
  String? _path;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player.onDurationChanged
        .listen((d) => setState(() => _duration = d));
    _player.onPositionChanged
        .listen((p) => setState(() => _position = p));
    _player.onPlayerComplete.listen((_) => setState(() {
          _playing = false;
          _position = Duration.zero;
        }));
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      setState(() => _playing = false);
      return;
    }
    if (_path == null) {
      setState(() => _loading = true);
      try {
        final session = await ref.read(appSessionProvider.future);
        if (session == null) return;
        final bytes = await ref.read(chatServiceProvider).openAttachment(
              message: widget.message,
              session: session,
              peer: widget.peer,
              groupKey: widget.groupKey,
            );
        _path = await ref
            .read(fileServiceProvider)
            .writeTempFile('voice_${widget.message.id}.m4a', bytes);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not play the voice note')),
          );
        }
        return;
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
    await _player.play(DeviceFileSource(_path!));
    setState(() => _playing = true);
  }

  @override
  Widget build(BuildContext context) {
    final progress = _duration.inMilliseconds == 0
        ? 0.0
        : _position.inMilliseconds / _duration.inMilliseconds;
    return Container(
      width: 230,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: _loading ? null : _toggle,
            icon: _loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(_playing ? Icons.pause : Icons.play_arrow),
            color: widget.isMine ? Colors.black : NyvoxTheme.accent,
          ),
          Expanded(
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              backgroundColor: widget.isMine
                  ? Colors.black26
                  : NyvoxTheme.accent.withValues(alpha: 0.2),
              color: widget.isMine ? Colors.black : NyvoxTheme.accent,
              minHeight: 3,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _fmtDur(_position > Duration.zero ? _position : _duration),
            style: TextStyle(
              fontSize: 11,
              color: widget.isMine ? Colors.black87 : NyvoxTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
