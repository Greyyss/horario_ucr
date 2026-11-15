import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../theme/ucr_colors.dart';
import '../models/declaration.dart';
import '../services/declaration_service.dart';
import '../services/validation_service.dart';
import '../services/personal_data_validator.dart';
import '../services/profile_service.dart';
import 'appointment_page.dart';
import 'declaration_observation_tools.dart';

class EditorPage extends StatefulWidget {
  final Declaration? existing;

  const EditorPage({super.key, this.existing});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  final service = DeclarationService();

  final fields = List.generate(8, (_) => TextEditingController());

  final jobs = <Appointment>[];
  final external = <Appointment>[];

  bool busy = false;
  bool _profileLoaded = false;

  String? _profileError;
  String _periodName = "";
  String _superiorName = "";

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
      fields[5].text = DeclarationObservationTools.generate(jobs, external);
    }
  }

  void _activitiesChanged() {
    _automaticObservations = true;
    _syncObservations();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _loadPersonalProfile({bool useCurrentProfile = false}) async {
    setState(() {
      _profileLoaded = false;
      _profileError = null;
    });

    try {
      final data = await ProfileService().load();

      if (!mounted) return;

      final periodId =
          widget.existing?.periodId ?? (data['periodId'] ?? '').toString();
      final superiorId =
          widget.existing?.superiorId ?? (data['superiorId'] ?? '').toString();
      final periodName = await _displayName('periods', periodId);
      final superiorName = await _displayName('users', superiorId);
      if (!mounted) return;

      setState(() {
        if (widget.existing == null || useCurrentProfile) {
          fields[0].text = (data['name'] ?? '').toString();
          fields[1].text = (data['identification'] ?? '').toString();
          fields[2].text = (data['phone'] ?? '').toString();
          fields[3].text = (data['email'] ?? '').toString();
          fields[4].text = (data['unit'] ?? '').toString();
        }

        fields[6].text = periodId;
        fields[7].text = superiorId;
        _periodName = periodName;
        _superiorName = superiorName;
        _profileLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _profileError =
            'No se pudo cargar tu perfil. Revisá tu conexión '
            'y volvé a intentarlo.';
      });
    }
  }

  Future<String> _displayName(String collection, String id) async {
    if (id.isEmpty) return 'Sin asignar';
    try {
      final data =
          (await FirebaseFirestore.instance
                  .collection(collection)
                  .doc(id)
                  .get())
              .data();
      return (data?['name'] ?? data?['label'] ?? 'Asignado').toString();
    } on FirebaseException {
      return 'Asignado';
    }
  }

  String? _validatePersonalField(int index, String? value) {
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
      _showMessage('Esperá a que se carguen tus datos personales.');
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

    fields[0].text = PersonalDataValidator.normalizeName(fields[0].text);

    for (final index in [1, 2, 3, 4, 5]) {
      fields[index].text = fields[index].text.trim();
    }

    for (var index = 0; index <= 5; index++) {
      final error = _validatePersonalField(index, fields[index].text);
      if (error != null) {
        _showMessage(error);
        return;
      }
    }
    if (fields[6].text.isEmpty || fields[7].text.isEmpty) {
      _showMessage('Falta asignar el período o el superior jerárquico.');
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
        throw StateError('El período indicado no está habilitado.');
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

  Widget _summary() {
    final values = [
      ('Nombre', fields[0].text),
      ('Cédula', fields[1].text),
      ('Correo', fields[3].text),
      ('Teléfono', fields[2].text),
      ('Unidad', fields[4].text),
      ('Período', _periodName),
      ('Superior', _superiorName),
    ];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFC5D5E6)),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(18),
      child: Wrap(
        spacing: 24,
        runSpacing: 12,
        alignment: WrapAlignment.spaceBetween,
        children: [
          for (final (label, value) in values)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(value.isEmpty ? '—' : value),
              ],
            ),
        ],
      ),
    );
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
          constraints: const BoxConstraints(maxWidth: 1360),
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              const Text(
                'Datos de la declaración',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF123663),
                ),
              ),
              const SizedBox(height: 20),
              if (!_profileLoaded && _profileError == null)
                const LinearProgressIndicator(),
              if (_profileError != null)
                TextButton(
                  onPressed: busy ? null : () => _loadPersonalProfile(),
                  child: Text('$_profileError Reintentar'),
                ),
              _summary(),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, constraints) {
                  final internalCard = _pendingAppointments();
                  final externalCard = section(
                    'Otras instituciones',
                    external,
                    true,
                  );
                  if (constraints.maxWidth < 640) {
                    return Column(children: [internalCard, externalCard]);
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: internalCard),
                      const SizedBox(width: 16),
                      Expanded(child: externalCard),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 12,
                runSpacing: 8,
                children: [
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
                  FilledButton.icon(
                    onPressed: busy || !_profileLoaded ? null : save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(busy ? 'Guardando...' : 'Guardar borrador'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  final _editedAssignments = <String, Appointment>{};

  Widget _pendingAppointments() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final period = fields[6].text.trim();
    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFC5D5E6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Nombramientos',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Divider(),
            if (uid != null && period.isNotEmpty)
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid)
                    .collection('pendingAppointments')
                    .where('periodId', isEqualTo: period)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Text(
                      'No se pudieron cargar los nombramientos.',
                    );
                  }
                  if (!snapshot.hasData) return const LinearProgressIndicator();
                  final docs = snapshot.data!.docs;
                  if (docs.isEmpty && jobs.isEmpty) {
                    return const Text('No tienes declaraciones pendientes');
                  }
                  return Column(
                    children: [
                      for (final doc in docs) _assignmentRow(doc),
                      for (final job in jobs)
                        if (!_editedAssignments.containsValue(job))
                          ListTile(
                            title: Text(job.position),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: busy ? null : () => _editAssigned(job),
                          ),
                    ],
                  );
                },
              )
            else if (!_profileLoaded && _profileError == null)
              const LinearProgressIndicator()
            else
              const Text('No tienes declaraciones pendientes'),
          ],
        ),
      ),
    );
  }

  Widget _assignmentRow(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final appointment = Appointment.fromMap(data);
    final edited = _editedAssignments[doc.id];
    return ListTile(
      title: Text(appointment.position),
      subtitle: Text(
        "${data['unit'] ?? fields[4].text} · "
        "${appointment.expectedHours} h semanales · $_periodName",
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(edited == null ? 'Pendiente' : 'En edición'),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: busy
          ? null
          : () => _editAssigned(edited ?? appointment, id: doc.id),
    );
  }

  Future<void> _editAssigned(Appointment appointment, {String? id}) async {
    final edited = await _openAppointment(
      isExternal: false,
      existing: appointment,
    );
    if (!mounted || edited == null) return;
    setState(() {
      final index = jobs.indexOf(appointment);
      if (index < 0) {
        jobs.add(edited);
      } else {
        jobs[index] = edited;
      }
      if (id != null) _editedAssignments[id] = edited;
      _activitiesChanged();
    });
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
          lockAssignment: !isExternal,
          otherAppointments: [
            for (final appointment in [...jobs, ...external])
              if (!identical(appointment, existing)) appointment,
          ],
          institutionalWorkplace: isExternal
              ? null
              : 'Universidad de Costa Rica',
        ),
      ),
    );
  }

  Widget section(String title, List<Appointment> list, bool isExternal) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFC5D5E6)),
      ),
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
                OutlinedButton.icon(
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
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 18, bottom: 12),
                child: Text(isExternal ? '' : 'No tienes nada por declarar'),
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
