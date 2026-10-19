import 'package:flutter/services.dart';

/// Formate un nom : TOUT EN MAJUSCULES (ex: "BEN KHALIFA", "DUPONT")
String formatNom(String input) {
  return input.trim().toUpperCase();
}

/// Formate avec la première lettre en majuscule (ex: "Hamed", "Jean-Pierre", "Iberostar", "Mahdia")
String formatCapitalized(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return '';
  return trimmed.split(' ').map((word) {
    if (word.isEmpty) return '';
    if (word.contains('-')) {
      return word.split('-').map((sub) {
        if (sub.isEmpty) return '';
        return sub[0].toUpperCase() + (sub.length > 1 ? sub.substring(1).toLowerCase() : '');
      }).join('-');
    }
    return word[0].toUpperCase() + (word.length > 1 ? word.substring(1).toLowerCase() : '');
  }).join(' ');
}

/// TextInputFormatter pour forcer le texte en majuscules (Nom)
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

/// TextInputFormatter pour mettre la première lettre de chaque mot en majuscule (Prénom, Ville, Hôtel)
class CapitalizeWordsTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) {
      return newValue;
    }
    final text = newValue.text;
    final buffer = StringBuffer();
    bool capitalizeNext = true;
    for (int i = 0; i < text.length; i++) {
      final ch = text[i];
      if (ch == ' ' || ch == '-' || ch == "'") {
        buffer.write(ch);
        capitalizeNext = true;
      } else if (capitalizeNext) {
        buffer.write(ch.toUpperCase());
        capitalizeNext = false;
      } else {
        buffer.write(ch);
      }
    }
    return TextEditingValue(
      text: buffer.toString(),
      selection: newValue.selection,
    );
  }
}
