import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

import '../../models/models.dart';
import '../../services/file_service.dart';
import '../../state/providers.dart';
import '../theme.dart';

/// Shared bubble chrome for every view-once attachment type.
class _AttachmentShell extends StatelessWidget {
  const _AttachmentShell({required this.isMine, required this.child});

  final bool isMine;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.all(10),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.76),
        decoration: BoxDecoration(
          color: isMine ? NyvoxTheme.accent : NyvoxTheme.surfaceRaised,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMine ? 18 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 18),
          ),
        ),
        child: child,
      ),
    );
  }
}

/// A view-once PHOTO. Tapping it decrypts in memory, shows it full screen,
/// and destroys the ciphertext on the server the moment it is opened.
class ViewOnceTile extends ConsumerStatefulWidget {
  const ViewOnceTile({super.key, required this.message, required this.peer});

  final ChatMessage message;
  final Profile peer;

  @override
  ConsumerState<ViewOnceTile> createState() => _ViewOnceTileState();
}

class _ViewOnceTileState extends ConsumerState<ViewOnceTile> {
  bool _busy = false;

  Future<void> _open() async {
    if (_busy) return;
    final session = await ref.read(appSessionProvider.future);
    if (session == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await ref.read(chatServiceProvider).openViewOnceAttachment(
            message: widget.message,
            identity: session.identity,
            peer: widget.peer,
            destroy: !widget.message.isMine,
          );
      if (bytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('This photo is no longer available')),
          );
        }
        return;
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black,
        builder: (ctx) => Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              Center(child: InteractiveViewer(child: Image.memory(bytes))),
              Positioned(
                top: 12,
                right: 12,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
              const Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: Text(
                  'View once \u2014 this photo is gone when you close it',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not open: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mine = widget.message.isMine;
    final opened = widget.message.viewedAt != null;
    final fg = mine ? Colors.black : NyvoxTheme.textPrimary;
    return _AttachmentShell(
      isMine: mine,
      child: InkWell(
        onTap: opened && !mine ? null : _open,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(opened ? Icons.visibility_off : Icons.photo_camera,
                    color: fg),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    opened ? 'Photo opened' : 'View-once photo',
                    style: TextStyle(
                        color: fg, fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  Text(
                    opened ? 'No longer available' : 'Tap to view once',
                    style: TextStyle(
                        color: mine ? Colors.black54 : NyvoxTheme.textSecondary,
                        fontSize: 11),
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

/// A view-once FILE (PDF, doc, video...). Decrypted to a temp file, opened
/// with the system viewer, then the temp copy is deleted immediately.
class ViewOnceFileTile extends ConsumerStatefulWidget {
  const ViewOnceFileTile(
      {super.key, required this.message, required this.peer});

  final ChatMessage message;
  final Profile peer;

  @override
  ConsumerState<ViewOnceFileTile> createState() => _ViewOnceFileTileState();
}

class _ViewOnceFileTileState extends ConsumerState<ViewOnceFileTile> {
  bool _busy = false;

  static String _prettySize(int? bytes) {
    if (bytes == null || bytes <= 0) return '';
    const units = ['B', 'KB', 'MB', 'GB'];
    var size = bytes.toDouble();
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(size >= 10 || unit == 0 ? 0 : 1)} ${units[unit]}';
  }

  static IconData _iconFor(String? name) {
    final ext = (name ?? '').toLowerCase().split('.').last;
    if (ext == 'pdf') return Icons.picture_as_pdf;
    if (['doc', 'docx', 'txt', 'rtf', 'odt'].contains(ext)) {
      return Icons.description;
    }
    if (['xls', 'xlsx', 'csv'].contains(ext)) return Icons.table_chart;
    if (['mp4', 'mov', 'mkv', 'webm'].contains(ext)) return Icons.movie;
    if (['zip', 'rar', '7z'].contains(ext)) return Icons.folder_zip;
    return Icons.insert_drive_file;
  }

  Future<void> _open() async {
    if (_busy) return;
    final session = await ref.read(appSessionProvider.future);
    if (session == null) return;
    setState(() => _busy = true);
    File? temp;
    try {
      final bytes = await ref.read(chatServiceProvider).openViewOnceAttachment(
            message: widget.message,
            identity: session.identity,
            peer: widget.peer,
            destroy: !widget.message.isMine,
          );
      if (bytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('This file is no longer available')),
          );
        }
        return;
      }
      temp = await FileService().writeTempFile(
        bytes,
        widget.message.attachmentName ?? 'nyvox_file',
      );
      await OpenFilex.open(temp.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not open file: $e')));
      }
    } finally {
      // Never leave plaintext lying around on disk.
      if (temp != null) {
        Future.delayed(const Duration(minutes: 2), () async {
          try {
            if (await temp!.exists()) await temp.delete();
          } catch (_) {}
        });
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final mine = m.isMine;
    final opened = m.viewedAt != null;
    final fg = mine ? Colors.black : NyvoxTheme.textPrimary;
    final sub = mine ? Colors.black54 : NyvoxTheme.textSecondary;
    final size = _prettySize(m.attachmentSize);

    return _AttachmentShell(
      isMine: mine,
      child: InkWell(
        onTap: opened && !mine ? null : _open,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _busy
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(opened ? Icons.lock_outline : _iconFor(m.attachmentName),
                    color: fg, size: 26),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    m.attachmentName ?? 'Encrypted file',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: fg, fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  Text(
                    opened
                        ? 'Opened \u2014 no longer available'
                        : [if (size.isNotEmpty) size, 'Tap to open once']
                            .join(' \u00b7 '),
                    style: TextStyle(color: sub, fontSize: 11),
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

/// An encrypted voice note. Decrypted to a temp file for playback only.
class VoiceNoteBubble extends ConsumerStatefulWidget {
  const VoiceNoteBubble({super.key, required this.message, required this.peer});

  final ChatMessage message;
  final Profile peer;

  @override
  ConsumerState<VoiceNoteBubble> createState() => _VoiceNoteBubbleState();
}

class _VoiceNoteBubbleState extends ConsumerState<VoiceNoteBubble> {
  final AudioPlayer _player = AudioPlayer();
  File? _temp;
  bool _busy = false;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playing = false;
          _position = Duration.zero;
        });
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    final t = _temp;
    if (t != null) {
      t.exists().then((e) {
        if (e) t.delete().catchError((_) => t);
      }).catchError((_) {});
    }
    super.dispose();
  }

  static String _fmt(Duration d) {
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inMinutes}:$s';
  }

  Future<void> _toggle() async {
    if (_busy) return;
    if (_playing) {
      await _player.pause();
      if (mounted) setState(() => _playing = false);
      return;
    }
    if (_temp != null && await _temp!.exists()) {
      await _player.resume();
      if (mounted) setState(() => _playing = true);
      return;
    }

    final session = await ref.read(appSessionProvider.future);
    if (session == null) return;
    setState(() => _busy = true);
    try {
      // Voice notes stay replayable for the owner of the chat, so we decrypt
      // WITHOUT destroying the ciphertext.
      final Uint8List? bytes =
          await ref.read(chatServiceProvider).openViewOnceAttachment(
                message: widget.message,
                identity: session.identity,
                peer: widget.peer,
                destroy: false,
              );
      if (bytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Voice note is no longer available')),
          );
        }
        return;
      }
      _temp = await FileService().writeTempFile(bytes, 'voice_note.m4a');
      await _player.play(DeviceFileSource(_temp!.path));
      if (mounted) setState(() => _playing = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not play voice note: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mine = widget.message.isMine;
    final fg = mine ? Colors.black : NyvoxTheme.textPrimary;
    final sub = mine ? Colors.black54 : NyvoxTheme.textSecondary;
    final progress = (_duration.inMilliseconds == 0)
        ? 0.0
        : (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0);

    return _AttachmentShell(
      isMine: mine,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: _toggle,
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: _busy
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(_playing ? Icons.pause_circle : Icons.play_circle,
                      size: 30, color: fg),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 130,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: sub.withValues(alpha: 0.3),
                    valueColor: AlwaysStoppedAnimation(fg),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(Icons.mic, size: 11, color: sub),
                    Text(
                      _duration == Duration.zero
                          ? 'Voice note'
                          : '${_fmt(_position)} / ${_fmt(_duration)}',
                      style: TextStyle(fontSize: 10, color: sub),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
