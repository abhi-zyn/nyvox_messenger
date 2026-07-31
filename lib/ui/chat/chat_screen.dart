import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../models/models.dart';
import '../../services/chat_media_service.dart';
import '../../state/providers.dart';
import '../theme.dart';
import 'view_once_widgets.dart';

const _disappearOptions = <String, Duration?>{
  'Off': null,
  '10 minutes': Duration(minutes: 10),
  '1 hour': Duration(hours: 1),
  '1 day': Duration(days: 1),
  '1 week': Duration(days: 7),
};

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.conversationId, required this.peer});

  final String conversationId;
  final Profile peer;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _composer = TextEditingController();
  String _disappearLabel = 'Off';
  bool _sending = false;
  bool _sendingImage = false;

  @override
  void initState() {
    super.initState();
    // Opening a chat marks its incoming messages read (clears the badge and
    // sends read receipts).
    WidgetsBinding.instance.addPostFrameCallback((_) => _markRead());
  }

  @override
  void dispose() {
    _composer.dispose();
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

  Future<void> _send() async {
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
            disappearAfter: _disappearOptions[_disappearLabel],
          );
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
    if (session == null || _sendingImage) return;
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (picked == null) return;
      setState(() => _sendingImage = true);
      final bytes = await picked.readAsBytes();
      final compressed = ChatMediaService().compressChatImage(bytes);
      await ref.read(chatServiceProvider).sendViewOnceImage(
            conversationId: widget.conversationId,
            identity: session.identity,
            peer: widget.peer,
            compressedJpg: compressed,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send photo: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingImage = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final args = (conversationId: widget.conversationId, peer: widget.peer);

    // While the chat is open, mark any new incoming messages read.
    ref.listen(messagesProvider(args), (previous, next) {
      final items = next.value;
      if (items != null && items.any((m) => !m.isMine && m.readAt == null)) {
        _markRead();
      }
    });

    final messages = ref.watch(messagesProvider(args));
    final avatarUrl = widget.peer.avatarUrl;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: NyvoxTheme.surfaceRaised,
              backgroundImage:
                  avatarUrl != null ? NetworkImage(avatarUrl) : null,
              child: avatarUrl == null
                  ? Text(widget.peer.avatarEmoji)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.peer.displayName,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  Text(
                    widget.peer.shortId,
                    style: const TextStyle(
                        fontSize: 11, color: NyvoxTheme.textSecondary, fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(
              Icons.timer_outlined,
              color: _disappearLabel == 'Off' ? null : NyvoxTheme.accent,
            ),
            tooltip: 'Disappearing messages',
            initialValue: _disappearLabel,
            onSelected: (v) => setState(() => _disappearLabel = v),
            itemBuilder: (_) => [
              for (final label in _disappearOptions.keys)
                PopupMenuItem(value: label, child: Text('Disappear: $label')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_disappearLabel != 'Off')
            Container(
              width: double.infinity,
              color: NyvoxTheme.surfaceRaised,
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                '⏱ Messages disappear $_disappearLabel after sending',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: NyvoxTheme.accent),
              ),
            ),
          Expanded(
            child: messages.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Could not load messages\n$e')),
              data: (items) => items.isEmpty
                  ? const Center(
                      child: Text(
                        'Messages are end-to-end encrypted\non this device. Say hello 👋',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: NyvoxTheme.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final message = items[items.length - 1 - i];
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
            sendingImage: _sendingImage,
            onSend: _send,
            onAttach: _sendImage,
          ),
        ],
      ),
    );
  }
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
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.76),
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
              message.plaintext ?? '⚠️ could not decrypt',
              style: TextStyle(
                fontSize: 15,
                color: message.isMine ? Colors.black : NyvoxTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.expiresAt != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(Icons.timer,
                        size: 11,
                        color: message.isMine ? Colors.black54 : NyvoxTheme.textSecondary),
                  ),
                Text(
                  time,
                  style: TextStyle(
                    fontSize: 10,
                    color: message.isMine ? Colors.black54 : NyvoxTheme.textSecondary,
                  ),
                ),
                if (message.isMine) ...[
                  const SizedBox(width: 4),
                  Icon(
                    message.readAt != null ? Icons.done_all : Icons.check,
                    size: 12,
                    color: message.readAt != null ? Colors.black : Colors.black54,
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
    required this.sendingImage,
    required this.onSend,
    required this.onAttach,
  });

  final TextEditingController controller;
  final bool sending;
  final bool sendingImage;
  final VoidCallback onSend;
  final VoidCallback onAttach;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Send a view-once photo',
              icon: sendingImage
                  ? const SizedBox(
                      height: 18, width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.photo_outlined),
              onPressed: sendingImage ? null : onAttach,
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
            IconButton.filled(
              style: IconButton.styleFrom(
                backgroundColor: NyvoxTheme.accent,
                foregroundColor: Colors.black,
              ),
              icon: sending
                  ? const SizedBox(
                      height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
              onPressed: sending ? null : onSend,
            ),
          ],
        ),
      ),
    );
  }
}
