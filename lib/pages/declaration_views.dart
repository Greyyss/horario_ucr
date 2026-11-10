import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/declaration.dart';
import '../services/declaration_service.dart';
import '../services/declaration_observations.dart';
import '../theme/ucr_colors.dart';

const _navy = Color(0xFF073A77);
const _softBlue = Color(0xFFEDF8FF);
const _days = [
  '',
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
];

String _status(String value) =>
    const {
      'BORRADOR': 'Borrador',
      'VALIDADA': 'Validada',
      'PENDIENTE_FIRMA_DECLARANTE': 'Pendiente de firma del declarante',
      'FIRMADA_POR_DECLARANTE': 'Firmada por el declarante',
      'PENDIENTE_FIRMA_SUPERIOR': 'Pendiente de revisión del superior',
      'FIRMADA_POR_SUPERIOR': 'Firmada por el superior',
      'ENVIADA_A_RRHH': 'Enviada a RRHH',
      'RECIBIDA_RRHH': 'Recibida por RRHH',
      'DEVUELTA': 'Devuelta para corrección',
      'FINALIZADA': 'Finalizada',
      'ANULADA': 'Anulada',
    }[value] ??
    value.replaceAll('_', ' ');

String _date(String value) {
  final date = DateTime.tryParse(value);
  if (date == null) return value.isEmpty ? 'Sin registrar' : value;
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

String _eventDate(dynamic value) {
  if (value is! Timestamp) return 'Fecha no registrada';
  final date = value.toDate().toLocal();
  return '${_date(date.toIso8601String())} · ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

class DeclarationDetailPage extends StatelessWidget {
  final String id;
  final Widget Function(Declaration declaration) actionsBuilder;
  const DeclarationDetailPage({
    super.key,
    required this.id,
    required this.actionsBuilder,
  });

  @override
  Widget build(BuildContext context) => _Page(
        title: 'Detalle de la declaración',
        child: _DeclarationReader(
          id: id,
          builder: (d) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                icon: Icons.description_outlined,
                title: d.ownerName,
                subtitle: '${d.periodId} · Versión actual ${d.version}',
                footer: _StatusChip(d.status),
              ),
              const SizedBox(height: 20),
              _Surface(
                title: 'Datos del declarante',
                icon: Icons.person_outline,
                child: _Fields([
                  ('Nombre completo', d.ownerName),
                  ('Cédula', d.identification),
                  ('Correo electrónico', d.email),
                  ('Teléfono', d.phone),
                  ('Unidad académica o administrativa', d.unit),
                  ('Período', d.periodId),
                ]),
              ),
              _appointments(
                'Nombramientos UCR',
                Icons.account_balance_outlined,
                d.appointments,
              ),
              _appointments(
                'Otras instituciones',
                Icons.business_outlined,
                d.externalJobs,
              ),
              _Surface(
                title: 'Observaciones',
                icon: Icons.notes_outlined,
                child: SelectableText(
                  declarationPdfObservations(d.toMap()),
                  style: const TextStyle(color: UcrColors.text, height: 1.6),
                ),
              ),
              _Surface(
                title: 'Acciones disponibles',
                icon: Icons.task_alt_outlined,
                child: actionsBuilder(d),
              ),
            ],
          ),
        ),
      );

  Widget _appointments(String title, IconData icon, List<Appointment> list) =>
      _Surface(
        title: title,
        icon: icon,
        child: list.isEmpty
            ? const Text('No se registraron nombramientos en esta sección.')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < list.length; i++)
                    _appointment(list[i], i),
                ],
              ),
      );

  Widget _appointment(Appointment a, int index) {
    final hours = a.expectedHours == a.expectedHours.roundToDouble()
        ? a.expectedHours.toStringAsFixed(0)
        : a.expectedHours.toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _softBlue,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: UcrColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${index + 1}. ${a.position}',
            style: const TextStyle(
              color: _navy,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            a.workplace,
            style: const TextStyle(color: UcrColors.text),
          ),
          const SizedBox(height: 16),
          _Fields([
            (
              'Jornada semanal',
              '$hours horas${a.workloadFraction == null ? '' : ' · ${a.workloadFraction}'}',
            ),
            ('Inicio de vigencia', _date(a.startDate)),
            ('Fin de vigencia', _date(a.endDate)),
          ]),
          const Divider(height: 28),
          const Text(
            'Distribución del horario',
            style: TextStyle(color: _navy, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          ...a.blocks.map(
            (block) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 12,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 90,
                    child: Text(
                      block.day > 0 && block.day < _days.length
                          ? _days[block.day]
                          : 'Día ${block.day}',
                      style: const TextStyle(
                        color: _navy,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '${block.start} – ${block.end}',
                    style: const TextStyle(color: UcrColors.text),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DeclarationHistoryPicker extends StatefulWidget {
  final List<Declaration> declarations;
  const DeclarationHistoryPicker({super.key, required this.declarations});
  @override
  State<DeclarationHistoryPicker> createState() =>
      _DeclarationHistoryPickerState();
}

class _DeclarationHistoryPickerState extends State<DeclarationHistoryPicker> {
  String _search = '';
  @override
  Widget build(BuildContext context) {
    final items = widget.declarations
        .where(
          (d) => '${d.ownerName} ${d.periodId} ${_status(d.status)}'
              .toLowerCase()
              .contains(_search),
        )
        .toList();
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: SizedBox(
        width: 660,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Header(
                icon: Icons.history_outlined,
                title: 'Consultar historial',
                subtitle: 'Seleccioná la declaración que querés revisar.',
                rounded: false,
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: TextField(
                  onChanged: (value) =>
                      setState(() => _search = value.trim().toLowerCase()),
                  decoration: InputDecoration(
                    hintText: 'Buscar por nombre, período o estado',
                    prefixIcon: const Icon(Icons.search, color: UcrColors.blue),
                    filled: true,
                    fillColor: _softBlue,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: UcrColors.border),
                    ),
                  ),
                ),
              ),
              Flexible(
                child: items.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No hay declaraciones que coincidan con la búsqueda.',
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, index) {
                          final d = items[index];
                          return Material(
                            color: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: const BorderSide(color: UcrColors.border),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => Navigator.pop(context, d.id),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const CircleAvatar(
                                      backgroundColor: _softBlue,
                                      child: Icon(
                                        Icons.description_outlined,
                                        color: UcrColors.blue,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            d.ownerName,
                                            style: const TextStyle(
                                              color: _navy,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(height: 5),
                                          Text(
                                            '${d.periodId} · Versión ${d.version}',
                                            style: const TextStyle(
                                              color: UcrColors.text,
                                            ),
                                          ),
                                          const SizedBox(height: 9),
                                          _StatusChip(d.status),
                                        ],
                                      ),
                                    ),
                                    const Icon(
                                      Icons.chevron_right,
                                      color: UcrColors.blue,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DeclarationHistoryPage extends StatelessWidget {
  final String id;
  const DeclarationHistoryPage({super.key, required this.id});

  @override
  Widget build(BuildContext context) => _Page(
        title: 'Historial de la declaración',
        child: _DeclarationReader(
          id: id,
          builder: (d) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                icon: Icons.history_outlined,
                title: 'Historial y seguimiento',
                subtitle:
                    '${d.ownerName}\n${d.periodId} · Versión actual ${d.version}',
                footer: _StatusChip(d.status),
              ),
              const SizedBox(height: 20),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: DeclarationService().timeline(id),
                builder: (context, snapshot) {
                  if (snapshot.hasError)
                    return const _Message(
                      'No se pudo cargar el historial. Revisá tu conexión y los permisos de la cuenta.',
                    );
                  if (!snapshot.hasData)
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  final events = snapshot.data!.docs.reversed.toList();
                  final returned = latestDeclarationReturn(
                    events.map((event) => event.data()).toList(),
                    status: d.status,
                    currentReturnNote: d.returnNote,
                    currentVersion: d.version,
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (returned != null)
                        _Surface(
                          title: d.status == 'DEVUELTA'
                              ? 'Motivo de devolución'
                              : 'Última devolución registrada',
                          icon: Icons.assignment_return_outlined,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Versión ${returned['version'] ?? '—'}'
                                '${returned['dateTime'] == null ? '' : ' · ${_eventDate(returned['dateTime'])}'}',
                                style: const TextStyle(
                                  color: UcrColors.blue,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 12),
                              SelectableText(
                                returned['observation'].toString().trim(),
                                style: const TextStyle(
                                  color: UcrColors.text,
                                  fontSize: 15,
                                  height: 1.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                      _Surface(
                        title: 'Movimientos registrados (${events.length})',
                        icon: Icons.fact_check_outlined,
                        child: events.isEmpty
                            ? const Text(
                                'Todavía no hay movimientos registrados.')
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Text(
                                    'Más recientes primero',
                                    style: TextStyle(color: UcrColors.text),
                                  ),
                                  const SizedBox(height: 16),
                                  for (var i = 0; i < events.length; i++)
                                    _event(events[i].data()),
                                ],
                              ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      );

  Widget _event(Map<String, dynamic> data) {
    final action = data['event']?.toString() ?? '';
    final label = const {
          'CREADA': 'Declaración creada',
          'MODIFICADA': 'Borrador actualizado',
          'validate': 'Declaración validada',
          'submit': 'Enviada a firma del declarante',
          'signOwner': 'Firma del declarante registrada',
          'route': 'Remitida al superior',
          'signSuperior': 'Firma del superior registrada',
          'return': 'Devuelta para corrección',
          'sendHr': 'Enviada a Recursos Humanos',
          'receive': 'Recibida por Recursos Humanos',
          'finish': 'Trámite finalizado',
          'newVersion': 'Nueva versión creada',
          'annul': 'Declaración anulada',
        }[action] ??
        action.replaceAll('_', ' ');
    final note = data['observation']?.toString().trim() ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        border: Border.all(color: UcrColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(
                  radius: 18,
                  backgroundColor: _softBlue,
                  child: Icon(
                    Icons.check_circle_outline,
                    color: UcrColors.blue,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          color: _navy,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${_eventDate(data['dateTime'])} · Versión ${data['version'] ?? '—'}',
                        style: const TextStyle(
                          color: UcrColors.text,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _StatusChip(data['previousStatus']?.toString() ?? ''),
                const Icon(
                  Icons.arrow_forward,
                  size: 17,
                  color: UcrColors.blue,
                ),
                _StatusChip(data['newStatus']?.toString() ?? ''),
              ],
            ),
            if (note.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _softBlue,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SelectableText(
                  note,
                  style: const TextStyle(color: UcrColors.text, height: 1.5),
                ),
              ),
            ],
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: const Text(
                'Datos de auditoría',
                style: TextStyle(color: UcrColors.blue, fontSize: 13),
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(
                    'Identificador del usuario: ${data['userId'] ?? 'Sin registrar'}',
                    style: const TextStyle(color: UcrColors.text, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  final String title;
  final Widget child;
  const _Page({required this.title, required this.child});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: UcrColors.background,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: _navy,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          title: Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(height: 1, color: UcrColors.border),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(
              MediaQuery.sizeOf(context).width < 600 ? 14 : 28,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: child,
              ),
            ),
          ),
        ),
      );
}

class _DeclarationReader extends StatelessWidget {
  final String id;
  final Widget Function(Declaration) builder;
  const _DeclarationReader({required this.id, required this.builder});
  @override
  Widget build(BuildContext context) =>
      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('declarations')
            .doc(id)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return const _Message(
              'No se pudo cargar la declaración. Revisá tu conexión y los permisos de esta cuenta.',
            );
          if (!snapshot.hasData)
            return const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            );
          if (!snapshot.data!.exists)
            return const _Message('La declaración ya no está disponible.');
          return builder(Declaration.fromDoc(snapshot.data!));
        },
      );
}

class _Header extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? footer;
  final bool rounded;
  const _Header({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.footer,
    this.rounded = true,
  });
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: rounded ? BorderRadius.circular(20) : null,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF064E95), _navy],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.white, size: 24),
                const SizedBox(width: 10),
                const Text(
                  'DeclaraHorario',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              subtitle,
              style: const TextStyle(color: Color(0xFFD8EBFF), height: 1.5),
            ),
            if (footer != null) ...[const SizedBox(height: 16), footer!],
          ],
        ),
      );
}

class _Surface extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  const _Surface({
    required this.title,
    required this.icon,
    required this.child,
  });
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: UcrColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: UcrColors.blue, size: 23),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: _navy,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 30, color: UcrColors.border),
            child,
          ],
        ),
      );
}

class _Fields extends StatelessWidget {
  final List<(String, String)> fields;
  const _Fields(this.fields);
  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth >= 650
              ? (constraints.maxWidth - 32) / 2
              : constraints.maxWidth;
          return Wrap(
            spacing: 32,
            runSpacing: 18,
            children: fields
                .map(
                  (field) => SizedBox(
                    width: width,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          field.$1,
                          style: const TextStyle(
                            color: UcrColors.blue,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 5),
                        SelectableText(
                          field.$2.isEmpty ? 'Sin registrar' : field.$2,
                          style: const TextStyle(
                            color: UcrColors.text,
                            fontSize: 15,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          );
        },
      );
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip(this.status);
  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'FINALIZADA' => const Color(0xFF167E73),
      'DEVUELTA' => const Color(0xFF926100),
      'ANULADA' => const Color(0xFFAD3B45),
      _ => _navy,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        _status(status),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final String message;
  const _Message(this.message);
  @override
  Widget build(BuildContext context) => _Surface(
        title: 'Información',
        icon: Icons.info_outline,
        child: Text(
          message,
          style: const TextStyle(color: UcrColors.text, height: 1.5),
        ),
      );
}
