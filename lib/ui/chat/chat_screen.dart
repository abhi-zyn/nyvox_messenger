import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../models/models.dart';
import '../../services/chat_media_service.dart';
import '../../services/file_service.dart';
import '../../state/providers.dart';
import '../theme.dart';
import 'view_once_widgets.dart';

/// Disappearing-message options. The selected value is stored on the
/// conversation row, so BOTH members get the same timer via realtime.
const _disappearOptions = <String, int?>{
  'Off': null,
  '10 minutes': 600,
  '1 hour': 3600,
  '1 day': 86400,
  '1 week': 604800,
};

String _timerLabel(int? seconds) {
  for (final entry in _disappearOptions.entries) {
    if (entry.value == seconds) return entry.key;
  }
  return 'Off';
}

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.conversationId, required this.peer});

  final String conversationId;
  final Profile peer;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _composer = TextEditingController();
  final AudioRecorder _recorder = AudioRecorder();

  bool _sending = false;
  bool _sendingAttachment = false;
  bool _recording = false;
  DateTime? _recordStarted;
  Timer? _recordTicker;
  bool _hasText = false;
  bool _exiting = false;

  @override
  void initState() {
    super.initState();
    _composer.addListener(() {
      final has = _composer.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _markRead());
  }

  @override
  void dispose() {
    _composer.dispose();
    _recordTicker?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _markRead() async {
    final session = await ref.read(appSessionProvider.future);
    if (session == null) return;
    await ref
        .read(chatServiceProvider)
        .markConversationRead(widget.conversationId, session.accountId);
    ref.invalidate(conversationsProvider);
  }

  Future<void> _send(int? disappearSeconds, bool highSecurity) async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending) return;

    final session = await ref.read(appSessionProvider.future);
    if (session == null) return;

    setState(() => _sending = true);
    _composer.clear();
    try {
      await ref.read(chatServiceProvider).sendMessage(
            conversationId: widget.conversationId,
            identity: session.identity,
            peer: widget.peer,
            text: text,
            highSecurity: highSecurity,
            disappearAfter: disappearSeconds == null
                ? null
                : Duration(seconds: disappearSeconds),
          );
      if (highSecurity && mounted) _showSecureSentAnimation();
    } catch (e) {
      if (mounted) {
        _composer.text = text;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Message failed to send: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Pick a photo, compress it on-device, E2E-encrypt, and send view-once.
  Future<void> _sendImage() async {
    final session = await ref.read(appSessionProvider.future);
    if (session == null || _sendingAttachment) return;
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (picked == null) return;
      setState(() => _sendingAttachment = true);
      final bytes = await picked.readAsBytes();
      final compressed = ChatMediaService().compressChatImage(bytes);
      final highSecurity = ref
              .read(conversationInfoProvider(widget.conversationId))
              .value
              ?.highSecurity ??
          false;
      await ref.read(chatServiceProvider).sendViewOnceAttachment(
            conversationId: widget.conversationId,
            identity: session.identity,
            peer: widget.peer,
            bytes: compressed,
            type: 'image',
            highSecurity: highSecurity,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send photo: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingAttachment = false);
    }
  }

  /// Pick any file (PDF, document, video...) and send it view-once.
  Future<void> _sendFile() async {
    final session = await ref.read(appSessionProvider.future);
    if (session == null || _sendingAttachment) return;
    try {
      final picked = await FileService().pickFile();
      if (picked == null) return;
      setState(() => _sendingAttachment = true);
      final highSecurity = ref
              .read(conversationInfoProvider(widget.conversationId))
              .value
              ?.highSecurity ??
          false;
      await ref.read(chatServiceProvider).sendViewOnceAttachment(
            conversationId: widget.conversationId,
            identity: session.identity,
            peer: widget.peer,
            bytes: Uint8List.fromList(picked.bytes),
            type: 'file',
            name: picked.name,
            size: picked.size,
            highSecurity: highSecurity,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send file: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingAttachment = false);
    }
  }

  void _openAttachSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: NyvoxTheme.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_outlined, color: NyvoxTheme.accent),
              title: const Text('View-once photo'),
              subtitle: const Text('Destroyed as soon as it is opened',
                  style: TextStyle(fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                _sendImage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined,
                  color: NyvoxTheme.accent),
              title: const Text('View-once file'),
              subtitle: const Text('PDF, document, video \u2014 opens once',
                  style: TextStyle(fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                _sendFile();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission is required')),
        );
      }
      return;
    }
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: path,
    );
    setState(() {
      _recording = true;
      _recordStarted = DateTime.now();
    });
    _recordTicker?.cancel();
    _recordTicker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() {}),
    );
  }

  Future<void> _stopRecording({required bool send}) async {
    _recordTicker?.cancel();
    final path = await _recorder.stop();
    if (mounted) setState(() => _recording = false);
    if (path == null) return;
    final file = File(path);
    if (!send) {
      try {
        await file.delete();
      } catch (_) {}
      return;
    }
    final session = await ref.read(appSessionProvider.future);
    if (session == null) return;
    try {
      setState(() => _sendingAttachment = true);
      final bytes = await file.readAsBytes();
      final highSecurity = ref
              .read(conversationInfoProvider(widget.conversationId))
              .value
              ?.highSecurity ??
          false;
      await ref.read(chatServiceProvider).sendViewOnceAttachment(
            conversationId: widget.conversationId,
            identity: session.identity,
            peer: widget.peer,
            bytes: bytes,
            type: 'voice',
            name: 'Voice note',
            highSecurity: highSecurity,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send voice note: $e')),
        );
      }
    } finally {
      try {
        await file.delete();
      } catch (_) {}
      if (mounted) setState(() => _sendingAttachment = false);
    }
  }

  Future<void> _setTimer(int? seconds) async {
    try {
      await ref
          .read(chatServiceProvider)
          .updateConversationTimer(widget.conversationId, seconds);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update the timer: $e')),
        );
      }
    }
  }

  Future<void> _setHighSecurity(bool enabled) async {
    if (enabled) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.security, color: NyvoxTheme.accent),
          title: const Text('Enable High Security?'),
          content: const Text(
            'Messages you send will disappear from your screen immediately. '
            'The recipient can view them only until they leave this chat, then '
            'the encrypted server copy is permanently deleted.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Enable'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    try {
      await ref
          .read(chatServiceProvider)
          .updateConversationHighSecurity(widget.conversationId, enabled);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update High Security: $e')),
        );
      }
    }
  }

  void _showSecureSentAnimation() {
    final overlay = Overlay.of(context);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: IgnorePointer(
          child: Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.65, end: 1),
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutBack,
              builder: (_, value, child) => Transform.scale(
                scale: value,
                child: Opacity(opacity: value.clamp(0, 1), child: child),
              ),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                decoration: BoxDecoration(
                  color: NyvoxTheme.surfaceRaised,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: NyvoxTheme.accent),
                  boxShadow: const [
                    BoxShadow(color: Colors.black54, blurRadius: 24),
                  ],
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock, color: NyvoxTheme.accent, size: 34),
                    SizedBox(height: 8),
                    Text(
                      'Secure message sent',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'Hidden from this device',
                      style: TextStyle(
                        color: NyvoxTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    Future.delayed(const Duration(milliseconds: 1200), entry.remove);
  }

  Future<void> _leaveChat() async {
    if (_exiting) return;
    _exiting = true;
    final session = await ref.read(appSessionProvider.future);
    if (session != null) {
      try {
        await ref.read(chatServiceProvider).purgeIncomingHighSecurity(
              widget.conversationId,
              session.accountId,
            );
      } catch (_) {
        // A later exit/open can retry; never trap the user in the chat.
      }
    }
    ref.invalidate(conversationsProvider);
    if (mounted) Navigator.of(context).pop();
  }

  String get _recordingElapsed {
    if (_recordStarted == null) return '0:00';
    final d = DateTime.now().difference(_recordStarted!);
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inMinutes}:$s';
  }

  @override
  Widget build(BuildContext context) {
    final args = (conversationId: widget.conversationId, peer: widget.peer);

    ref.listen(messagesProvider(args), (previous, next) {
      final items = next.value;
      if (items != null && items.any((m) => !m.isMine && m.readAt == null)) {
        _markRead();
      }
    });

    final messages = ref.watch(messagesProvider(args));
    final info = ref.watch(conversationInfoProvider(widget.conversationId));
    final timerSeconds = info.value?.disappearSeconds;
    final highSecurity = info.value?.highSecurity ?? false;
    final label = _timerLabel(timerSeconds);
    final avatarUrl = widget.peer.avatarUrl;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leaveChat();
      },
      child: Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: NyvoxTheme.surfaceRaised,
              backgroundImage:
                  avatarUrl != null ? NetworkImage(avatarUrl) : null,
              child: avatarUrl == null ? Text(widget.peer.avatarEmoji) : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.peer.displayName,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    widget.peer.shortId,
                    style: const TextStyle(
                      fontSize: 11,
                      color: NyvoxTheme.textSecondary,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip:
                highSecurity ? 'Disable High Security' : 'Enable High Security',
            icon: Icon(
              highSecurity ? Icons.security : Icons.security_outlined,
              color: highSecurity ? NyvoxTheme.accent : null,
            ),
            onPressed: () => _setHighSecurity(!highSecurity),
          ),
          PopupMenuButton<String>(
            icon: Icon(
              Icons.timer_outlined,
              color: timerSeconds == null ? null : NyvoxTheme.accent,
            ),
            tooltip: 'Disappearing messages ($label)',
            initialValue: label,
            onSelected: (v) => _setTimer(_disappearOptions[v]),
            itemBuilder: (_) => [
              for (final entry in _disappearOptions.entries)
                PopupMenuItem(
                  value: entry.key,
                  child: Row(
                    children: [
                      if (entry.key == label)
                        const Icon(Icons.check,
                            size: 16, color: NyvoxTheme.accent)
                      else
                        const SizedBox(width: 16),
                      const SizedBox(width: 8),
                      Text(entry.key),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (highSecurity)
            Container(
              width: double.infinity,
              color: Colors.redAccent.withValues(alpha: 0.12),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.security, size: 14, color: Colors.redAccent),
                  SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'High Security — sent messages hide immediately; '
                      'received messages are destroyed when you leave',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 12, color: Colors.redAccent),
                    ),
                  ),
                ],
              ),
            ),
          if (timerSeconds != null)
            Container(
              width: double.infinity,
              color: NyvoxTheme.accent.withValues(alpha: 0.12),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.timer, size: 14, color: NyvoxTheme.accent),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Messages disappear $label after sending \u2014 for both of you',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 12, color: NyvoxTheme.accent),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: messages.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  Center(child: Text('Could not load messages\n$e')),
              data: (items) => items.isEmpty
                  ? const Center(
                      child: Text(
                        'Messages are end-to-end encrypted\non this device. Say hello \ud83d\udc4b',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: NyvoxTheme.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final message = items[items.length - 1 - i];
                        if (message.isVoiceAttachment) {
                          return VoiceNoteBubble(
                              message: message, peer: widget.peer);
                        }
                        if (message.isFileAttachment) {
                          return ViewOnceFileTile(
                              message: message, peer: widget.peer);
                        }
                        if (message.isViewOnceImage) {
                          return ViewOnceTile(
                              message: message, peer: widget.peer);
                        }
                        return _MessageBubble(message: message);
                      },
                    ),
            ),
          ),
          _Composer(
            controller: _composer,
            sending: _sending,
            sendingAttachment: _sendingAttachment,
            recording: _recording,
            recordingElapsed: _recordingElapsed,
            hasText: _hasText,
            onSend: () => _send(timerSeconds, highSecurity),
            onAttach: _openAttachSheet,
            onStartRecording: _startRecording,
            onCancelRecording: () => _stopRecording(send: false),
            onSendRecording: () => _stopRecording(send: true),
          ),
        ],
      ),
      ),
    );
  }
}

String _remaining(DateTime expiresAt) {
  final left = expiresAt.difference(DateTime.now());
  if (left.isNegative) return 'gone';
  if (left.inDays > 0) return '${left.inDays}d';
  if (left.inHours > 0) return '${left.inHours}h';
  if (left.inMinutes > 0) return '${left.inMinutes}m';
  return '${left.inSeconds}s';
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final time = DateFormat.Hm().format(message.createdAt);
    return Align(
      alignment: message.isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.76),
        decoration: BoxDecoration(
          color: message.isMine ? NyvoxTheme.accent : NyvoxTheme.surfaceRaised,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(message.isMine ? 18 : 4),
            bottomRight: Radius.circular(message.isMine ? 4 : 18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              message.plaintext ?? '\u26a0\ufe0f could not decrypt',
              style: TextStyle(
                fontSize: 15,
                color: message.isMine ? Colors.black : NyvoxTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.expiresAt != null) ...[
                  Icon(Icons.timer,
                      size: 11,
                      color: message.isMine
                          ? Colors.black54
                          : NyvoxTheme.textSecondary),
                  const SizedBox(width: 3),
                  Text(
                    _remaining(message.expiresAt!),
                    style: TextStyle(
                      fontSize: 10,
                      color: message.isMine
                          ? Colors.black54
                          : NyvoxTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  time,
                  style: TextStyle(
                    fontSize: 10,
                    color: message.isMine
                        ? Colors.black54
                        : NyvoxTheme.textSecondary,
                  ),
                ),
                if (message.isMine) ...[
                  const SizedBox(width: 4),
                  Icon(
                    message.readAt != null ? Icons.done_all : Icons.check,
                    size: 12,
                    color:
                        message.readAt != null ? Colors.black : Colors.black54,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.sendingAttachment,
    required this.recording,
    required this.recordingElapsed,
    required this.hasText,
    required this.onSend,
    required this.onAttach,
    required this.onStartRecording,
    required this.onCancelRecording,
    required this.onSendRecording,
  });

  final TextEditingController controller;
  final bool sending;
  final bool sendingAttachment;
  final bool recording;
  final String recordingElapsed;
  final bool hasText;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final VoidCallback onStartRecording;
  final VoidCallback onCancelRecording;
  final VoidCallback onSendRecording;

  @override
  Widget build(BuildContext context) {
    if (recording) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: Row(
            children: [
              const Icon(Icons.mic, color: Colors.redAccent),
              const SizedBox(width: 8),
              Text(recordingElapsed,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton(
                onPressed: onCancelRecording,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 4),
              IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: NyvoxTheme.accent,
                  foregroundColor: Colors.black,
                ),
                icon: const Icon(Icons.send),
                onPressed: onSendRecording,
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Send a view-once photo or file',
              icon: sendingAttachment
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.attach_file),
              onPressed: sendingAttachment ? null : onAttach,
            ),
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'Message'),
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 8),
            if (hasText)
              IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: NyvoxTheme.accent,
                  foregroundColor: Colors.black,
                ),
                icon: sending
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send),
                onPressed: sending ? null : onSend,
              )
            else
              IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: NyvoxTheme.accent,
                  foregroundColor: Colors.black,
                ),
                tooltip: 'Hold-free voice note',
                icon: const Icon(Icons.mic),
                onPressed: onStartRecording,
              ),
          ],
        ),
      ),
    );
  }
}
