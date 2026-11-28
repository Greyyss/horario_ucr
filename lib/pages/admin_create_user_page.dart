import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import 'registrar_declarante_page.dart' show fondoRegistroUsuarios;

class AdminCreateUserPage extends StatefulWidget {
  const AdminCreateUserPage({super.key});

  @override
  State<AdminCreateUserPage> createState() => _AdminCreateUserPageState();
}

class _AdminCreateUserPageState extends State<AdminCreateUserPage> {
  static const _blue = Color(0xFF02408A);

  static const _roles = {
    'declarante': 'Declarante',
    'superior': 'Superior',
    'rrhh': 'Recursos Humanos',
    'admin': 'Administrador',
  };

  static const _units = [
    'Sede Rodrigo Facio',
    'Sede de Occidente',
    'Sede del Atlántico',
    'Sede de Guanacaste',
    'Sede del Caribe',
    'Sede del Pacífico',
    'Sede del Sur',
    'Sede Interuniversitaria de Alajuela',
    'Recinto de Tacares',
    'Recinto de Paraíso',
    'Recinto de Guápiles',
    'Recinto de Santa Cruz',
    'Recinto de Siquirres',
  ];

  final _form = GlobalKey<FormState>();
  final _id = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();

  late final _superiores = FirebaseFirestore.instance
      .collection('users')
      .where('role', isEqualTo: 'superior')
      .snapshots();

  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'us-east1');

  String _names = '';
  String _lastNames = '';
  String _role = 'declarante';
  String? _unit;
  String? _superior;
  String? _verifiedId;
  String? _lookupError;
  String? _error;
  String? _lastPayload;
  String? _operationId;

  int _lookupRevision = 0;
  bool _lookingUp = false;
  bool _saving = false;

  static final _idPattern = RegExp(r'^[0-9]{9}$');
  static final _phonePattern = RegExp(r'^[0-9]{8}$');
  static final _emailPattern = RegExp(r'^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$');

  @override
  void dispose() {
    _id.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _lookup(String value) async {
    final id = value.trim();
    final revision = ++_lookupRevision;
    final valid = _idPattern.hasMatch(id);

    setState(() {
      _names = '';
      _lastNames = '';
      _verifiedId = null;
      _lookupError = null;
      _lookingUp = valid;
    });

    if (!valid) return;

    try {
      final response = await _functions
          .httpsCallable('consultarPadronRegistro')
          .call({'cedula': id});

      if (!mounted || revision != _lookupRevision) return;

      final data = Map<String, dynamic>.from(response.data as Map);
      final names = (data['nombres'] ?? '').toString().trim();
      final lastNames = (data['apellidos'] ?? '').toString().trim();

      setState(() {
        _names = names;
        _lastNames = lastNames;
        _lookingUp = false;

        if (names.isEmpty || lastNames.isEmpty) {
          _lookupError = 'El padrón no devolvió el nombre completo.';
        } else {
          _verifiedId = id;
        }
      });
    } on FirebaseFunctionsException catch (error) {
      if (!mounted || revision != _lookupRevision) return;

      setState(() {
        _lookupError = error.message ?? 'No se pudo consultar el padrón.';
        _lookingUp = false;
      });
    } catch (_) {
      if (!mounted || revision != _lookupRevision) return;

      setState(() {
        _lookupError = 'No se pudo consultar el padrón. Intentá nuevamente.';
        _lookingUp = false;
      });
    }
  }

  Future<void> _create() async {
    if (_saving || _lookingUp) return;
    if (!_form.currentState!.validate()) return;
    if (_verifiedId != _id.text.trim()) return;

    final payload = <String, dynamic>{
      'cedula': _id.text.trim(),
      'correo': _email.text.trim().toLowerCase(),
      'telefono': _phone.text.trim(),
      'unidad': _unit,
      'rol': _role,
      'superiorId': _role == 'declarante' ? _superior : null,
    };

    final fingerprint = jsonEncode(payload);

    if (_lastPayload != fingerprint) {
      _lastPayload = fingerprint;
      _operationId = const Uuid().v4();
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    Map<String, dynamic>? created;

    try {
      final response = await _functions
          .httpsCallable(
        'adminCrearUsuario',
        options: HttpsCallableOptions(
          timeout: const Duration(seconds: 150),
        ),
      )
          .call({
        ...payload,
        'operationId': _operationId,
      });

      created = Map<String, dynamic>.from(response.data as Map);
    } on FirebaseFunctionsException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message ?? 'No se pudo crear el usuario.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'No se pudo confirmar la creación. Reintentá con los mismos datos.';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }

    if (!mounted || created == null) return;

    final name = created['nombre']?.toString() ?? 'Usuario';

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Usuario creado'),
        content: Text(
          '$name\n${payload['correo']}\n\n'
          'Para establecer su contraseña, la persona puede usar '
          '“Olvidé mi contraseña” en el inicio de sesión.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );

    if (mounted) Navigator.pop(context, true);
  }

  InputDecoration _decoration(String label) => InputDecoration(
        labelText: label,
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      );

  Widget _readOnly(String label, String value) => InputDecorator(
        isEmpty: value.isEmpty,
        decoration: _decoration(label),
        child: Text(value, overflow: TextOverflow.ellipsis),
      );

  double get _progress {
    final items = [
      _verifiedId == _id.text.trim() && _verifiedId != null,
      _email.text.trim().length <= 254 &&
          _emailPattern.hasMatch(_email.text.trim()),
      _phonePattern.hasMatch(_phone.text.trim()),
      _unit != null,
      if (_role == 'declarante') _superior != null,
    ];

    return items.where((done) => done).length / items.length;
  }

  Widget _superiorField() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _superiores,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text(
            'No se pudieron cargar los superiores. Volvé a abrir la pantalla.',
            style: TextStyle(color: Colors.red),
          );
        }

        if (!snapshot.hasData) {
          return const LinearProgressIndicator();
        }

        final users = snapshot.data!.docs.toList()
          ..sort(
            (a, b) =>
                (a.data()['name'] ?? '').toString().toLowerCase().compareTo(
                      (b.data()['name'] ?? '').toString().toLowerCase(),
                    ),
          );

        final selectedExists = users.any((user) => user.id == _superior);

        return DropdownButtonFormField<String>(
          key: ValueKey(selectedExists ? _superior : 'sin-superior'),
          initialValue: selectedExists ? _superior : null,
          isExpanded: true,
          decoration: _decoration('Superior asignado'),
          items: [
            for (final user in users)
              DropdownMenuItem(
                value: user.id,
                child: Text(
                  '${user.data()['name'] ?? 'Sin nombre'}'
                  ' · ${user.data()['email'] ?? ''}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: _saving || users.isEmpty
              ? null
              : (value) => setState(() => _superior = value),
          validator: (value) {
            if (users.isEmpty) {
              return 'Primero registrá una persona con rol Superior.';
            }

            if (value == null || !users.any((user) => user.id == value)) {
              return 'Seleccioná un superior.';
            }

            return null;
          },
        );
      },
    );
  }

  Widget _identityFields() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _id,
            enabled: !_saving,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(9),
            ],
            decoration: _decoration('Cédula').copyWith(
              errorText: _lookupError,
              suffixIcon: _lookingUp
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : _lookupError != null
                      ? IconButton(
                          tooltip: 'Reintentar consulta',
                          onPressed: _saving ? null : () => _lookup(_id.text),
                          icon: const Icon(Icons.refresh),
                        )
                      : null,
            ),
            onChanged: _lookup,
            validator: (value) => _idPattern.hasMatch(value ?? '')
                ? null
                : 'Ingresá nueve dígitos.',
          ),
          const SizedBox(height: 12),
          _readOnly('Nombres', _names),
          const SizedBox(height: 12),
          _readOnly('Apellidos', _lastNames),
        ],
      );

  Widget _detailFields() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _email,
            enabled: !_saving,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: _decoration('Correo electrónico'),
            onChanged: (_) => setState(() {}),
            validator: (value) {
              final email = (value ?? '').trim();

              return email.length <= 254 && _emailPattern.hasMatch(email)
                  ? null
                  : 'Ingresá un correo válido.';
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phone,
            enabled: !_saving,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(8),
            ],
            decoration: _decoration('Teléfono'),
            onChanged: (_) => setState(() {}),
            validator: (value) => _phonePattern.hasMatch((value ?? '').trim())
                ? null
                : 'Ingresá ocho dígitos.',
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _unit,
            isExpanded: true,
            decoration: _decoration('Unidad académica o administrativa'),
            items: [
              for (final unit in _units)
                DropdownMenuItem(
                  value: unit,
                  child: Text(unit, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged:
                _saving ? null : (value) => setState(() => _unit = value),
            validator: (value) =>
                value == null ? 'Seleccioná una sede o recinto.' : null,
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        backgroundColor: const Color(0xFFEAF4FC),
        appBar: AppBar(
          backgroundColor: _blue,
          foregroundColor: Colors.white,
          automaticallyImplyLeading: !_saving,
          title: const Text('Crear usuario'),
        ),
        body: fondoRegistroUsuarios(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: Card(
                  color: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: Color(0xFFD5E2EE)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Image.asset(
                              'assets/images/logo_declara_ucr.png',
                              height: 84,
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 380),
                              child: TweenAnimationBuilder<double>(
                                tween: Tween<double>(begin: 0, end: _progress),
                                duration: const Duration(milliseconds: 250),
                                builder: (_, value, __) =>
                                    LinearProgressIndicator(
                                  value: value,
                                  color: _blue,
                                  backgroundColor: const Color(0xFFD5E6F4),
                                  semanticsLabel: 'Progreso del registro',
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Datos del usuario',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _blue,
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 20),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              if (constraints.maxWidth < 580) {
                                return Column(
                                  children: [
                                    _identityFields(),
                                    const SizedBox(height: 12),
                                    _detailFields(),
                                  ],
                                );
                              }

                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: _identityFields()),
                                  const SizedBox(width: 20),
                                  Expanded(child: _detailFields()),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 20),
                          DropdownButtonFormField<String>(
                            initialValue: _role,
                            decoration: _decoration('Rol'),
                            items: [
                              for (final role in _roles.entries)
                                DropdownMenuItem(
                                  value: role.key,
                                  child: Text(role.value),
                                ),
                            ],
                            onChanged: _saving
                                ? null
                                : (value) {
                                    if (value == null) return;
                                    setState(() {
                                      _role = value;
                                      _superior = null;
                                    });
                                  },
                          ),
                          if (_role == 'declarante') ...[
                            const SizedBox(height: 12),
                            _superiorField(),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              _error!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ],
                          const SizedBox(height: 20),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: _blue,
                            ),
                            onPressed:
                                _saving || _lookingUp || _verifiedId == null
                                    ? null
                                    : _create,
                            child: _saving
                                ? const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                      SizedBox(width: 10),
                                      Text('Creando usuario…'),
                                    ],
                                  )
                                : const Text('Crear usuario'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
