import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

FirebaseFunctions get _functions =>
    FirebaseFunctions.instanceFor(region: 'us-east1');

class MisDeclarantesPage extends StatefulWidget {
  const MisDeclarantesPage({super.key});

  @override
  State<MisDeclarantesPage> createState() => _MisDeclarantesPageState();
}

class _MisDeclarantesPageState extends State<MisDeclarantesPage> {
  late Future<HttpsCallableResult<dynamic>> _assigned = _load();

  Future<HttpsCallableResult<dynamic>> _load() =>
      _functions.httpsCallable('listarMisDeclarantes').call();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Mis declarantes')),
        body: FutureBuilder<HttpsCallableResult<dynamic>>(
          future: _assigned,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: TextButton(
                  onPressed: () => setState(() => _assigned = _load()),
                  child: const Text('No se pudieron cargar. Reintentar'),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final users = List<dynamic>.from(snapshot.data!.data as List);
            if (users.isEmpty) {
              return const Center(
                  child: Text('No tenés declarantes asignados.'));
            }
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                for (final user in users)
                  ListTile(
                    title: Text(user['name'] as String),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => NuevaDeclaracionSuperiorPage(
                          uid: user['uid'] as String,
                          name: user['name'] as String,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      );
}

class NuevaDeclaracionSuperiorPage extends StatefulWidget {
  const NuevaDeclaracionSuperiorPage({super.key, this.uid, this.name});

  final String? uid;
  final String? name;

  @override
  State<NuevaDeclaracionSuperiorPage> createState() =>
      NuevaDeclaracionSuperiorPageState();
}

class NuevaDeclaracionSuperiorPageState
    extends State<NuevaDeclaracionSuperiorPage> {
  static const _days = [
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
  ];

  final _form = GlobalKey<FormState>();
  final _position = TextEditingController();
  final _hours = TextEditingController();
  final _begin = TextEditingController();
  final _finish = TextEditingController();
  final _course = TextEditingController();
  final _start = TextEditingController(text: '08:00');
  final _end = TextEditingController(text: '09:00');
  final _blocks = <Map<String, dynamic>>[];

  final _operation = FirebaseFirestore.instance.collection('users').doc().id;
  late final _periods = FirebaseFirestore.instance
      .collection('periods')
      .where('enabled', isEqualTo: true)
      .snapshots();

  String? _period;
  late String? _declaranteId = widget.uid;
  late final Future<HttpsCallableResult<dynamic>> _declarantes =
      _functions.httpsCallable('listarMisDeclarantes').call();

  Widget _declaranteField() {
    final name = widget.name;
    if (name != null && widget.uid != null) {
      return InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Declarante',
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          border: OutlineInputBorder(),
        ),
        child: Text(name),
      );
    }

    return FutureBuilder<HttpsCallableResult<dynamic>>(
      future: _declarantes,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text('No se pudieron cargar los declarantes.');
        }
        if (!snapshot.hasData) return const LinearProgressIndicator();
        final users = snapshot.data!.data as List;
        if (users.isEmpty) {
          return const Text('No tenés declarantes asignados.');
        }

        return DropdownButtonFormField<String>(
          initialValue: _declaranteId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Declarante',
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            border: OutlineInputBorder(),
          ),
          hint: const Text('Seleccioná un declarante'),
          items: [
            for (final user in users)
              DropdownMenuItem<String>(
                value: user['uid'] as String,
                child: Text(
                  user['name'] as String,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: _busy ? null : (id) => setState(() => _declaranteId = id),
          validator: (id) => id == null ? 'Seleccioná un declarante.' : null,
        );
      },
    );
  }

  int _day = 1;
  bool _busy = false;

  @override
  void dispose() {
    for (final controller in [
      _position,
      _hours,
      _begin,
      _finish,
      _course,
      _start,
      _end,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _notice(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  int? _minutes(String input) {
    final value = input.trim();
    if (!RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(value)) {
      return null;
    }
    final parts = value.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  int get _contactMinutes => _blocks.fold<int>(
        0,
        (sum, block) =>
            sum +
            _minutes(block['end'] as String)! -
            _minutes(block['start'] as String)!,
      );

  void _addBlock() {
    final course = _course.text.trim().toUpperCase();
    final from = _minutes(_start.text);
    final to = _minutes(_end.text);
    if (!RegExp(r'^[A-Z0-9][A-Z0-9-]{1,19}$').hasMatch(course)) {
      _notice('Ingresá las siglas del curso.');
      return;
    }
    if (from == null || to == null || from < 420 || to > 1310 || from >= to) {
      _notice('Ingresá un bloque válido entre 07:00 y 21:50.');
      return;
    }
    if (from < 780 && to > 720) {
      _notice('El horario de 12:00 a 13:00 está bloqueado.');
      return;
    }
    if (_blocks.any((block) =>
        block['day'] == _day &&
        from < _minutes(block['end'] as String)! &&
        to > _minutes(block['start'] as String)!)) {
      _notice('El bloque se traslapa con otro del mismo día.');
      return;
    }
    if (_blocks.length >= 84) {
      _notice('El nombramiento admite hasta 84 bloques.');
      return;
    }
    setState(() => _blocks.add({
          'day': _day,
          'start': _start.text.trim(),
          'end': _end.text.trim(),
          'courseCode': course,
          'activityType': 'CONTACTO',
        }));
  }

  Future<void> _date(TextEditingController controller) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(controller.text) ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5, 12, 31),
    );
    if (!mounted || date == null) return;
    controller.text = date.toIso8601String().substring(0, 10);
  }

  Future<void> _send() async {
    if (_busy ||
        _declaranteId == null ||
        _period == null ||
        !_form.currentState!.validate()) return;
    final hours = double.tryParse(_hours.text.trim().replaceAll(',', '.'));
    if (hours == null || !hours.isFinite || hours <= 0 || hours > 40) {
      _notice('Ingresá una jornada mayor que cero y de hasta 40 horas.');
      return;
    }
    if (_begin.text.compareTo(_finish.text) > 0) {
      _notice('La fecha final debe ser igual o posterior a la inicial.');
      return;
    }
    if (_blocks.isEmpty || _contactMinutes > hours * 60) {
      _notice('Agregá bloques de contacto que quepan dentro de la jornada.');
      return;
    }

    setState(() => _busy = true);
    try {
      await _functions.httpsCallable('publicarNombramiento').call({
        'uid': _declaranteId,
        'periodId': _period,
        'operationId': _operation,
        'appointment': {
          'position': _position.text.trim(),
          'expectedHours': hours,
          'startDate': _begin.text,
          'endDate': _finish.text,
          'blocks': _blocks,
        },
      });
      if (!mounted) return;
      _notice('Nombramiento enviado al declarante.');
      Navigator.of(context).pop();
    } on FirebaseFunctionsException catch (error) {
      if (mounted) _notice(error.message ?? 'No se pudo enviar.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _appointmentOptions() {
    const positions = [
      'Interino Bachiller',
      'Interino Licenciado',
      'Instructor',
      'Adjunto',
      'Asociado',
      'Catedrático',
      'Coordinación de Carrera',
      'Coordinación de Docencia',
      'Coordinación de Investigación',
      'Coordinación de Acción Social',
      'Coordinación de Administración',
      'Proyectos',
    ];

    const workloads = {
      '5': '1/8 · 5 horas',
      '10': '1/4 · 10 horas',
      '15': '3/8 · 15 horas',
      '20': '1/2 · 20 horas',
      '25': '5/8 · 25 horas',
      '30': '3/4 · 30 horas',
      '35': '7/8 · 35 horas',
      '40': '1 TC · 40 horas',
    };

    InputDecoration decoration(String label) => InputDecoration(
          labelText: label,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          border: const OutlineInputBorder(),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue:
              positions.contains(_position.text) ? _position.text : null,
          isExpanded: true,
          decoration: decoration('Cargo o categoría'),
          items: [
            for (final position in positions)
              DropdownMenuItem(
                value: position,
                child: Text(position, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: _busy ? null : (value) => _position.text = value ?? '',
          validator: (value) => value == null ? 'Seleccioná un cargo.' : null,
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: workloads.containsKey(_hours.text) ? _hours.text : null,
          isExpanded: true,
          decoration: decoration('Jornada de trabajo'),
          items: [
            for (final entry in workloads.entries)
              DropdownMenuItem(
                value: entry.key,
                child: Text(entry.value),
              ),
          ],
          onChanged: _busy ? null : (value) => _hours.text = value ?? '',
          validator: (value) =>
              value == null ? 'Seleccioná una jornada.' : null,
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _field(
                'Inicio de vigencia',
                _begin,
                required: true,
                onTap: () => _date(_begin),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _field(
                'Fin de vigencia',
                _finish,
                required: true,
                onTap: () => _date(_finish),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    bool required = false,
    VoidCallback? onTap,
    TextInputType? keyboard,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextFormField(
          controller: controller,
          enabled: !_busy,
          readOnly: onTap != null,
          onTap: onTap,
          keyboardType: keyboard,
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            border: const OutlineInputBorder(),
          ),
          validator: (value) => required && (value ?? '').trim().isEmpty
              ? 'Completá este campo.'
              : null,
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            // Formulario compacto del superior.
            backgroundColor: const Color(0xFF005A91),
            foregroundColor: Colors.white,
            toolbarHeight: 52,
            title: const Text('Nueva declaración')),
        body: _withContactSchedule(
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Form(
                key: _form,
                child: ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    _declaranteField(),
                    const SizedBox(height: 8),
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _periods,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return const Text(
                              'No se pudieron cargar los períodos.');
                        }
                        if (!snapshot.hasData)
                          return const LinearProgressIndicator();
                        final docs = snapshot.data!.docs;
                        final active = docs.any((doc) => doc.id == _period);
                        if (docs.isEmpty)
                          return const Text('No hay períodos habilitados.');
                        return DropdownButton<String>(
                          value: active ? _period : null,
                          isExpanded: true,
                          hint: const Text('Seleccioná un período'),
                          items: [
                            for (final doc in docs)
                              DropdownMenuItem(
                                value: doc.id,
                                child: Text((doc.data()['name'] ??
                                        doc.data()['label'] ??
                                        doc.id)
                                    .toString()),
                              ),
                          ],
                          onChanged: _busy
                              ? null
                              : (id) => setState(() => _period = id),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    _appointmentOptions(),
                    const Divider(),
                    Text('Bloques de contacto',
                        style: Theme.of(context).textTheme.titleMedium),
                    DropdownButton<int>(
                      value: _day,
                      items: [
                        for (var i = 0; i < _days.length; i++)
                          DropdownMenuItem(value: i + 1, child: Text(_days[i])),
                      ],
                      onChanged:
                          _busy ? null : (day) => setState(() => _day = day!),
                    ),
                    _field('Siglas del curso', _course),
                    Row(
                      children: [
                        Expanded(child: _field('Inicio HH:MM', _start)),
                        const SizedBox(width: 12),
                        Expanded(child: _field('Fin HH:MM', _end)),
                      ],
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _addBlock,
                      icon: const Icon(Icons.add),
                      label: const Text('Agregar bloque de contacto'),
                    ),
                    for (var i = 0; i < _blocks.length; i++)
                      ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        title: Text('${_blocks[i]['courseCode']} · '
                            '${_days[(_blocks[i]['day'] as int) - 1]}'),
                        subtitle:
                            Text('${_blocks[i]['start']}–${_blocks[i]['end']}'),
                        trailing: IconButton(
                          tooltip: 'Quitar bloque',
                          icon: const Icon(Icons.close),
                          onPressed: _busy
                              ? null
                              : () => setState(() => _blocks.removeAt(i)),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                        'Contacto: ${_contactMinutes ~/ 60} h ${_contactMinutes % 60} min'),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: _busy ||
                              _declaranteId == null ||
                              _period == null ||
                              _blocks.isEmpty
                          ? null
                          : _send,
                      child: _busy
                          ? const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF29557D),
                                  ),
                                ),
                                SizedBox(width: 10),
                                Text('Enviando…'),
                              ],
                            )
                          : const Text('Enviar al declarante'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  Widget _withContactSchedule(Widget form) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final schedule = _contactSchedule(context);
        if (constraints.maxWidth >= 960) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 4, child: form),
              Expanded(flex: 6, child: schedule),
            ],
          );
        }

        return Column(
          children: [
            Expanded(flex: 3, child: form),
            Expanded(flex: 2, child: schedule),
          ],
        );
      },
    );
  }

  Widget _contactSchedule(BuildContext context) {
    const blue = Color(0xFF005A91);
    const palette = [
      Color(0xFFD5E9FA),
      Color(0xFFB7D8EE),
      Color(0xFF9CCDE0),
      Color(0xFFC7DFEB),
      Color(0xFFA9C3E5),
      Color(0xFFD2DDF4),
      Color(0xFFAFDAE5),
      Color(0xFFC5D4E6),
    ];
    final colors = <String, Color>{};
    for (final block in _blocks) {
      final course = block['courseCode'] as String;
      colors.putIfAbsent(course, () => palette[colors.length % palette.length]);
    }

    Widget cell(
      String text, {
      String? tooltip,
      Color background = const Color(0xFFF0F3F6),
      Color foreground = blue,
      int flex = 1,
    }) {
      final content = Container(
        margin: const EdgeInsets.all(0.5),
        padding: const EdgeInsets.symmetric(horizontal: 3),
        alignment: Alignment.center,
        color: background,
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: foreground, fontSize: 11),
        ),
      );
      return Expanded(
        flex: flex,
        child: tooltip == null
            ? content
            : Tooltip(message: tooltip, child: content),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 16, 16),
      child: Card(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Color(0xFFD2E0ED)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final rowHeight = ((constraints.maxHeight - 88) / 16)
                .clamp(24.0, 42.0)
                .toDouble();

            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Text(
                  'Horario semanal',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                    'Contacto: ${_contactMinutes ~/ 60} h ${_contactMinutes % 60} min'),
                const SizedBox(height: 10),
                SizedBox(
                  height: rowHeight,
                  child: Row(
                    children: [
                      for (final label in ['Horas', ..._days])
                        cell(label,
                            tooltip: label,
                            background: blue,
                            foreground: Colors.white),
                    ],
                  ),
                ),
                for (var hour = 7; hour <= 21; hour++)
                  SizedBox(
                    height: rowHeight,
                    child: Row(
                      children: [
                        cell(
                          '${hour.toString().padLeft(2, '0')}:00–${hour.toString().padLeft(2, '0')}:50',
                          background: blue,
                          foreground: Colors.white,
                        ),
                        if (hour == 12)
                          cell('', flex: 6, background: const Color(0xFF424B55))
                        else
                          for (var day = 1; day <= 6; day++)
                            Builder(
                              builder: (context) {
                                final matches = _blocks.where((block) {
                                  return block['day'] == day &&
                                      _minutes(block['start'] as String)! <
                                          (hour + 1) * 60 &&
                                      _minutes(block['end'] as String)! >
                                          hour * 60;
                                }).toList();
                                if (matches.isEmpty) return cell('');

                                final courses = matches
                                    .map((block) =>
                                        block['courseCode'] as String)
                                    .toSet()
                                    .join(' / ');
                                final times = matches.map((block) {
                                  return '${block['courseCode']}: ${block['start']}–${block['end']}';
                                }).join('\n');

                                return cell(
                                  courses,
                                  tooltip: times,
                                  background: matches.length == 1
                                      ? colors[matches.first['courseCode']]!
                                      : const Color(0xFFDDE8EF),
                                );
                              },
                            ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
