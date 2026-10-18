import 'package:file_picker/file_picker.dart';
export 'package:file_picker/file_picker.dart' show PlatformFile;

import 'universal_file_picker_stub.dart'
    if (dart.library.html) 'universal_file_picker_web.dart'
    if (dart.library.io) 'universal_file_picker_io.dart';

Future<PlatformFile?> pickSingleFile({
  List<String>? allowedExtensions,
  String? dialogTitle,
}) {
  return pickFileImpl(
    allowedExtensions: allowedExtensions,
    dialogTitle: dialogTitle,
  );
}
