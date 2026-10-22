import '../models/declaration.dart';

class PersonalDataValidator {
  static const letters =
      'A-Za-zÁÉÍÓÚÜÑáéíóúüñÀÈÌÒÙàèìòù'
      'ÂÊÎÔÛâêîôûÄËÏÖäëïöÇç';

  static final _namePattern = RegExp(
    "^[$letters]+(?:[-'’][$letters]+)*"
    "(?: [$letters]+(?:[-'’][$letters]+)*)+\$",
  );

  static final _emailPattern =
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static String normalizeName(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ');

  static String? name(String? value) {
    final text = value ?? '';
    if (text.length < 5 || text.length > 100) {
      return 'El nombre debe tener entre 5 y 100 caracteres.';
    }
    if (!_namePattern.hasMatch(text)) {
      return 'Ingresá nombre y apellido, usando letras y espacios.';
    }
    return null;
  }

  static String? identification(String? value) {
    return RegExp(r'^[0-9]{9}$').hasMatch(value ?? '')
        ? null
        : 'La cédula debe tener exactamente 9 dígitos.';
  }

  static String? phone(String? value) {
    return RegExp(r'^[0-9]{8}$').hasMatch(value ?? '')
        ? null
        : 'El teléfono debe tener exactamente 8 dígitos.';
  }

  static String? email(String? value) {
    final text = value ?? '';
    return text.length <= 254 && _emailPattern.hasMatch(text)
        ? null
        : 'Ingresá un correo electrónico válido.';
  }

  static String? unit(String? value) {
    final text = value ?? '';
    return text == text.trim() &&
            text.length >= 2 &&
            text.length <= 150 &&
            !RegExp(r'[\r\n\t]').hasMatch(text)
        ? null
        : 'La unidad debe tener entre 2 y 150 caracteres.';
  }

  static String? observations(String? value) {
    return (value ?? '').length <= 2000
        ? null
        : 'Las observaciones admiten hasta 2000 caracteres.';
  }

  static List<String> errors(Declaration declaration) {
    final results = <String?>[
      name(declaration.ownerName),
      identification(declaration.identification),
      phone(declaration.phone),
      email(declaration.email),
      unit(declaration.unit),
      observations(declaration.observations),
    ];
    return results.whereType<String>().toList();
  }

  static void ensureValid(Declaration declaration) {
    final messages = errors(declaration);
    if (messages.isNotEmpty) {
      throw StateError(messages.join('\n'));
    }
  }
}