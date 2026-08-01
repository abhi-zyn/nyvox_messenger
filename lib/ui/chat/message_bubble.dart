import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../theme.dart';
import 'view_once_widgets.dart';

String _fmtClock(DateTime t) {
  final local = t.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

String _remaining(DateTime expiresAt) {
  final left = expiresAt.difference(DateTime.now().toUtc());
  if (left.isNegative) return 'gone';
  if (left.inDays > 0) return '${left.inDays}d';
  if (left.inHours > 0) return '${left.inHours}h';
  if (left.inMinutes > 0) return '${left.inMinutes}m';
  return '${left.inSeconds}s';
}

/// One chat bubble: text, view-once image, view-once file, or voice note.
/// Group bubbles show the sender's name above the content.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.senderName,
    this.peer,
    this.groupKey,
  });

  final ChatMessage message;
  final bool isMine;
  final String? senderName;
  final Profile? peer;
  final List<int>? groupKey;

  @override
  Widget build(BuildContext context) {
    final bg = isMine ? NyvoxTheme.accent : NyvoxTheme.bubbleOther;
    final fg = isMine ? Colors.black : NyvoxTheme.textPrimary;
    final time = _fmtClock(message.createdAt);
    final plainCard = !message.hasAttachment || message.isVoiceAttachment;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 12),
        padding: plainCard
            ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
            : EdgeInsets.zero,
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: plainCard ? bg : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isMine && senderName != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  senderName!,
                  style: const TextStyle(
                    color: NyvoxTheme.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (message.isViewOnceImage)
              ViewOnceTile(
                  message: message, isMine: isMine, peer: peer, groupKey: groupKey)
            else if (message.isFileAttachment)
              ViewOnceFileTile(
                  message: message, isMine: isMine, peer: peer, groupKey: groupKey)
            else if (message.isVoiceAttachment)
              VoiceNoteBubble(
                  message: message, isMine: isMine, peer: peer, groupKey: groupKey)
            else
              Text(message.plaintext ?? '…', style: TextStyle(color: fg)),
            if (plainCard) ...[
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (message.expiresAt != null) ...[
                    const Icon(Icons.timer, size: 11, color: NyvoxTheme.textSecondary),
                    const SizedBox(width: 3),
                    Text(_remaining(message.expiresAt!),
                        style: TextStyle(
                            fontSize: 10,
                            color: isMine ? Colors.black54 : NyvoxTheme.textSecondary)),
                    const SizedBox(width: 6),
                  ],
                  Text(time,
                      style: TextStyle(
                          fontSize: 10,
                          color: isMine ? Colors.black54 : NyvoxTheme.textSecondary)),
                  if (isMine) ...[
                    const SizedBox(width: 4),
                    ReadTicks(readAt: message.readAt),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ReadTicks extends StatelessWidget {
  const ReadTicks({super.key, this.readAt});

  final DateTime? readAt;

  @override
  Widget build(BuildContext context) {
    final read = readAt != null;
    return Icon(read ? Icons.done_all : Icons.check,
        size: 14, color: read ? Colors.blue.shade700 : Colors.black54);
  }
}
