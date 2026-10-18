import 'package:file_picker/file_picker.dart';

Future<PlatformFile?> pickFileImpl({
  List<String>? allowedExtensions,
  String? dialogTitle,
}) async {
  final result = await FilePicker.platform.pickFiles(
    type: allowedExtensions != null && allowedExtensions.isNotEmpty
        ? FileType.custom
        : FileType.any,
    allowedExtensions: allowedExtensions,
    withData: true,
    dialogTitle: dialogTitle,
  );
  if (result != null && result.files.isNotEmpty) {
    return result.files.first;
  }
  return null;
}
