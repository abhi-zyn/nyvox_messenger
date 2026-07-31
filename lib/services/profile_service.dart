import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Profile avatars: picked from the gallery, compressed on-device, and
/// uploaded to the public `avatars` bucket. Only a small JPEG is stored —
/// never the original full-resolution image.
class ProfileService {
  final SupabaseClient _client = Supabase.instance.client;

  /// Compress [bytes] to a square 512px JPEG (quality 82).
  Uint8List compressAvatar(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw ArgumentError('Unsupported image format');
    final resized = img.copyResizeCropSquare(decoded, size: 512);
    return Uint8List.fromList(img.encodeJpg(resized, quality: 82));
  }

  /// Upload the compressed avatar and persist its public URL on the profile.
  Future<String> uploadAvatar(String accountId, Uint8List compressedJpg) async {
    final authUid = _client.auth.currentUser!.id;
    final path =
        '$authUid/$accountId-${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _client.storage.from('avatars').uploadBinary(
          path,
          compressedJpg,
          fileOptions:
              const FileOptions(contentType: 'image/jpeg', upsert: true),
        );
    final url = _client.storage.from('avatars').getPublicUrl(path);
    await _client
        .from('profiles')
        .update({'avatar_url': url})
        .eq('account_id', accountId);
    return url;
  }
}
