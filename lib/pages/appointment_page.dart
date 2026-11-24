import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import '../theme/ucr_colors.dart';
import '../models/declaration.dart';
import '../services/validation_service.dart';
import '../widgets/declared_hours_summary.dart';
import 'declaration_observation_tools.dart';

const days = [
  '',
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
];

class AppointmentPage extends StatefulWidget {
  final Appointment? existing;
  final bool noPendingAppointment;
  final bool lockAssignment;
  final String? relatedAssignmentId;
  final List<Appointment> otherAppointments;
  final String? institutionalWorkplace;

  const AppointmentPage({
    super.key,
    this.existing,
    this.noPendingAppointment = false,
    this.lockAssignment = false,
    this.relatedAssignmentId,
    this.otherAppointments = const [],
    this.institutionalWorkplace,
  });

  @override
  State<AppointmentPage> createState() => _AppointmentPageState();
}

class _AppointmentPageState extends State<AppointmentPage> {
  final f = List.generate(5, (_) => TextEditingController());
  final blocks = <TimeBlock>[];

  final start = TextEditingController(text: '08:00');
  final end = TextEditingController(text: '12:00');

  final _courseCode = TextEditingController();
  final _activityName = TextEditingController();

  int day = 1;
  String? _workloadFraction;
  String? _activityType;
  int? _editingBlock;

  bool get _institutional => widget.institutionalWorkplace != null;

  bool get _requiresCourse =>
      _institutional && DeclarationObservationTools.isTeaching(f[1].text);

  bool get _fixedActivity =>
      widget.lockAssignment &&
      !DeclarationObservationTools.isTeaching(f[1].text);

  bool _lockedBlock(TimeBlock block) =>
      widget.lockAssignment &&
      (_fixedActivity || block.activityType == 'CONTACTO');

  static const List<String> _positions = [
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

  static const Map<String, double> _workloadHours = {
    '1/8': 5,
    '1/4': 10,
    '3/8': 15,
    '1/2': 20,
    '5/8': 25,
    '3/4': 30,
    '7/8': 35,
    '1 TC': 40,
  };

  @override
  void initState() {
    super.initState();

    final appointment = widget.existing;

    if (appointment != null) {
      f[0].text = appointment.workplace;
      f[1].text = appointment.position;
      f[2].text = appointment.expectedHours.toString();
      f[3].text = appointment.startDate;

      if (_institutional) {
        _workloadFraction = appointment.workloadFraction ?? 'LEGACY';
      }

      f[4].text = appointment.endDate.trim().toLowerCase() == 'no aplica'
          ? ''
          : appointment.endDate;

      blocks.addAll(appointment.blocks);
    }

    final workplace = widget.institutionalWorkplace;

    if (workplace != null) {
      f[0].text = workplace;
    }

    if (_institutional && !_requiresCourse) {
      _activityName.text = f[1].text;
    }
  }

  @override
  void dispose() {
    for (final controller in f) {
      controller.dispose();
    }

    start.dispose();
    end.dispose();
    _courseCode.dispose();
    _activityName.dispose();

    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  InputDecoration _decoration(
    String label, {
    String? helper,
  }) {
    return InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 12,
      ),
      labelText: label,
      helperText: helper,
      helperMaxLines: 3,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  Widget _positionField() {
    if (widget.lockAssignment) {
      return Text('Cargo: ${f[1].text}');
    }

    final previous = f[1].text.trim();
    final available = _positions.contains(previous);

    return DropdownButtonFormField<String>(
      key: ValueKey('position-$previous'),
      initialValue: available ? previous : null,
      isExpanded: true,
      decoration: _decoration(
        'Cargo o categoría',
        helper: previous.isNotEmpty && !available
            ? 'Cargo anterior: $previous. Seleccioná una opción.'
            : null,
      ),
      hint: const Text('Seleccioná un cargo'),
      items: _positions
          .map(
            (position) => DropdownMenuItem<String>(
              value: position,
              child: Text(
                position,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: (value) {
        setState(() {
          f[1].text = value ?? '';
          _editingBlock = null;
          _courseCode.clear();
          _activityType = null;
          _activityName.text =
              _institutional && !_requiresCourse ? f[1].text : '';
        });
      },
    );
  }

  Widget _hoursField({bool readOnly = false}) {
    return TextField(
      controller: f[2],
      readOnly: readOnly,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
      ),
      decoration: _decoration(
        'Jornada semanal esperada (horas)',
      ),
    );
  }

  Widget _workloadField() {
    if (widget.lockAssignment) {
      return Text('Jornada: ${f[2].text} h semanales');
    }

    if (!_institutional) {
      return _hoursField();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('workload-$_workloadFraction'),
          initialValue: _workloadFraction,
          isExpanded: true,
          decoration: _decoration(
            'Jornada de trabajo UCR',
            helper: '1 TC equivale a 40 horas semanales.',
          ),
          hint: const Text('Seleccioná la jornada'),
          items: [
            if (widget.existing != null &&
                widget.existing!.workloadFraction == null)
              const DropdownMenuItem<String>(
                value: 'LEGACY',
                child: Text(
                  'Mantener jornada anterior en horas',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            for (final entry in _workloadHours.entries)
              DropdownMenuItem<String>(
                value: entry.key,
                child: Text(
                  '${entry.key} '
                  '(${entry.value.toStringAsFixed(0)} horas semanales)',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) {
            setState(() {
              _workloadFraction = value;

              if (value == 'LEGACY') {
                f[2].text = widget.existing!.expectedHours.toString();
              } else if (value != null) {
                f[2].text = _workloadHours[value]!.toString();
              }
            });
          },
        ),
        const SizedBox(height: 8),
        _hoursField(
          readOnly: _workloadFraction != 'LEGACY',
        ),
      ],
    );
  }

  Future<void> _chooseDate(
    TextEditingController controller,
  ) async {
    final initial =
        ValidationService.parseDate(controller.text.trim()) ?? DateTime.now();

    final chosen = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Seleccioná la fecha',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
      fieldHintText: 'dd/mm/aaaa',
      locale: const Locale('es', 'ES'),
    );

    if (chosen == null || !mounted) return;

    setState(() {
      controller.text = '${chosen.year.toString().padLeft(4, '0')}-'
          '${chosen.month.toString().padLeft(2, '0')}-'
          '${chosen.day.toString().padLeft(2, '0')}';
    });
  }

  Widget _timeWheel({
    required FixedExtentScrollController controller,
    required int count,
    required ValueChanged<int> onChanged,
  }) {
    return SizedBox(
      width: 84,
      child: CupertinoPicker(
        scrollController: controller,
        itemExtent: 44,
        diameterRatio: 1.8,
        squeeze: 1.0,
        useMagnifier: false,
        selectionOverlay: null,
        onSelectedItemChanged: onChanged,
        children: List.generate(
          count,
          (index) => Center(
            child: Text(
              index.toString().padLeft(2, '0'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 25,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _chooseTime(
    TextEditingController controller,
  ) async {
    final parts = controller.text.trim().split(':');

    final parsedHour = parts.isNotEmpty ? int.tryParse(parts[0]) : null;

    final parsedMinute = parts.length > 1 ? int.tryParse(parts[1]) : null;

    int hour = parsedHour != null && parsedHour >= 0 && parsedHour < 24
        ? parsedHour
        : 8;

    int minute = parsedMinute != null && parsedMinute >= 0 && parsedMinute < 60
        ? parsedMinute
        : 0;

    final hourController = FixedExtentScrollController(initialItem: hour);

    final minuteController = FixedExtentScrollController(initialItem: minute);

    final selected = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => Dialog(
        backgroundColor: const Color(0xFF1D1D20),
        insetPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 20,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 390),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Seleccionar hora',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 205,
                  child: Center(
                    child: SizedBox(
                      width: 208,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFF39393F),
                              borderRadius: BorderRadius.circular(11),
                            ),
                          ),
                          CupertinoTheme(
                            data: const CupertinoThemeData(
                              brightness: Brightness.dark,
                              primaryColor: Colors.white,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _timeWheel(
                                  controller: hourController,
                                  count: 24,
                                  onChanged: (value) {
                                    hour = value;
                                  },
                                ),
                                const SizedBox(
                                  width: 26,
                                  child: Center(
                                    child: Text(
                                      ':',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 26,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                _timeWheel(
                                  controller: minuteController,
                                  count: 60,
                                  onChanged: (value) {
                                    minute = value;
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        Navigator.pop(dialogContext, false);
                      },
                      child: const Text('Cancelar'),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(dialogContext, true);
                      },
                      child: const Text(
                        'Aceptar',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (selected == true && mounted) {
      setState(() {
        controller.text = '${hour.toString().padLeft(2, '0')}:'
            '${minute.toString().padLeft(2, '0')}';
      });
    }
  }

  void _editBlock(int index) {
    final block = blocks[index];

    if (_lockedBlock(block)) {
      return;
    }

    setState(() {
      _editingBlock = index;
      day = block.day;
      start.text = block.start;
      end.text = block.end;
      _courseCode.text = block.courseCode ?? '';

      _activityType = DeclarationObservationTools.activityLabels.containsKey(
        block.activityType,
      )
          ? block.activityType
          : null;

      _activityName.text = (block.activityName ?? '').trim().isNotEmpty
          ? block.activityName!
          : _institutional && !_requiresCourse
              ? f[1].text
              : '';
    });
  }

  void _cancelBlockEdit() {
    setState(() {
      _editingBlock = null;
      _courseCode.clear();
      _activityType = null;
      _activityName.text = _institutional && !_requiresCourse ? f[1].text : '';
    });
  }

  void _addOrUpdateBlock() {
    if (_fixedActivity) return;
    if (!_positions.contains(f[1].text.trim())) {
      _showMessage('Primero seleccioná el cargo o categoría.');
      return;
    }

    try {
      final initialMinutes = ValidationService.minutes(start.text.trim());

      final finalMinutes = ValidationService.minutes(end.text.trim());

      if (finalMinutes <= initialMinutes) {
        _showMessage(
          'La hora final debe ser posterior a la inicial.',
        );
        return;
      }
    } catch (_) {
      _showMessage('Horario inválido.');
      return;
    }

    if (widget.lockAssignment &&
        !['CONSULTA', 'PREPARACION'].contains(_activityType)) {
      _showMessage('Seleccioná consulta o preparación.');
      return;
    }

    final block = TimeBlock(
      day: day,
      start: start.text.trim(),
      end: end.text.trim(),
      courseCode: _requiresCourse
          ? DeclarationObservationTools.normalizeCode(
              _courseCode.text,
            )
          : null,
      activityType: _requiresCourse ? _activityType : null,
      activityName:
          _institutional && !_requiresCourse ? _activityName.text.trim() : null,
    );

    final conflict = _scheduleError(
      block,
      skip: _editingBlock,
    );

    if (conflict != null || block.activityType == 'CONTACTO') {
      _showMessage(
        conflict ?? 'Seleccioná preparación o consulta.',
      );
      return;
    }

    if (widget.lockAssignment) {
      final courses = widget.existing!.blocks
          .where((item) => item.activityType == 'CONTACTO')
          .map((item) => item.courseCode)
          .toSet();

      if (!courses.contains(block.courseCode)) {
        _showMessage(
          'Seleccioná uno de los cursos asignados por el superior.',
        );
        return;
      }

      final currentMinutes = blocks
          .asMap()
          .entries
          .where((entry) => entry.key != _editingBlock)
          .fold<int>(
            0,
            (sum, entry) =>
                sum +
                ValidationService.minutes(entry.value.end) -
                ValidationService.minutes(entry.value.start),
          );

      final added = ValidationService.minutes(block.end) -
          ValidationService.minutes(block.start);

      if (currentMinutes + added > widget.existing!.expectedHours * 60) {
        _showMessage(
          'El bloque supera las horas pendientes de tu jornada.',
        );
        return;
      }
    }

    final error = DeclarationObservationTools.blockError(
      block,
      f[1].text.trim(),
      !_institutional,
    );

    if (error != null) {
      _showMessage(error);
      return;
    }

    setState(() {
      final index = _editingBlock;

      if (index == null) {
        blocks.add(block);
      } else {
        blocks[index] = block;
      }

      _editingBlock = null;
    });
  }

  void _removeBlock(int index) {
    if (_lockedBlock(blocks[index])) return;
    setState(() {
      blocks.removeAt(index);

      if (_editingBlock == index) {
        _editingBlock = null;
      } else if (_editingBlock != null && _editingBlock! > index) {
        _editingBlock = _editingBlock! - 1;
      }
    });
  }

  void _saveAppointment() {
    if (_editingBlock != null) {
      _showMessage(
        'Actualizá el bloque que estás editando '
        'o cancelá su edición.',
      );
      return;
    }

    if (!_positions.contains(f[1].text.trim())) {
      _showMessage('Seleccioná un cargo de la lista.');
      return;
    }

    if (_institutional && _workloadFraction == null) {
      _showMessage('Seleccioná la jornada del nombramiento UCR.');
      return;
    }

    final fraction = _institutional && _workloadFraction != 'LEGACY'
        ? _workloadFraction
        : null;

    if (fraction != null) {
      f[2].text = _workloadHours[fraction]!.toString();
    }

    final workplace = widget.institutionalWorkplace;

    if (workplace != null) {
      f[0].text = workplace;
    }

    final expected = double.tryParse(f[2].text.trim());

    if (f[0].text.trim().isEmpty ||
        blocks.isEmpty ||
        expected == null ||
        !expected.isFinite ||
        expected <= 0) {
      _showMessage(
        'Completá institución, jornada mayor que cero '
        'y al menos un bloque horario.',
      );
      return;
    }

    final beginDate = ValidationService.parseDate(f[3].text.trim());

    final finishDate = ValidationService.parseDate(f[4].text.trim());

    if (beginDate == null ||
        finishDate == null ||
        finishDate.isBefore(beginDate)) {
      _showMessage(
        'Seleccioná fechas válidas; el fin no puede '
        'ser anterior al inicio.',
      );
      return;
    }

    for (var i = 0; i < blocks.length; i++) {
      final error = _scheduleError(
            blocks[i],
            skip: i,
          ) ??
          DeclarationObservationTools.blockError(
            blocks[i],
            f[1].text.trim(),
            !_institutional,
          );

      if (error != null) {
        _showMessage('Bloque ${i + 1}: $error');
        return;
      }
    }

    Navigator.pop(
      context,
      Appointment(
        assignmentId: widget.existing?.assignmentId,
        relatedAssignmentId:
            widget.existing?.relatedAssignmentId ?? widget.relatedAssignmentId,
        workplace: f[0].text.trim(),
        position: f[1].text.trim(),
        expectedHours: expected,
        workloadFraction: fraction,
        startDate: f[3].text.trim(),
        endDate: f[4].text.trim(),
        blocks: List.of(blocks),
      ),
    );
  }

  Widget _dateField(int index, String label) {
    return TextField(
      controller: f[index],
      readOnly: true,
      onTap: () => _chooseDate(f[index]),
      decoration: _decoration(label).copyWith(
        suffixIcon: IconButton(
          tooltip: 'Abrir calendario',
          icon: const Icon(Icons.event_outlined),
          onPressed: () => _chooseDate(f[index]),
        ),
      ),
    );
  }

  Widget _blockActivityFields() {
    if (!_institutional) {
      return const SizedBox.shrink();
    }

    if (!_positions.contains(f[1].text.trim())) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Text(
          'Seleccioná el cargo para indicar '
          'la actividad de cada bloque.',
        ),
      );
    }

    if (_requiresCourse) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.lockAssignment)
            DropdownButtonFormField<String>(
              key: ValueKey(
                'assigned-course-$_editingBlock-${_courseCode.text}',
              ),
              initialValue: widget.existing!.blocks
                      .where(
                        (block) => block.activityType == 'CONTACTO',
                      )
                      .any(
                        (block) => block.courseCode == _courseCode.text,
                      )
                  ? _courseCode.text
                  : null,
              isExpanded: true,
              decoration: _decoration('Curso asignado'),
              items: [
                for (final code in widget.existing!.blocks
                    .where(
                      (block) => block.activityType == 'CONTACTO',
                    )
                    .map((block) => block.courseCode)
                    .whereType<String>()
                    .toSet())
                  DropdownMenuItem(
                    value: code,
                    child: Text(code),
                  ),
              ],
              onChanged: (value) {
                setState(() => _courseCode.text = value ?? '');
              },
            )
          else
            TextField(
              controller: _courseCode,
              maxLength: 20,
              textCapitalization: TextCapitalization.characters,
              decoration: _decoration(
                'Siglas del curso',
                helper: 'Ejemplo: IF0011. Podés usar cursos diferentes '
                    'en cada bloque.',
              ),
            ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: ValueKey(
              'activity-$_editingBlock-$_activityType',
            ),
            initialValue: _activityType == 'CONTACTO' ? null : _activityType,
            isExpanded: true,
            decoration: _decoration('Actividad del bloque'),
            hint: const Text('Seleccioná la actividad'),
            items: DeclarationObservationTools.activityLabels.entries
                .where((entry) => entry.key != 'CONTACTO')
                .map(
                  (entry) => DropdownMenuItem<String>(
                    value: entry.key,
                    child: Text(
                      entry.key == 'CONSULTA' ? 'Consulta' : entry.value,
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              setState(() => _activityType = value);
            },
          ),
          const SizedBox(height: 8),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _activityName,
        maxLength: 150,
        decoration: _decoration(
          'Nombre de la actividad',
          helper: 'Podés conservar el cargo o indicar una actividad '
              'específica, por ejemplo: Comisión de autoevaluación.',
        ),
      ),
    );
  }

  Iterable<TimeBlock> get _otherBlocks sync* {
    final from = ValidationService.parseDate(f[3].text.trim());

    final to = ValidationService.parseDate(f[4].text.trim());

    for (final appointment in widget.otherAppointments) {
      final otherFrom = ValidationService.parseDate(appointment.startDate);

      final otherTo = ValidationService.parseDate(appointment.endDate);

      if (from != null && otherTo != null && otherTo.isBefore(from)) {
        continue;
      }

      if (to != null && otherFrom != null && otherFrom.isAfter(to)) {
        continue;
      }

      yield* appointment.blocks;
    }
  }

  String? _scheduleError(
    TimeBlock block, {
    int? skip,
  }) {
    final start = ValidationService.minutes(block.start);
    final end = ValidationService.minutes(block.end);

    if (start < 420 || end > 1310) {
      return 'Usá horas entre 07:00 y 21:50.';
    }

    if (end <= start) {
      return 'La hora final debe ser posterior a la inicial.';
    }

    if (start < 780 && end > 720) {
      return 'Almuerzo bloqueado de 12:00 a 13:00.';
    }

    final comparable = [
      ..._otherBlocks,
      for (var i = 0; i < blocks.length; i++)
        if (i != skip) blocks[i],
    ];

    for (final other in comparable) {
      if (other.day == block.day &&
          start < ValidationService.minutes(other.end) &&
          end > ValidationService.minutes(other.start)) {
        return 'Traslape con el bloque de '
            '${other.start} a ${other.end}.';
      }
    }

    if (widget.lockAssignment && widget.existing != null) {
      final used =
          blocks.asMap().entries.where((entry) => entry.key != skip).fold<int>(
                0,
                (sum, entry) =>
                    sum +
                    ValidationService.minutes(entry.value.end) -
                    ValidationService.minutes(entry.value.start),
              );

      if (used + end - start > widget.existing!.expectedHours * 60) {
        return 'Este bloque supera las horas pendientes '
            'de la jornada.';
      }
    }

    return null;
  }

  Widget _schedule({bool empty = false}) {
    final other = _otherBlocks.toList();

    final all = empty ? <TimeBlock>[] : [...other, ...blocks];

    final total = all.fold<int>(
      0,
      (sum, block) =>
          sum +
          ValidationService.minutes(block.end) -
          ValidationService.minutes(block.start),
    );

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

    for (final block in all) {
      final code = block.courseCode?.trim() ?? '';

      if (code.isNotEmpty) {
        colors.putIfAbsent(
          code,
          () => palette[colors.length % palette.length],
        );
      }
    }

    const headings = [
      'Horas',
      'Lunes',
      'Martes',
      'Miércoles',
      'Jueves',
      'Viernes',
      'Sábado',
    ];

    Widget cell(
      String label, {
      Color? fill,
      bool header = false,
      int flex = 1,
    }) {
      return Expanded(
        flex: flex,
        child: Tooltip(
          message: label,
          child: Container(
            margin: const EdgeInsets.all(0.5),
            alignment: Alignment.center,
            color: fill ?? const Color(0xFFF0F3F6),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: header ? Colors.white : UcrColors.blue,
              ),
            ),
          ),
        ),
      );
    }

    return Card(
      color: Colors.white,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Horario semanal',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              '${total ~/ 60} h ${total % 60} min '
              'declarados en los bloques visibles',
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 24,
              child: Row(
                children: [
                  for (final label in headings)
                    cell(
                      label,
                      fill: UcrColors.blue,
                      header: true,
                    ),
                ],
              ),
            ),
            for (var hour = 7; hour <= 21; hour++)
              Expanded(
                child: Row(
                  children: [
                    cell(
                      '${hour.toString().padLeft(2, '0')}:00–'
                      '${hour.toString().padLeft(2, '0')}:50',
                      fill: UcrColors.blue,
                      header: true,
                    ),
                    if (hour == 12)
                      cell(
                        '',
                        flex: 6,
                        fill: const Color(0xFF424B55),
                        header: true,
                      )
                    else
                      for (var weekday = 1; weekday <= 6; weekday++)
                        Builder(
                          builder: (context) {
                            final matches = all
                                .where(
                                  (block) =>
                                      block.day == weekday &&
                                      ValidationService.minutes(
                                            block.start,
                                          ) <
                                          (hour + 1) * 60 &&
                                      ValidationService.minutes(
                                            block.end,
                                          ) >
                                          hour * 60,
                                )
                                .toList();

                            if (matches.isEmpty) {
                              return cell('');
                            }

                            final block = matches.first;

                            final label = matches
                                .map(
                                  (item) =>
                                      item.courseCode ??
                                      item.activityName ??
                                      '${item.start}–${item.end}',
                                )
                                .join(' / ');

                            return cell(
                              label,
                              fill: colors[block.courseCode] ??
                                  const Color(0xFFDDE8EF),
                            );
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

  Widget _fixedActivityForm() {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        InputDecorator(
          decoration: _decoration('Lugar de trabajo / institución'),
          child: Text(f[0].text),
        ),
        const SizedBox(height: 12),
        _positionField(),
        const SizedBox(height: 8),
        _workloadField(),
        const SizedBox(height: 8),
        Text('Vigencia: ${f[3].text} – ${f[4].text}'),
        const Divider(height: 24),
        Text(
          'Horario asignado por el superior',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        const Text(
          'El superior fijó el horario de esta actividad. No se puede modificar.',
        ),
        const SizedBox(height: 12),
        for (final block in blocks)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.lock_outline),
            title: Text(
              '${days[block.day]} · ${block.start}–${block.end}',
            ),
            subtitle: Text(
              DeclarationObservationTools.blockDescription(block),
            ),
          ),
        const SizedBox(height: 12),
        DeclaredHoursSummary(
          blocks: blocks,
          expectedHours: double.tryParse(f[2].text) ?? 0,
          position: f[1].text,
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _saveAppointment,
          child: const Text('Confirmar nombramiento'),
        ),
      ],
    );
  }

  Widget _formPair(Widget first, Widget second) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: first),
        const SizedBox(width: 12),
        Expanded(child: second),
      ],
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
          _fixedActivity
              ? 'Revisar nombramiento'
              : widget.existing == null
                  ? 'Agregar nombramiento'
                  : 'Editar nombramiento',
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (widget.noPendingAppointment) {
            const message = Center(
              child: Text(
                'No tienes declaraciones pendientes',
                textAlign: TextAlign.center,
              ),
            );

            final schedule = _schedule(empty: true);

            if (constraints.maxWidth >= 960) {
              return Row(
                children: [
                  const Expanded(child: message),
                  Expanded(child: schedule),
                ],
              );
            }

            return Column(
              children: [
                const Expanded(child: message),
                Expanded(
                  flex: 3,
                  child: schedule,
                ),
              ],
            );
          }

          return ListenableBuilder(
            listenable: Listenable.merge([
              start,
              end,
              f[3],
              f[4],
            ]),
            builder: (context, child) {
              final conflict = _scheduleError(
                TimeBlock(
                  day: day,
                  start: start.text,
                  end: end.text,
                ),
                skip: _editingBlock,
              );

              final form = _fixedActivity
                  ? _fixedActivityForm()
                  : ListView(
                      padding: const EdgeInsets.all(14),
                      children: [
                        TextField(
                          controller: f[0],
                          readOnly: _institutional,
                          decoration: _decoration(
                            'Lugar de trabajo / institución',
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (constraints.maxWidth >= 1160)
                          _formPair(
                            _positionField(),
                            _workloadField(),
                          )
                        else ...[
                          _positionField(),
                          const SizedBox(height: 8),
                          _workloadField(),
                        ],
                        const SizedBox(height: 8),
                        if (widget.lockAssignment)
                          Text(
                            'Vigencia: ${f[3].text} – ${f[4].text}',
                          )
                        else
                          _formPair(
                            _dateField(3, 'Inicio de vigencia'),
                            _dateField(4, 'Fin de vigencia'),
                          ),
                        const SizedBox(height: 8),
                        Text(
                          _editingBlock == null
                              ? 'Agregar bloque horario'
                              : 'Editar bloque ${_editingBlock! + 1}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        _blockActivityFields(),
                        DropdownButtonFormField<int>(
                          key: ValueKey('day-$day'),
                          initialValue: day,
                          decoration: _decoration('Día'),
                          items: [
                            for (var i = 1; i <= 6; i++)
                              DropdownMenuItem<int>(
                                value: i,
                                child: Text(days[i]),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => day = value);
                            }
                          },
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: start,
                                readOnly: true,
                                onTap: () => _chooseTime(start),
                                decoration: const InputDecoration(
                                  labelText: 'Inicio HH:MM',
                                  prefixIcon: Icon(
                                    Icons.access_time_outlined,
                                  ),
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: end,
                                readOnly: true,
                                onTap: () => _chooseTime(end),
                                decoration: const InputDecoration(
                                  labelText: 'Fin HH:MM',
                                  prefixIcon: Icon(
                                    Icons.access_time_outlined,
                                  ),
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (conflict != null)
                          Text(
                            conflict,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        FilledButton.tonalIcon(
                          onPressed:
                              conflict == null ? _addOrUpdateBlock : null,
                          icon: Icon(
                            _editingBlock == null ? Icons.add : Icons.check,
                          ),
                          label: Text(
                            _editingBlock == null
                                ? 'Agregar bloque'
                                : 'Actualizar bloque',
                          ),
                        ),
                        if (_editingBlock != null)
                          TextButton(
                            onPressed: _cancelBlockEdit,
                            child: const Text(
                              'Cancelar edición del bloque',
                            ),
                          ),
                        const SizedBox(height: 16),
                        for (var i = 0; i < blocks.length; i++)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              '${days[blocks[i].day]} '
                              '${blocks[i].start}–${blocks[i].end}',
                            ),
                            subtitle: Text(
                              DeclarationObservationTools.blockDescription(
                                          blocks[i])
                                      .isEmpty
                                  ? _institutional
                                      ? 'Actividad pendiente de completar'
                                      : f[1].text
                                  : DeclarationObservationTools
                                      .blockDescription(blocks[i]),
                            ),
                            leading: DeclarationObservationTools.blockError(
                                      blocks[i],
                                      f[1].text.trim(),
                                      !_institutional,
                                    ) ==
                                    null
                                ? const Icon(Icons.schedule)
                                : const Icon(
                                    Icons.warning_amber_outlined,
                                    color: Colors.deepOrange,
                                  ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Editar bloque',
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                  ),
                                  onPressed: widget.lockAssignment &&
                                          blocks[i].activityType == 'CONTACTO'
                                      ? null
                                      : () => _editBlock(i),
                                ),
                                IconButton(
                                  tooltip: 'Quitar bloque',
                                  icon: const Icon(Icons.close),
                                  onPressed: widget.lockAssignment &&
                                          blocks[i].activityType == 'CONTACTO'
                                      ? null
                                      : () => _removeBlock(i),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 12),
                        if (_institutional)
                          DeclaredHoursSummary(
                            blocks: blocks,
                            expectedHours: double.tryParse(f[2].text) ?? 0,
                            position: f[1].text,
                          ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _saveAppointment,
                          child: Text(
                            widget.existing == null
                                ? 'Agregar nombramiento'
                                : 'Guardar cambios',
                          ),
                        ),
                      ],
                    );

              if (constraints.maxWidth >= 960) {
                return Row(
                  children: [
                    Expanded(child: form),
                    Expanded(child: _schedule()),
                  ],
                );
              }

              return Column(
                children: [
                  Expanded(
                    flex: 3,
                    child: form,
                  ),
                  Expanded(
                    flex: 2,
                    child: _schedule(),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
