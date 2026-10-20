import 'admin_page.dart';
import 'dart:convert';
import '../services/websocket_service.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/declaration.dart';
import '../services/declaration_service.dart';
import '../services/validation_service.dart';

const days = [
  '',
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado'
];

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});
  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  final service = DeclarationService();
  final webSocketService = WebSocketService();
  String role = 'declarante';
  Map<String, dynamic> profile = {};
  bool loading = true;
  @override
  void initState() {
    super.initState();
    load();
    connectWebSocket();
  }

  Future<void> connectWebSocket() async {
    try {
      await webSocketService.connect();

      if (!mounted) return;

      webSocketService.messages?.listen((message) {
        if (!mounted) return;

        try {
          final data = jsonDecode(message.toString());
          if (data is! Map<String, dynamic>) return;

          debugPrint('Mensaje WebSocket recibido: ${data['type']}');

          final type = data['type'];
          final text = data['message'];

          if (type == 'authenticated') {
            debugPrint('Firebase autenticó correctamente al usuario');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('WebSocket autenticado correctamente'),
              ),
            );
            return;
          }

          if (type == 'ready') {
            debugPrint('Sistema de notificaciones preparado');
            return;
          }

          if (type == 'notification') {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(text?.toString() ?? 'Nueva notificación'),
                duration: const Duration(seconds: 6),
                behavior: SnackBarBehavior.floating,
              ),
            );
            return;
          }

          debugPrint('Mensaje WebSocket recibido: $type');
        } catch (e) {
          debugPrint('Error al leer notificación: $e');
        }
      }, onError: (error) {
        debugPrint('Error en WebSocket: $error');
      });
    } catch (e) {
      debugPrint('Error al conectar WebSocket: $e');
    }
  }

  @override
  void dispose() {
    webSocketService.disconnect();
    super.dispose();
  }

  Future<void> load() async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(FirebaseAuth.instance.currentUser!.uid)
        .get();
    if (mounted)
      setState(() {
        profile = doc.data() ?? {};
        role = profile['role'] ?? 'declarante';
        loading = false;
      });
  }

  Future<void> act(Declaration d, String action,
      {String note = '', bool confirmed = false}) async {
    try {
      await service.transition(d, action, note: note, confirmed: confirmed);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Operación completada')));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> askReturn(Declaration d) async {
    final c = TextEditingController();
    final note = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Devolver declaración'),
                content: TextField(
                    controller: c,
                    maxLines: 3,
                    decoration:
                        const InputDecoration(labelText: 'Motivo obligatorio')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, c.text),
                      child: const Text('Devolver'))
                ]));
    if (note != null) await act(d, 'return', note: note);
  }

  Future<void> askSign(Declaration d) async {
    bool accepted = false;
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, setLocal) => AlertDialog(
                    title: const Text('Declaración bajo juramento'),
                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text(
                          'Declaro bajo juramento que la información registrada es verdadera y completa. Esta es una firma electrónica interna, no una firma digital certificada.'),
                      CheckboxListTile(
                          value: accepted,
                          onChanged: (v) =>
                              setLocal(() => accepted = v ?? false),
                          title: const Text('Confirmo expresamente'))
                    ]),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancelar')),
                      FilledButton(
                          onPressed:
                              accepted ? () => Navigator.pop(ctx, true) : null,
                          child: const Text('Firmar'))
                    ])));
    if (ok == true) await act(d, 'signOwner', confirmed: true);
  }

  Widget action(Declaration d, String key, String label,
          {bool enabled = true}) =>
      Padding(
          padding: const EdgeInsets.only(right: 6, bottom: 6),
          child: OutlinedButton(
              onPressed: enabled
                  ? () {
                      if (key == 'return') {
                        askReturn(d);
                      } else if (key == 'signOwner') {
                        askSign(d);
                      } else {
                        act(d, key);
                      }
                    }
                  : null,
              child: Text(label)));
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return Scaffold(
        appBar: AppBar(
            title: const Text('DeclaraHorario'),
            backgroundColor: Colors.white,
            actions: [
              if (role == 'admin')
  IconButton(
    tooltip: 'Administración',
    icon: const Icon(Icons.admin_panel_settings_outlined),
    onPressed: () {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const AdminPage(),
        ),
      );
    },
  ),
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child:
                      Center(child: Text('${profile['name'] ?? ''} · $role'))),
              IconButton(
                  tooltip: 'Cerrar sesión',
                  onPressed: () => FirebaseAuth.instance.signOut(),
                  icon: const Icon(Icons.logout))
            ]),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Panel de declaraciones',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              const Text(
                                  'Gestione sus trámites, firmas y seguimiento institucional.'),
                              const SizedBox(height: 18),
                              if (role == 'declarante')
                                Align(
                                    alignment: Alignment.centerLeft,
                                    child: FilledButton.icon(
                                        onPressed: () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                                builder: (_) =>
                                                    const EditorPage())),
                                        icon: const Icon(Icons.add),
                                        label:
                                            const Text('Nueva declaración'))),
                              const SizedBox(height: 16),
                              Expanded(
                                  child: StreamBuilder<List<Declaration>>(
                                      stream: role == 'declarante'
                                          ? service.watchMine()
                                          : (role == 'superior'
                                              ? service.watchAssigned()
                                              : service.watchAll()),
                                      builder: (ctx, s) {
                                        if (s.hasError)
                                          return Center(
                                              child: Text('Error: ${s.error}'));
                                        if (!s.hasData)
                                          return const Center(
                                              child:
                                                  CircularProgressIndicator());
                                        final list = s.data!
                                            .where((d) =>
                                                role == 'admin' ||
                                                role == 'rrhh' ||
                                                role == 'declarante' ||
                                                d.superiorId == uid)
                                            .toList();
                                        if (list.isEmpty)
                                          return const Center(
                                              child: Text(
                                                  'No hay declaraciones disponibles.'));
                                        return ListView.builder(
                                            itemCount: list.length,
                                            itemBuilder: (ctx, i) {
                                              final d = list[i];
                                              return Card(
                                                  elevation: 0,
                                                  margin: const EdgeInsets.only(
                                                      bottom: 12),
                                                  child: Padding(
                                                      padding:
                                                          const EdgeInsets.all(
                                                              16),
                                                      child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Wrap(
                                                                spacing: 12,
                                                                runSpacing: 8,
                                                                children: [
                                                                  Text(d.ownerName,
                                                                      style: const TextStyle(
                                                                          fontWeight: FontWeight
                                                                              .bold,
                                                                          fontSize:
                                                                              18)),
                                                                  Chip(
                                                                      label: Text(d
                                                                          .status
                                                                          .replaceAll(
                                                                              '_',
                                                                              ' '))),
                                                                  Text(
                                                                      'Versión ${d.version} · ${d.unit}')
                                                                ]),
                                                            const SizedBox(
                                                                height: 8),
                                                            Text(
                                                                'Período: ${d.periodId} · Actualización: ${d.updatedAt.toLocal()}'),
                                                            const SizedBox(
                                                                height: 12),
                                                            Wrap(children: [
                                                              if (role ==
                                                                      'declarante' &&
                                                                  d.status ==
                                                                      'BORRADOR') ...[
                                                                action(
                                                                    d,
                                                                    'validate',
                                                                    'Validar'),
                                                                TextButton(
                                                                    onPressed: () => Navigator.push(
                                                                        context,
                                                                        MaterialPageRoute(
                                                                            builder: (_) => EditorPage(
                                                                                existing:
                                                                                    d))),
                                                                    child: const Text(
                                                                        'Editar'))
                                                              ],
                                                              if (role ==
                                                                      'declarante' &&
                                                                  d.status ==
                                                                      'VALIDADA')
                                                                action(
                                                                    d,
                                                                    'submit',
                                                                    'Enviar a firma'),
                                                              if (role ==
                                                                      'declarante' &&
                                                                  d.status ==
                                                                      'PENDIENTE_FIRMA_DECLARANTE')
                                                                action(
                                                                    d,
                                                                    'signOwner',
                                                                    'Firmar bajo juramento'),
                                                              if (role ==
                                                                      'declarante' &&
                                                                  d.status ==
                                                                      'FIRMADA_POR_DECLARANTE')
                                                                action(
                                                                    d,
                                                                    'route',
                                                                    'Remitir al superior'),
                                                              if (role ==
                                                                      'declarante' &&
                                                                  d.status ==
                                                                      'DEVUELTA')
                                                                action(
                                                                    d,
                                                                    'newVersion',
                                                                    'Crear nueva versión'),
                                                              if ((role ==
                                                                          'superior' ||
                                                                      role ==
                                                                          'admin') &&
                                                                  d.superiorId ==
                                                                      uid &&
                                                                  d.status ==
                                                                      'PENDIENTE_FIRMA_SUPERIOR') ...[
                                                                action(
                                                                    d,
                                                                    'signSuperior',
                                                                    'Aprobar y firmar'),
                                                                action(
                                                                    d,
                                                                    'return',
                                                                    'Devolver')
                                                              ],
                                                              if ((role ==
                                                                          'rrhh' ||
                                                                      role ==
                                                                          'admin') &&
                                                                  d.status ==
                                                                      'FIRMADA_POR_SUPERIOR')
                                                                action(
                                                                    d,
                                                                    'sendHr',
                                                                    'Enviar a RRHH'),
                                                              if ((role ==
                                                                          'rrhh' ||
                                                                      role ==
                                                                          'admin') &&
                                                                  d.status ==
                                                                      'ENVIADA_A_RRHH')
                                                                action(
                                                                    d,
                                                                    'receive',
                                                                    'Recibir'),
                                                              if ((role ==
                                                                          'rrhh' ||
                                                                      role ==
                                                                          'admin') &&
                                                                  d.status ==
                                                                      'RECIBIDA_RRHH')
                                                                action(
                                                                    d,
                                                                    'finish',
                                                                    'Finalizar'),
                                                              OutlinedButton(
                                                                  onPressed: () => Navigator.push(
                                                                      context,
                                                                      MaterialPageRoute(
                                                                          builder: (_) => TimelinePage(
                                                                              id: d
                                                                                  .id))),
                                                                  child: const Text(
                                                                      'Historial')),
                                                              OutlinedButton(
                                                                  onPressed: () =>
                                                                      service
                                                                          .generatePdf(
                                                                              d),
                                                                  child:
                                                                      const Text(
                                                                          'PDF'))
                                                            ])
                                                          ])));
                                            });
                                      }))
                            ])))));
  }
}

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
  String period = '';
  String superior = '';
  @override
  void initState() {
    super.initState();
    final d = widget.existing;
    if (d != null) {
      for (final pair in <(int, String)>[
        (0, d.ownerName),
        (1, d.identification),
        (2, d.phone),
        (3, d.email),
        (4, d.unit),
        (5, d.observations),
        (6, d.periodId),
        (7, d.superiorId)
      ]) {
        fields[pair.$1].text = pair.$2;
      }
      jobs.addAll(d.appointments);
      external.addAll(d.externalJobs);
    } else {
      final u = FirebaseAuth.instance.currentUser!;
      fields[0].text = u.displayName ?? '';
      fields[3].text = u.email ?? '';
      FirebaseFirestore.instance
          .collection('users')
          .doc(u.uid)
          .get()
          .then((doc) {
        if (mounted)
          setState(() {
            fields[1].text = doc.data()?['identification'] ?? '';
            fields[2].text = doc.data()?['phone'] ?? '';
            fields[4].text = doc.data()?['unit'] ?? '';
          });
      });
    }
  }

  Future<void> save() async {
    setState(() => busy = true);
    try {
      final p = await FirebaseFirestore.instance
          .collection('periods')
          .doc(fields[6].text.trim())
          .get();
      if (!p.exists || p.data()?['enabled'] != true)
        throw StateError('El período indicado no está habilitado.');
      if (fields[0].text.trim().isEmpty ||
          fields[1].text.trim().isEmpty ||
          fields[7].text.trim().isEmpty ||
          jobs.isEmpty)
        throw StateError(
            'Complete los datos, el superior UID y al menos un nombramiento.');
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
          appointments: jobs,
          externalJobs: external,
          updatedAt: DateTime.now());
      await service.save(d);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    for (final controller in fields) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const labels = [
      'Nombre completo',
      'Identificación',
      'Teléfono',
      'Correo',
      'Unidad académica o administrativa',
      'Observaciones',
      'ID del período activo',
      'UID del superior jerárquico'
    ];
    return Scaffold(
        appBar: AppBar(
            title: Text(widget.existing == null
                ? 'Nueva declaración'
                : 'Editar declaración')),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 850),
                child: ListView(padding: const EdgeInsets.all(22), children: [
                  Card(
                      elevation: 0,
                      child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Información general',
                                    style:
                                        Theme.of(context).textTheme.titleLarge),
                                const SizedBox(height: 12),
                                for (var i = 0; i < fields.length; i++)
                                  Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 12),
                                      child: TextField(
                                          controller: fields[i],
                                          maxLines: i == 5 ? 3 : 1,
                                          decoration: InputDecoration(
                                              labelText: labels[i])))
                              ]))),
                  const SizedBox(height: 12),
                  section('Nombramientos', jobs, false),
                  const SizedBox(height: 12),
                  section('Otras instituciones', external, true),
                  const SizedBox(height: 12),
                  Builder(builder: (ctx) {
                    final result = ValidationService.validate(jobs, external);
                    return Card(
                        elevation: 0,
                        child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      'Horas institucionales: ${result.institutionalHours.toStringAsFixed(2)} / ${result.expectedHours.toStringAsFixed(2)} esperadas'),
                                  Text(
                                      'Horas externas: ${result.externalHours.toStringAsFixed(2)}'),
                                  ...result.errors.map((e) => Text('• $e',
                                      style: const TextStyle(
                                          color: Colors.deepOrange)))
                                ])));
                  }),
                  const SizedBox(height: 16),
                  FilledButton(
                      onPressed: busy ? null : save,
                      child: Text(busy ? 'Guardando...' : 'Guardar borrador'))
                ]))));
  }

  Widget section(String title, List<Appointment> list, bool isExternal) {
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
                  child: Text(title,
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    final appointment = await Navigator.push<Appointment>(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const AppointmentPage()),
                    );
                    if (appointment != null && mounted) {
                      setState(() => list.add(appointment));
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
                  '${list[i].position} · ${list[i].blocks.length} bloques',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Editar',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () async {
                        final index = i;
                        final edited = await Navigator.push<Appointment>(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                AppointmentPage(existing: list[index]),
                          ),
                        );
                        if (edited != null && mounted && index < list.length) {
                          setState(() => list[index] = edited);
                        }
                      },
                    ),
                    IconButton(
                      tooltip: 'Eliminar',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => setState(() => list.removeAt(i)),
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

class AppointmentPage extends StatefulWidget {
  final Appointment? existing;

  const AppointmentPage({super.key, this.existing});

  @override
  State<AppointmentPage> createState() => _AppointmentPageState();
}

class _AppointmentPageState extends State<AppointmentPage> {
  final f = List.generate(5, (_) => TextEditingController());
  final blocks = <TimeBlock>[];
  final start = TextEditingController(text: '08:00');
  final end = TextEditingController(text: '12:00');
  int day = 1;

  @override
  void initState() {
    super.initState();
    final appointment = widget.existing;
    if (appointment != null) {
      f[0].text = appointment.workplace;
      f[1].text = appointment.position;
      f[2].text = appointment.expectedHours.toString();
      f[3].text = appointment.startDate;
      f[4].text = appointment.endDate;
      blocks.addAll(appointment.blocks);
    }
  }

  @override
  void dispose() {
    for (final controller in f) {
      controller.dispose();
    }
    start.dispose();
    end.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const labels = [
      'Lugar de trabajo / institución',
      'Cargo o categoría',
      'Jornada semanal esperada (horas)',
      'Inicio de vigencia (AAAA-MM-DD)',
      'Fin de vigencia (AAAA-MM-DD)',
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null
            ? 'Agregar nombramiento'
            : 'Editar nombramiento'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              for (var i = 0; i < f.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: f[i],
                    decoration: InputDecoration(labelText: labels[i]),
                  ),
                ),
              const Text('Bloques horarios (lunes a sábado)'),
              DropdownButton<int>(
                value: day,
                items: [
                  for (var i = 1; i <= 6; i++)
                    DropdownMenuItem(value: i, child: Text(days[i])),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => day = value);
                },
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: start,
                      decoration:
                          const InputDecoration(labelText: 'Inicio HH:MM'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: end,
                      decoration: const InputDecoration(labelText: 'Fin HH:MM'),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Agregar bloque horario',
                    onPressed: () {
                      try {
                        final initialMinutes =
                            ValidationService.minutes(start.text.trim());
                        final finalMinutes =
                            ValidationService.minutes(end.text.trim());
                        if (finalMinutes <= initialMinutes)
                          throw FormatException();
                        setState(() {
                          blocks.add(TimeBlock(
                            day: day,
                            start: start.text.trim(),
                            end: end.text.trim(),
                          ));
                        });
                      } catch (_) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Horario inválido')),
                        );
                      }
                    },
                    icon: const Icon(Icons.add_circle),
                  ),
                ],
              ),
              for (var i = 0; i < blocks.length; i++)
                ListTile(
                  title: Text(
                      '${days[blocks[i].day]} ${blocks[i].start}–${blocks[i].end}'),
                  trailing: IconButton(
                    tooltip: 'Quitar bloque',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => blocks.removeAt(i)),
                  ),
                ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {
                  final expected = double.tryParse(f[2].text.trim());
                  if (f[0].text.trim().isEmpty ||
                      blocks.isEmpty ||
                      expected == null ||
                      expected <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'Complete institución, jornada válida y bloques'),
                      ),
                    );
                    return;
                  }
                  Navigator.pop(
                    context,
                    Appointment(
                      workplace: f[0].text.trim(),
                      position: f[1].text.trim(),
                      expectedHours: expected,
                      startDate: f[3].text.trim(),
                      endDate: f[4].text.trim(),
                      blocks: List.of(blocks),
                    ),
                  );
                },
                child: Text(
                  widget.existing == null
                      ? 'Agregar nombramiento'
                      : 'Guardar cambios',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TimelinePage extends StatelessWidget {
  final String id;
  const TimelinePage({super.key, required this.id});
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Historial y auditoría')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: DeclarationService().timeline(id),
          builder: (ctx, s) {
            if (s.hasError) return Center(child: Text('${s.error}'));
            if (!s.hasData)
              return const Center(child: CircularProgressIndicator());
            return ListView(
                children: s.data!.docs.map((doc) {
              final d = doc.data();
              return ListTile(
                  leading: const Icon(Icons.history),
                  title: Text('${d['event']} · v${d['version']}'),
                  subtitle: Text(
                      '${d['previousStatus']} → ${d['newStatus']}\n${d['observation'] ?? ''}\nUsuario: ${d['userId']}'),
                  isThreeLine: true);
            }).toList());
          }));
}
