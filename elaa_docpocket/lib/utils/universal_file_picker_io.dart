import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

Future<PlatformFile?> pickFileImpl({
  List<String>? allowedExtensions,
  String? dialogTitle,
}) async {
  FilePickerResult? result;
  try {
    result = await FilePicker.platform.pickFiles(
      type: allowedExtensions != null && allowedExtensions.isNotEmpty
          ? FileType.custom
          : FileType.any,
      allowedExtensions: allowedExtensions,
      withData: true,
      dialogTitle: dialogTitle,
    );
  } catch (_) {
    result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
      dialogTitle: dialogTitle,
    );
  }

  if (result != null && result.files.isNotEmpty) {
    final file = result.files.first;
    Uint8List? bytes = file.bytes;
    if (bytes == null && file.path != null && File(file.path!).existsSync()) {
      try {
        bytes = await File(file.path!).readAsBytes();
        return PlatformFile(
          name: file.name,
          size: file.size,
          path: file.path,
          bytes: bytes,
        );
      } catch (_) {}
    }
    return file;
  }
  return null;
}
