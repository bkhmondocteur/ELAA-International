export 'mail_launcher_stub.dart'
  if (dart.library.html) 'mail_launcher_web.dart'
  if (dart.library.io) 'mail_launcher_io.dart';
