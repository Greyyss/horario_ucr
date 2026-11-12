import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'personal_data_validator.dart';

class ProfileService {
  DocumentReference<Map<String, dynamic>> _reference() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Iniciá sesión para consultar tus datos.');
    }
    return FirebaseFirestore.instance.collection('users').doc(user.uid);
  }

  Future<Map<String, dynamic>> load() async {
    // No presentar una cédula como editable por usar una copia local antigua.
    final snapshot = await _reference().get(
      const GetOptions(source: Source.server),
    );
    final data = snapshot.data();
    if (data == null) {
      throw StateError('No se encontró tu perfil. Contactá al administrador.');
    }
    return data;
  }

  Future<void> save({
    required String name,
    required String identification,
    required String phone,
    required String email,
    required String unit,
  }) async {
    final values = <String, String>{
      'name': PersonalDataValidator.normalizeName(name),
      'identification': identification.trim(),
      'phone': phone.trim(),
      'email': email.trim(),
      'unit': unit.trim(),
    };
    final reference = _reference();
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      final current = snapshot.data();
      if (current == null) {
        throw StateError(
          'No se encontró tu perfil. Contactá al administrador.',
        );
      }
      final fromPadron = current['identitySource'] == 'padron';
      final errors = <String?>[
        if (!fromPadron) PersonalDataValidator.name(values['name']),
        if (!fromPadron)
          PersonalDataValidator.identification(values['identification']),
        PersonalDataValidator.phone(values['phone']),
        PersonalDataValidator.email(values['email']),
        PersonalDataValidator.unit(values['unit']),
      ].whereType<String>().toList();
      if (errors.isNotEmpty) throw StateError(errors.join('\n'));

      final previousId = (current['identification'] ?? '').toString();
      if (!fromPadron &&
          previousId.isNotEmpty &&
          previousId != values['identification']) {
        throw StateError(
          'La cédula ya está registrada y no se puede cambiar. '
          'Volvé a abrir tus datos personales.',
        );
      }
      // La transacción vuelve a leer el perfil si otra pestaña lo modifica.
      // Las reglas de Firestore también hacen cumplir la inmutabilidad.
      transaction.update(reference, {
        if (!fromPadron) 'name': values['name']!,
        if (!fromPadron) 'identification': values['identification']!,
        'phone': values['phone']!,
        'email': values['email']!,
        'unit': values['unit']!,
      });
    });
  }
}
