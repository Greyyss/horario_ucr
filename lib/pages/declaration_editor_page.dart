import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/ucr_colors.dart';
import '../models/declaration.dart';
import '../services/declaration_service.dart';
import '../services/validation_service.dart';
import '../services/personal_data_validator.dart';
import '../services/profile_service.dart';
import 'personal_profile_page.dart';
import 'superior_selector.dart';
import 'appointment_page.dart';
import 'declaration_observation_tools.dart';

class EditorPage extends StatefulWidget {
  final Declaration? existing;

  const EditorPage({
    super.key,
    this.existing,
  });

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  final service = DeclarationService();

  final fields = List.generate(
    8,
    (_) => TextEditingController(),
  );

  final _formKey = GlobalKey<FormState>();

  final jobs = <Appointment>[];
  final external = <Appointment>[];

  bool busy = false;
  bool _profileLoaded = false;

  String? _profileError;

  // Los documentos anteriores conservan sus observaciones
  // hasta que se modifiquen los horarios o se solicite regenerarlas.
  bool _automaticObservations = false;

  @override
  void initState() {
    super.initState();

    final d = widget.existing;

    _automaticObservations = d == null;

    if (d != null) {
      for (final pair in <(int, String)>[
        (0, d.ownerName),
        (1, d.identification),
        (2, d.phone),
        (3, d.email),
        (4, d.unit),
        (5, d.observations),
        (6, d.periodId),
        (7, d.superiorId),
      ]) {
        fields[pair.$1].text = pair.$2;
      }

      jobs.addAll(d.appointments);
      external.addAll(d.externalJobs);
    }

    _syncObservations();
    _loadPersonalProfile();
  }

  @override
  void dispose() {
    for (final controller in fields) {
      controller.dispose();
    }

    super.dispose();
  }

  void _syncObservations() {
    if (_automaticObservations) {
      fields[5].text = DeclarationObservationTools.generate(
        jobs,
        external,
      );
    }
  }

  void _activitiesChanged() {
    _automaticObservations = true;
    _syncObservations();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _loadPersonalProfile({
    bool useCurrentProfile = false,
  }) async {
    setState(() {
      _profileLoaded = false;
      _profileError = null;
    });

    try {
      final data = await ProfileService().load();

      if (!mounted) return;

      setState(() {
        if (widget.existing == null || useCurrentProfile) {
          fields[0].text = (data['name'] ?? '').toString();
          fields[1].text = (data['identification'] ?? '').toString();
          fields[2].text = (data['phone'] ?? '').toString();
          fields[3].text = (data['email'] ?? '').toString();
          fields[4].text = (data['unit'] ?? '').toString();
        }

        _profileLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _profileError = 'No se pudo cargar tu perfil. Revisá tu conexión '
            'y volvé a intentarlo.';
      });
    }
  }

  Future<void> _editPersonalProfile() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => const PersonalProfilePage(),
      ),
    );

    if (!mounted) return;

    await _loadPersonalProfile(
      useCurrentProfile: true,
    );
  }

  String? _validatePersonalField(
    int index,
    String? value,
  ) {
    switch (index) {
      case 0:
        return PersonalDataValidator.name(value);
      case 1:
        return PersonalDataValidator.identification(value);
      case 2:
        return PersonalDataValidator.phone(value);
      case 3:
        return PersonalDataValidator.email(value);
      case 4:
        return PersonalDataValidator.unit(value);
      case 5:
        return PersonalDataValidator.observations(value);
      default:
        return null;
    }
  }

  Future<void> save() async {
    if (busy) return;

    if (!_profileLoaded) {
      _showMessage(
        'Esperá a que se carguen tus datos personales.',
      );
      return;
    }

    if (_automaticObservations) {
      final activityError = DeclarationObservationTools.firstError(jobs);

      if (activityError != null) {
        _showMessage(activityError);
        return;
      }

      _syncObservations();
    }

    fields[0].text = PersonalDataValidator.normalizeName(
      fields[0].text,
    );

    for (final index in [1, 2, 3, 4, 5]) {
      fields[index].text = fields[index].text.trim();
    }

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() => busy = true);

    try {
      final currentProfile = await ProfileService().load();

      if (!mounted) return;

      final registeredId = (currentProfile['identification'] ?? '').toString();

      if (registeredId.isEmpty) {
        throw StateError(
          'Primero registrá y guardá tu cédula '
          'en Mis datos personales.',
        );
      }

      if (fields[1].text != registeredId) {
        throw StateError(
          'La cédula de la declaración no coincide con tu perfil. '
          'Revisá tus datos antes de continuar.',
        );
      }

      final p = await FirebaseFirestore.instance
          .collection('periods')
          .doc(fields[6].text.trim())
          .get();

      if (!mounted) return;

      if (!p.exists || p.data()?['enabled'] != true) {
        throw StateError(
          'El período indicado no está habilitado.',
        );
      }

      if (fields[0].text.trim().isEmpty ||
          fields[1].text.trim().isEmpty ||
          fields[7].text.trim().isEmpty ||
          jobs.isEmpty) {
        throw StateError(
          'Completá los datos, seleccioná tu superior '
          'y agregá al menos un nombramiento.',
        );
      }

      final d = Declaration(
        id: widget.existing?.id ?? '',
        ownerId: FirebaseAuth.instance.currentUser!.uid,
        ownerName: fields[0].text.trim(),
        identification: fields[1].text.trim(),
        phone: fields[2].text.trim(),
        email: fields[3].text.trim(),
        unit: fields[4].text.trim(),
        periodId: fields[6].text.trim(),
        superiorId: fields[7].text.trim(),
        status: 'BORRADOR',
        observations: fields[5].text.trim(),
        version: widget.existing?.version ?? 1,
        appointments: List.of(jobs),
        externalJobs: List.of(external),
        updatedAt: DateTime.now(),
      );

      await service.save(d);

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        _showMessage('$e');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  InputDecoration _fieldStyle(
    String label,
    IconData icon,
  ) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: UcrColors.blue),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 17,
      ),
    );
  }

  Widget _input(
    int index,
    String label,
    IconData icon, {
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: fields[index],
      readOnly: index >= 0 && index <= 4,
      maxLines: maxLines,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (value) => _validatePersonalField(index, value),
      keyboardType: index == 1
          ? TextInputType.number
          : index == 2
              ? TextInputType.phone
              : index == 3
                  ? TextInputType.emailAddress
                  : TextInputType.text,
      decoration: _fieldStyle(
        label,
        icon,
      ).copyWith(errorMaxLines: 3),
    );
  }

  Widget _pair(Widget first, Widget second) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 580) {
          return Column(
            children: [
              first,
              const SizedBox(height: 14),
              second,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: first),
            const SizedBox(width: 14),
            Expanded(child: second),
          ],
        );
      },
    );
  }

  Widget _heading(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, color: UcrColors.blue, size: 23),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF123663),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _panel(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F9FE),
        border: Border.all(
          color: const Color(0xFFD7E8F7),
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _periodDropdown() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('periods')
          .where('enabled', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text(
            'No se pudieron consultar los períodos: '
            '${snapshot.error}',
            style: const TextStyle(color: Colors.red),
          );
        }

        if (!snapshot.hasData) {
          return const LinearProgressIndicator();
        }

        final docs = snapshot.data!.docs;
        final current = fields[6].text.trim();

        final available = docs.any(
          (doc) => doc.id == current,
        );

        final items = <DropdownMenuItem<String>>[
          if (current.isNotEmpty && !available)
            DropdownMenuItem<String>(
              value: current,
              child: Text(
                '$current (período anterior)',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          for (final doc in docs)
            DropdownMenuItem<String>(
              value: doc.id,
              child: Text(
                (doc.data()['name'] ?? doc.data()['label'] ?? doc.id)
                    .toString(),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ];

        if (items.isEmpty) {
          return const Text(
            'No hay períodos activos disponibles.',
          );
        }

        return DropdownButtonFormField<String>(
          key: ValueKey('period-$current'),
          initialValue: current.isEmpty ? null : current,
          isExpanded: true,
          decoration: _fieldStyle(
            'Período activo',
            Icons.event_available_outlined,
          ),
          hint: const Text('Seleccioná un período'),
          items: items,
          onChanged: widget.existing != null || busy
              ? null
              : (value) {
                  setState(
                    () => fields[6].text = value ?? '',
                  );
                },
        );
      },
    );
  }

  Widget _observationsPanel() {
    final error =
        _automaticObservations ? DeclarationObservationTools.firstError(jobs) : null;

    return _panel([
      _heading(
        'Observaciones de la declaración',
        Icons.notes_outlined,
      ),
      Text(
        _automaticObservations
            ? 'El resumen se genera a partir de los cursos, '
                'actividades y horarios declarados.'
            : 'Se conservan las observaciones del borrador anterior. '
                'Al modificar sus horarios, el resumen se generará '
                'automáticamente.',
      ),
      if (!_automaticObservations)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: busy
                ? null
                : () {
                    setState(_activitiesChanged);
                  },
            icon: const Icon(Icons.auto_awesome_outlined),
            label: const Text('Generar desde los horarios'),
          ),
        ),
      const SizedBox(height: 12),
      TextFormField(
        controller: fields[5],
        readOnly: true,
        minLines: 4,
        maxLines: 12,
        validator: PersonalDataValidator.observations,
        decoration: _fieldStyle(
          'Resumen de horarios',
          Icons.description_outlined,
        ).copyWith(
          hintText: 'Agregá nombramientos para generar el resumen.',
          errorMaxLines: 3,
        ),
      ),
      if (error != null) ...[
        const SizedBox(height: 10),
        Text(
          error,
          style: const TextStyle(
            color: Colors.deepOrange,
          ),
        ),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UcrColors.background,
      appBar: AppBar(
        backgroundColor: UcrColors.blue,
        foregroundColor: Colors.white,
        title: Text(
          widget.existing == null ? 'Nueva declaración' : 'Editar declaración',
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(22),
              children: [
                const Text(
                  'Datos de la declaración',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF123663),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Completá la información y agregá tus horarios.',
                  style: TextStyle(
                    color: Color(0xFF55749A),
                  ),
                ),
                const SizedBox(height: 22),
                _panel([
                  _heading(
                    'Información personal',
                    Icons.person_outline,
                  ),
                  if (!_profileLoaded && _profileError == null)
                    const LinearProgressIndicator(),
                  if (_profileError != null) ...[
                    Text(
                      _profileError!,
                      style: const TextStyle(
                        color: Colors.red,
                      ),
                    ),
                    TextButton(
                      onPressed: busy ? null : () => _loadPersonalProfile(),
                      child: const Text(
                        'Reintentar carga del perfil',
                      ),
                    ),
                  ],
                  const Text(
                    'Los datos se completan desde tu perfil. '
                    'Podés actualizarlos allí; la cédula '
                    'guardada no se puede cambiar.',
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed:
                          busy || !_profileLoaded ? null : _editPersonalProfile,
                      icon: const Icon(
                        Icons.manage_accounts_outlined,
                      ),
                      label: Text(
                        widget.existing == null
                            ? 'Completar o editar mis datos'
                            : 'Editar perfil y usar sus datos actuales',
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _pair(
                    _input(
                      0,
                      'Nombre completo',
                      Icons.person_outline,
                    ),
                    _input(
                      1,
                      'Identificación',
                      Icons.credit_card_outlined,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _pair(
                    _input(
                      3,
                      'Correo electrónico',
                      Icons.mail_outline,
                    ),
                    _input(
                      2,
                      'Teléfono',
                      Icons.phone_outlined,
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                _panel([
                  _heading(
                    'Información institucional',
                    Icons.account_balance_outlined,
                  ),
                  _input(
                    4,
                    'Unidad académica o administrativa',
                    Icons.apartment_outlined,
                  ),
                  const SizedBox(height: 14),
                  _pair(
                    _periodDropdown(),
                    SuperiorSelector(
                      controller: fields[7],
                      enabled: widget.existing == null && !busy,
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                section(
                  'Nombramientos',
                  jobs,
                  false,
                ),
                const SizedBox(height: 12),
                section(
                  'Otras instituciones',
                  external,
                  true,
                ),
                const SizedBox(height: 16),
                _observationsPanel(),
                const SizedBox(height: 12),
                Builder(
                  builder: (ctx) {
                    final result = ValidationService.validate(
                      jobs,
                      external,
                    );

                    return Card(
                      elevation: 0,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Horas institucionales: '
                              '${result.institutionalHours.toStringAsFixed(2)} / '
                              '${result.expectedHours.toStringAsFixed(2)} '
                              'esperadas',
                            ),
                            Text(
                              'Horas externas: '
                              '${result.externalHours.toStringAsFixed(2)}',
                            ),
                            ...result.errors.map(
                              (e) => Text(
                                '• $e',
                                style: const TextStyle(
                                  color: Colors.deepOrange,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          final resultado = ValidationService.validate(
                            jobs,
                            external,
                          );

                          await showDialog<void>(
                            context: context,
                            builder: (dialogContext) => AlertDialog(
                              title: Text(
                                resultado.valid
                                    ? 'Horario sin errores'
                                    : 'Revisá el horario',
                              ),
                              content: SingleChildScrollView(
                                child: Text(
                                  resultado.valid
                                      ? 'Podés continuar y guardar el borrador.'
                                      : resultado.errors.join('\n\n'),
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(dialogContext).pop(),
                                  child: Text(
                                    resultado.valid
                                        ? 'Continuar'
                                        : 'Volver a editar',
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                  icon: const Icon(Icons.rule),
                  label: const Text('Revisar horario'),
                ),
                const SizedBox(height: 8),

                FilledButton.icon(
                  onPressed: busy || !_profileLoaded ? null : save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(
                    busy ? 'Guardando...' : 'Guardar borrador',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<Appointment?> _openAppointment({
    required bool isExternal,
    Appointment? existing,
  }) {
    return Navigator.push<Appointment>(
      context,
      MaterialPageRoute(
        builder: (_) => AppointmentPage(
          existing: existing,
          institutionalWorkplace:
              isExternal ? null : 'Universidad de Costa Rica',
        ),
      ),
    );
  }

  Widget section(
    String title,
    List<Appointment> list,
    bool isExternal,
  ) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: busy
                      ? null
                      : () async {
                          final appointment = await _openAppointment(
                            isExternal: isExternal,
                          );

                          if (appointment != null && mounted) {
                            setState(() {
                              list.add(appointment);
                              _activitiesChanged();
                            });
                          }
                        },
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar'),
                ),
              ],
            ),
            for (var i = 0; i < list.length; i++)
              ListTile(
                title: Text(list[i].workplace),
                subtitle: Text(
                  '${list[i].position} · '
                  '${list[i].blocks.length} bloques',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Editar',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: busy
                          ? null
                          : () async {
                              final index = i;
                              final original = list[index];

                              final edited = await _openAppointment(
                                isExternal: isExternal,
                                existing: original,
                              );

                              if (edited != null &&
                                  mounted &&
                                  index < list.length &&
                                  identical(list[index], original)) {
                                setState(() {
                                  list[index] = edited;
                                  _activitiesChanged();
                                });
                              }
                            },
                    ),
                    IconButton(
                      tooltip: 'Eliminar',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: busy
                          ? null
                          : () {
                              setState(() {
                                list.removeAt(i);
                                _activitiesChanged();
                              });
                            },
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// FORMULARIO DE NOMBRAMIENTOS Y BLOQUES
// ============================================================

