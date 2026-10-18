// STUB for non-web platforms — remplace dart:html
// ignore_for_file: unused_element

/// Stub d'IFrameElement pour les plateformes non-web (Android, iOS, macOS natif).
/// Sur le web, c'est l'implémentation réelle de dart:html qui est utilisée.
class IFrameElement {
  String srcdoc = '';
  final _StyleStub style = _StyleStub();
  bool allowFullscreen = false;
}

class _StyleStub {
  String border = '';
  String width = '';
  String height = '';
}
