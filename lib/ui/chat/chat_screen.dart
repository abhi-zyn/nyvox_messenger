import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../data/models.dart';
import '../../state/app_session.dart';
import '../../state/providers.dart';
import '../theme.dart';
import 'message_bubble.dart';

/// Chat screen for both DMs and groups: text, view-once photos and files,
/// voice notes, and a synced disappearing timer.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.title,
    this.isGroup = false,
    this.peer,
  });

  final String conversationId;
  final String title;
  final bool isGroup;
  final Profile? peer; // DMs only

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _recorder = AudioRecorder();
  bool _sending = false;
  bool _recording = false;
  DateTime? _recordStarted;
  Timer? _recordTicker;

  @override
  void dispose() {
    _controller.dispose();
    _recordTicker?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  String get _timerLabel {
    final info = ref.read(conversationInfoProvider(widget.conversationId)).value;
    final s = info?.disappearSeconds;
    if (s == null) return 'Off';
    if (s < 3600) return '${s ~/ 60} min';
    if (s < 86400) return '${s ~/ 3600} hr';
    return '${s ~/ 86400} day';
  }

  Future<void> _sendText(AppSession session, int? timer) async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    List<int>? groupKey;
    if (widget.isGroup) {
      groupKey =
          (await ref.read(groupContextProvider(widget.conversationId).future))
              .keyBytes;
    }
    await ref.read(chatServiceProvider).sendText(
          conversationId: widget.conversationId,
          session: session,
          peer: widget.peer,
          groupKey: groupKey,
          text: text,
          disappearSeconds: timer,
        );
  }

  Future<void> _sendAttachment(
      AppSession session, List<int> bytes, String type,
      {String? name, int? size}) async {
    List<int>? groupKey;
    if (widget.isGroup) {
      groupKey =
          (await ref.read(groupContextProvider(widget.conversationId).future))
              .keyBytes;
    }
    await ref.read(chatServiceProvider).sendViewOnceAttachment(
          conversationId: widget.conversationId,
          session: session,
          peer: widget.peer,
          groupKey: groupKey,
          bytes: bytes,
          type: type,
          name: name,
          size: size,
        );
  }

  void _openAttachSheet(AppSession session) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo, color: NyvoxTheme.accent),
              title: const Text('View-once photo'),
              subtitle: const Text('Destroyed after it is opened'),
              onTap: () async {
                Navigator.pop(ctx);
                final bytes = await ref.read(fileServiceProvider).pickImage();
                if (bytes == null) return;
                await _sendAttachment(session, bytes, 'image');
              },
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file,
                  color: NyvoxTheme.accent),
              title: const Text('View-once file'),
              subtitle: const Text('PDF, document, video — opens once'),
              onTap: () async {
                Navigator.pop(ctx);
                final f = await ref.read(fileServiceProvider).pickFile();
                if (f == null) return;
                await _sendAttachment(session, f.bytes, 'file',
                    name: f.name, size: f.size);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) return;
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
    setState(() {
      _recording = true;
      _recordStarted = DateTime.now();
    });
    _recordTicker?.cancel();
    _recordTicker =
        Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  Future<void> _stopRecording(AppSession session, {required bool send}) async {
    _recordTicker?.cancel();
    final path = await _recorder.stop();
    setState(() => _recording = false);
    if (!send || path == null) {
      if (path != null) await File(path).delete().catchError((_) => File(path!));
      return;
    }
    final bytes = await File(path).readAsBytes();
    await File(path).delete().catchError((_) => File(path));
    await _sendAttachment(session, bytes, 'voice', name: 'Voice note');
  }

  Future<void> _setTimer(int? seconds) async {
    await ref
        .read(chatServiceProvider)
        .updateConversationTimer(widget.conversationId, seconds);
  }

  String get _recordingElapsed {
    if (_recordStarted == null) return '0:00';
    final d = DateTime.now().difference(_recordStarted!);
    return '${d.inMinutes}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(appSessionProvider);
    final session = sessionAsync.value;
    if (session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final myId = session.profile.accountId;
    final messagesAsync = widget.isGroup
        ? ref.watch(groupMessagesProvider(widget.conversationId))
        : ref.watch(messagesProvider(
            (conversationId: widget.conversationId, peer: widget.peer!)));
    final infoAsync = ref.watch(conversationInfoProvider(widget.conversationId));
    final timer = infoAsync.value?.disappearSeconds;
    final groupCtx = widget.isGroup
        ? ref.watch(groupContextProvider(widget.conversationId)).value
        : null;

    // Mark incoming messages read whenever the list updates.
    messagesAsync.whenData((items) {
      if (items.any((m) => m.senderAccountId != myId && m.readAt == null)) {
        ref
            .read(chatServiceProvider)
            .markConversationRead(widget.conversationId, myId);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: NyvoxTheme.accent.withValues(alpha: 0.15),
              child: Icon(
                widget.isGroup ? Icons.groups : Icons.person,
                size: 18,
                color: NyvoxTheme.accent,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title,
                      style: const TextStyle(fontSize: 16),
                      overflow: TextOverflow.ellipsis),
                  Text(
                    widget.isGroup
                        ? '${groupCtx?.members.length ?? 0} members'
                        : 'end-to-end encrypted',
                    style: const TextStyle(
                        fontSize: 11, color: NyvoxTheme.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<int?>(
            icon: const Icon(Icons.timer_outlined),
            tooltip: 'Disappearing messages ($_timerLabel)',
            onSelected: _setTimer,
            itemBuilder: (_) => const [
              PopupMenuItem(value: null, child: Text('Off')),
              PopupMenuItem(value: 600, child: Text('10 minutes')),
              PopupMenuItem(value: 3600, child: Text('1 hour')),
              PopupMenuItem(value: 86400, child: Text('1 day')),
              PopupMenuItem(value: 604800, child: Text('1 week')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (timer != null)
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: NyvoxTheme.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.timer,
                        size: 14, color: NyvoxTheme.accent),
                    const SizedBox(width: 6),
                    Text(
                      'Messages disappear $_timerLabel after sending — for everyone',
                      style: const TextStyle(
                          fontSize: 12, color: NyvoxTheme.accent),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: messagesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (items) {
                if (items.isEmpty) {
                  return const Center(
                    child: Text(
                      'No messages yet.\nEverything here is end-to-end encrypted.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: NyvoxTheme.textSecondary),
                    ),
                  );
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final m = items[items.length - 1 - i];
                    return MessageBubble(
                      message: m,
                      isMine: m.senderAccountId == myId,
                      senderName: widget.isGroup && m.senderAccountId != myId
                          ? groupCtx?.members[m.senderAccountId]?.displayName
                          : null,
                      peer: widget.peer,
                      groupKey: groupCtx?.keyBytes,
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: _recording
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.mic, color: Colors.redAccent),
                        const SizedBox(width: 8),
                        Text(_recordingElapsed,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        const Spacer(),
                        TextButton(
                          onPressed: () =>
                              _stopRecording(session, send: false),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        CircleAvatar(
                          backgroundColor: NyvoxTheme.accent,
                          child: IconButton(
                            icon: const Icon(Icons.send, color: Colors.black),
                            onPressed: () =>
                                _stopRecording(session, send: true),
                          ),
                        ),
                      ],
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.attach_file,
                              color: NyvoxTheme.accent),
                          onPressed: _sending
                              ? null
                              : () => _openAttachSheet(session),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            minLines: 1,
                            maxLines: 4,
                            decoration:
                                const InputDecoration(hintText: 'Message'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (_controller.text.trim().isEmpty)
                          CircleAvatar(
                            backgroundColor: NyvoxTheme.accent,
                            child: IconButton(
                              icon:
                                  const Icon(Icons.mic, color: Colors.black),
                              onPressed: _startRecording,
                            ),
                          )
                        else
                          CircleAvatar(
                            backgroundColor: NyvoxTheme.accent,
                            child: IconButton(
                              icon:
                                  const Icon(Icons.send, color: Colors.black),
                              onPressed: _sending
                                  ? null
                                  : () async {
                                      setState(() => _sending = true);
                                      try {
                                        await _sendText(session, timer);
                                      } finally {
                                        if (mounted) {
                                          setState(() => _sending = false);
                                        }
                                      }
                                    },
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
