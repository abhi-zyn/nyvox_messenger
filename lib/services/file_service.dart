import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Picks and prepares media/files on-device. Nothing leaves the device
/// unencrypted — the chat service encrypts bytes before upload.
class FileService {
  final _picker = ImagePicker();

  /// Pick a photo from the gallery, downscale + JPEG-compress it.
  Future<List<int>?> pickImage({int maxSide = 1280, int quality = 78}) async {
    final x = await _picker.pickImage(source: ImageSource.gallery);
    if (x == null) return null;
    final raw = await x.readAsBytes();
    final decoded = img.decodeImage(raw);
    if (decoded == null) return raw;
    final resized = decoded.width > decoded.height
        ? (decoded.width > maxSide
            ? img.copyResize(decoded, width: maxSide)
            : decoded)
        : (decoded.height > maxSide
            ? img.copyResize(decoded, height: maxSide)
            : decoded);
    return img.encodeJpg(resized, quality: quality);
  }

  /// Pick any file (PDF, document, audio, video…) with its bytes in memory.
  Future<({List<int> bytes, String name, int size})?> pickFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    final f = result?.files.firstOrNull;
    if (f == null || f.bytes == null) return null;
    return (bytes: f.bytes!, name: f.name, size: f.size);
  }

  /// Write bytes to a temporary file and return its path (for viewing or
  /// sharing). The caller is responsible for deleting it.
  Future<String> writeTempFile(String name, List<int> bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> deleteTempFile(String path) async {
    try {
      await File(path).delete();
    } catch (_) {}
  }
}
