import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../theme/ucr_colors.dart';
import '../models/declaration.dart';
import '../services/declaration_service.dart';
import '../services/validation_service.dart';
import '../services/personal_data_validator.dart';
import '../services/profile_service.dart';
import '../widgets/declaration_assignment_card.dart';
import '../widgets/declaration_personal_summary.dart';
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
  final fields = List.generate(8, (_) => TextEditingController());

  final jobs = <Appointment>[];
  final external = <Appointment>[];

  bool busy = false;
  bool _profileLoaded = false;
  bool _automaticObservations = false;

  String? _profileError;
  String _periodName = '';
  String _superiorName = '';

  @override
  void initState() {
    super.initState();

    final declaration = widget.existing;
    _automaticObservations = declaration == null;

    if (declaration != null) {
      for (final pair in <(int, String)>[
        (0, declaration.ownerName),
        (1, declaration.identification),
        (2, declaration.phone),
        (3, declaration.email),
        (4, declaration.unit),
        (5, declaration.observations),
        (6, declaration.periodId),
        (7, declaration.superiorId),
      ]) {
        fields[pair.$1].text = pair.$2;
      }

      jobs.addAll(declaration.appointments);
      external.addAll(declaration.externalJobs);
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
      fields[5].text =
          DeclarationObservationTools.generate(jobs, external);
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

      final periodId =
          widget.existing?.periodId ?? (data['periodId'] ?? '').toString();

      final superiorId = widget.existing?.superiorId ??
          (data['superiorId'] ?? '').toString();

      final periodName = await _displayName('periods', periodId);
      final superiorName = await _loadSuperiorName(superiorId, data);

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

  Future<String> _displayName(
    String collection,
    String id,
  ) async {
    if (id.isEmpty) return 'Sin asignar';

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(collection)
          .doc(id)
          .get();

      final data = snapshot.data();

      return (data?['name'] ?? data?['label'] ?? 'Asignado')
          .toString();
    } on FirebaseException {
      return 'Asignado';
    }
  }

  Future<String> _loadSuperiorName(
    String id,
    Map<String, dynamic> profile,
  ) async {
    if (id.isEmpty) return 'Sin asignar';

    final savedName =
        (profile['superiorName'] ?? '').toString().trim();

    if (profile['superiorId'] == id && savedName.isNotEmpty) {
      return savedName;
    }

    try {
      final result =
          await FirebaseFunctions.instanceFor(region: 'us-east1')
              .httpsCallable('listSuperiors')
              .call();

      final superiors = (result.data as Map)['superiors'] as List;

      for (final superior in superiors) {
        if (superior['uid'] == id) {
          return superior['name'].toString();
        }
      }
    } catch (_) {
      // No impide abrir el formulario si falta el nombre.
    }

    return 'Nombre no disponible';
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
      final activityError =
          DeclarationObservationTools.firstError(jobs);

      if (activityError != null) {
        _showMessage(activityError);
        return;
      }

      _syncObservations();
    }

    fields[0].text =
        PersonalDataValidator.normalizeName(fields[0].text);

    for (final index in [1, 2, 3, 4, 5]) {
      fields[index].text = fields[index].text.trim();
    }

    for (var index = 0; index <= 5; index++) {
      final error =
          _validatePersonalField(index, fields[index].text);

      if (error != null) {
        _showMessage(error);
        return;
      }
    }

    if (fields[6].text.isEmpty || fields[7].text.isEmpty) {
      _showMessage(
        'Falta asignar el período o el superior jerárquico.',
      );
      return;
    }

    setState(() => busy = true);

    try {
      final currentProfile = await ProfileService().load();
      if (!mounted) return;

      final registeredId =
          (currentProfile['identification'] ?? '').toString();

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

      final period = await FirebaseFirestore.instance
          .collection('periods')
          .doc(fields[6].text.trim())
          .get();

      if (!mounted) return;

      if (!period.exists || period.data()?['enabled'] != true) {
        throw StateError(
          'El período indicado no está habilitado.',
        );
      }

      if (fields[0].text.trim().isEmpty ||
          fields[1].text.trim().isEmpty ||
          fields[7].text.trim().isEmpty ||
          jobs.isEmpty) {
        throw StateError(
          'Completá los datos y agregá al menos un nombramiento.',
        );
      }

      final declaration = Declaration(
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

      await service.save(declaration);

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        _showMessage('$error');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Widget _summary() {
    return DeclarationPersonalSummary(
      name: fields[0].text,
      identification: fields[1].text,
      email: fields[3].text,
      unit: fields[4].text,
      superior: _superiorName,
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
          widget.existing == null
              ? 'Nueva declaración'
              : 'Editar declaración',
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
                  onPressed:
                      busy ? null : () => _loadPersonalProfile(),
                  child: Text('$_profileError Reintentar'),
                ),
              _summary(),
              const SizedBox(height: 20),
              _pendingAppointments(),
              if (external.any(
                (job) => job.relatedAssignmentId == null,
              )) ...[
                const SizedBox(height: 16),
                _legacyExternalInstitutions(),
              ],
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: busy ? null : _reviewSchedule,
                    icon: const Icon(Icons.rule),
                    label: const Text('Revisar horario'),
                  ),
                  FilledButton.icon(
                    onPressed:
                        busy || !_profileLoaded ? null : save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(
                      busy ? 'Guardando...' : 'Guardar borrador',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _reviewSchedule() async {
    final result = ValidationService.validate(jobs, external);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          result.valid
              ? 'Horario sin errores'
              : 'Revisá el horario',
        ),
        content: SingleChildScrollView(
          child: Text(
            result.valid
                ? 'Podés continuar y guardar el borrador.'
                : result.errors.join('\n\n'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              result.valid ? 'Continuar' : 'Volver a editar',
            ),
          ),
        ],
      ),
    );
  }

  Widget _pendingAppointments() {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return const Text(
        'Iniciá sesión para consultar tus nombramientos.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Nombramientos',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('pendingAppointments')
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Text(
                'No se pudieron cargar los nombramientos.',
              );
            }

            if (!snapshot.hasData) {
              return const LinearProgressIndicator();
            }

            final docs = snapshot.data!.docs.where((doc) {
              final claimed = doc.data()['declarationId'];

              return claimed == null ||
                  claimed == widget.existing?.id;
            }).toList();

            if (docs.isEmpty && jobs.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'No tienes declaraciones pendientes',
                ),
              );
            }

            return Column(
              children: [
                for (final doc in docs) _assignmentRow(doc),
                for (final job in jobs)
                  if (!docs.any(
                    (doc) => doc.id == job.assignmentId,
                  ))
                    _assignmentCard(
                      job,
                      period: _periodName.isEmpty
                          ? fields[6].text
                          : _periodName,
                      selected: true,
                      onEdit: () => _editAssigned(job),
                      onAddExternal: job.assignmentId == null
                          ? null
                          : () => _addExternalFor(job),
                    ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _assignmentRow(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();

    final source = Appointment.fromMap({
      ...data,
      'assignmentId': doc.id,
      'workloadFraction':
          data['workloadFraction'] ??
              _fractionFor(data['expectedHours']),
    });

    final matches =
        jobs.where((job) => job.assignmentId == doc.id);

    final edited = matches.isEmpty ? null : matches.first;
    final appointment = edited ?? source;

    return _assignmentCard(
      appointment,
      period:
          (data['periodName'] ?? data['periodId'] ?? '').toString(),
      selected: edited != null,
      onEdit: () =>
          _editAssignmentFromSource(appointment, data),
      onAddExternal: () =>
          _addExternalFor(appointment, source: data),
    );
  }

  Widget _assignmentCard(
    Appointment appointment, {
    required String period,
    required bool selected,
    required VoidCallback onEdit,
    VoidCallback? onAddExternal,
  }) {
    final associated = appointment.assignmentId == null
        ? <Appointment>[]
        : external
            .where(
              (job) =>
                  job.relatedAssignmentId ==
                  appointment.assignmentId,
            )
            .toList();

    return DeclarationAssignmentCard(
      appointment: appointment,
      period: period,
      selected: selected,
      externalJobs: associated,
      busy: busy || !_profileLoaded,
      onEdit: onEdit,
      onAddExternal: onAddExternal,
      onEditExternal: (job) => _editExternal(
        job,
        associatedAppointment: appointment,
      ),
      onRemoveExternal: _removeExternal,
    );
  }

  Widget _legacyExternalInstitutions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
          color: const Color(0xFFC5D5E6),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Instituciones de declaraciones anteriores',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          const Text(
            'Estos registros se conservan sin vincularlos '
            'automáticamente a un nombramiento.',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF53667B),
            ),
          ),
          for (final job in external.where(
            (job) => job.relatedAssignmentId == null,
          ))
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(job.workplace),
              subtitle: Text(job.position),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Editar institución',
                    onPressed:
                        busy ? null : () => _editExternal(job),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: 'Quitar institución',
                    onPressed:
                        busy ? null : () => _removeExternal(job),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String? _fractionFor(dynamic hours) {
    return const <num, String>{
      5: '1/8',
      10: '1/4',
      15: '3/8',
      20: '1/2',
      25: '5/8',
      30: '3/4',
      35: '7/8',
      40: '1 TC',
    }[hours];
  }

  bool _canUseSource(Map<String, dynamic> data) {
    if (!_profileLoaded) {
      _showMessage('Esperá a que se carguen tus datos.');
      return false;
    }

    final periodId = data['periodId']?.toString() ?? '';
    final superiorId = data['superiorId']?.toString() ?? '';

    if (periodId.isEmpty || superiorId.isEmpty) {
      _showMessage(
        'El nombramiento no tiene período o superior asignado.',
      );
      return false;
    }

    if ((widget.existing != null || jobs.isNotEmpty) &&
        (fields[6].text != periodId ||
            fields[7].text != superiorId)) {
      _showMessage(
        'Los nombramientos de otro período o superior '
        'se completan en una declaración separada.',
      );
      return false;
    }

    if ((widget.existing != null || jobs.isNotEmpty) &&
        (data['unit'] ?? fields[4].text).toString() !=
            fields[4].text) {
      _showMessage(
        'Los nombramientos de otra unidad '
        'se completan en una declaración separada.',
      );
      return false;
    }

    return true;
  }

  void _adoptSource(Map<String, dynamic> source) {
    fields[6].text = source['periodId'].toString();
    fields[7].text = source['superiorId'].toString();
    fields[4].text =
        (source['unit'] ?? fields[4].text).toString();

    _periodName =
        (source['periodName'] ?? source['periodId']).toString();

    final name =
        (source['superiorName'] ?? '').toString().trim();

    if (name.isNotEmpty) {
      _superiorName = name;
    }
  }

  Future<void> _editAssignmentFromSource(
    Appointment appointment,
    Map<String, dynamic> data,
  ) async {
    if (!_canUseSource(data)) return;
    await _editAssigned(appointment, source: data);
  }

  Future<void> _addExternalFor(
    Appointment appointment, {
    Map<String, dynamic>? source,
  }) async {
    if (source != null && !_canUseSource(source)) return;

    final id = appointment.assignmentId;

    if (id == null) {
      _showMessage(
        'Este nombramiento histórico no tiene '
        'una referencia de asignación.',
      );
      return;
    }

    final added = await _openAppointment(
      isExternal: true,
      relatedAssignmentId: id,
      associatedAppointment: appointment,
    );

    if (!mounted || added == null) return;

    setState(() {
      if (!jobs.any((job) => job.assignmentId == id)) {
        jobs.add(appointment);
      }

      if (source != null) {
        _adoptSource(source);
      }

      external.add(added);
      _activitiesChanged();
    });
  }

  Future<void> _editExternal(
    Appointment original, {
    Appointment? associatedAppointment,
  }) async {
    final index = external.indexOf(original);

    final edited = await _openAppointment(
      isExternal: true,
      existing: original,
      relatedAssignmentId: original.relatedAssignmentId,
      associatedAppointment: associatedAppointment,
    );

    if (!mounted ||
        edited == null ||
        index < 0 ||
        index >= external.length ||
        !identical(external[index], original)) {
      return;
    }

    setState(() {
      external[index] = edited;
      _activitiesChanged();
    });
  }

  void _removeExternal(Appointment original) {
    setState(() {
      external.remove(original);
      _activitiesChanged();
    });
  }

  Future<void> _editAssigned(
    Appointment appointment, {
    Map<String, dynamic>? source,
  }) async {
    final edited = await _openAppointment(
      isExternal: false,
      existing: appointment,
    );

    if (!mounted || edited == null) return;

    setState(() {
      final index = appointment.assignmentId == null
          ? jobs.indexOf(appointment)
          : jobs.indexWhere(
              (job) =>
                  job.assignmentId == appointment.assignmentId,
            );

      if (index < 0) {
        jobs.add(edited);
      } else {
        jobs[index] = edited;
      }

      if (source != null) {
        _adoptSource(source);
      }

      _activitiesChanged();
    });
  }

  Future<Appointment?> _openAppointment({
    required bool isExternal,
    Appointment? existing,
    String? relatedAssignmentId,
    Appointment? associatedAppointment,
  }) {
    final others = [
      for (final appointment in [...jobs, ...external])
        if (!identical(appointment, existing)) appointment,
    ];

    if (associatedAppointment != null &&
        !others.any(
          (job) =>
              job.assignmentId != null &&
              job.assignmentId ==
                  associatedAppointment.assignmentId,
        )) {
      others.add(associatedAppointment);
    }

    return Navigator.push<Appointment>(
      context,
      MaterialPageRoute(
        builder: (_) => AppointmentPage(
          existing: existing,
          lockAssignment: !isExternal,
          relatedAssignmentId: relatedAssignmentId,
          otherAppointments: others,
          institutionalWorkplace:
              isExternal ? null : 'Universidad de Costa Rica',
        ),
      ),
    );
  }
}