import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';

/// View-once chat media: compress → E2E encrypt → upload ciphertext to the
/// private `chat-media` bucket. Files are deleted the moment the recipient
/// opens them — nothing retrievable stays on the server.
class ChatMediaService {
  final SupabaseClient _client = Supabase.instance.client;

  /// Compress for chat: longest side 1080px, JPEG quality 80.
  Uint8List compressChatImage(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw ArgumentError('Unsupported image format');
    var resized = decoded;
    if (decoded.width > 1080 || decoded.height > 1080) {
      resized = img.copyResize(
        decoded,
        width: decoded.width >= decoded.height ? 1080 : null,
        height: decoded.height > decoded.width ? 1080 : null,
      );
    }
    return Uint8List.fromList(img.encodeJpg(resized, quality: 80));
  }

  Future<void> uploadCipher(String path, Uint8List cipherBytes) async {
    await _client.storage.from('chat-media').uploadBinary(
          path,
          cipherBytes,
          fileOptions:
              const FileOptions(contentType: 'application/octet-stream'),
        );
  }

  Future<Uint8List> downloadCipher(String path) async {
    return _client.storage.from('chat-media').download(path);
  }

  Future<void> delete(String path) async {
    await _client.storage.from('chat-media').remove([path]);
  }
}
