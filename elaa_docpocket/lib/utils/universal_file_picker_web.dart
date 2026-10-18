// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:async';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

Future<PlatformFile?> pickFileImpl({
  List<String>? allowedExtensions,
  String? dialogTitle,
}) async {
  try {
    final uploadInput = html.FileUploadInputElement();
    if (allowedExtensions != null && allowedExtensions.isNotEmpty) {
      uploadInput.accept = allowedExtensions.map((e) => '.$e').join(',');
    }
    uploadInput.click();

    // Attendre la sélection de l'utilisateur
    await uploadInput.onChange.first;
    if (uploadInput.files == null || uploadInput.files!.isEmpty) {
      return null;
    }

    final file = uploadInput.files!.first;
    final reader = html.FileReader();
    final completer = Completer<Uint8List>();

    reader.onLoadEnd.listen((_) {
      final res = reader.result;
      if (res is Uint8List) {
        completer.complete(res);
      } else if (res is ByteBuffer) {
        completer.complete(res.asUint8List());
      } else if (res is List<int>) {
        completer.complete(Uint8List.fromList(res));
      } else {
        completer.complete(Uint8List(0));
      }
    });

    reader.onError.listen((err) {
      completer.completeError(err);
    });

    reader.readAsArrayBuffer(file);
    final bytes = await completer.future;

    return PlatformFile(
      name: file.name,
      size: file.size,
      bytes: bytes,
    );
  } catch (e) {
    // Si l'API DOM échoue exceptionnellement, tentative de repli
    try {
      final result = await FilePicker.platform.pickFiles(
        type: allowedExtensions != null && allowedExtensions.isNotEmpty
            ? FileType.custom
            : FileType.any,
        allowedExtensions: allowedExtensions,
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        return result.files.first;
      }
    } catch (_) {}
    rethrow;
  }
}
