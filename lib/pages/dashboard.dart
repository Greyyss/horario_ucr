import '../theme/ucr_colors.dart';
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
  String _search = '';
  String _statusFilter = 'TODOS';
  bool _newestFirst = true;
  String _section = 'inicio';
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
  
  // Presentación institucional; las transiciones y permisos permanecen en los servicios.

  String _statusLabel(String status) => status.replaceAll('_', ' ');

  
Color _statusColor(String status) {
  switch (status) {
    case 'FINALIZADA':
      return const Color(0xFF167E73);
    case 'DEVUELTA':
  return const Color(0xFFD18A00);
    case 'ANULADA':
      return const Color(0xFFB54757);
    case 'BORRADOR':
      return const Color(0xFF64748B);
    default:
      return UcrColors.blue;
  }
}


  String _date(DateTime value) {
    final d = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}  ${two(d.hour)}:${two(d.minute)}';
  }

  void _help() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.help_outline, color: UcrColors.blue),
          SizedBox(width: 10),
          Text('Ayuda · DeclaraHorario'),
        ]),
        content: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 460),
          child: Text(
            'Este sistema permite crear y tramitar declaraciones de horario.\n\n'
            'En «Mis declaraciones» puede consultar el estado y realizar las acciones disponibles.\n\n'
            'Para consultar los movimientos de un trámite, utilice «Historial».\n\n'
            'Las opciones dependen de su rol institucional.',
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar'))],
      ),
    );
  }

Widget _summary(String label, int count, IconData icon, Color accent) {
  return Container(
    height: 145,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: UcrColors.blue,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: UcrColors.blue.withValues(alpha: 0.12),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(
              icon,
              color: Colors.white,
              size: 28,
            ),
            Text(
              '$count',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}


 
Widget _statusBadge(String status) {
  final color = _statusColor(status);

  final IconData icon;
  switch (status) {
    case 'FINALIZADA':
      icon = Icons.check_circle_outline;
      break;
    case 'DEVUELTA':
      icon = Icons.keyboard_return_rounded;
      break;
    case 'ANULADA':
      icon = Icons.cancel_outlined;
      break;
    case 'BORRADOR':
      icon = Icons.edit_note_outlined;
      break;
    default:
      icon = Icons.schedule_outlined;
  }

  return Container(
    padding: const EdgeInsets.symmetric(
      horizontal: 12,
      vertical: 8,
    ),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 15),
        const SizedBox(width: 7),
        Text(
          _statusLabel(status),
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ],
    ),
  );
}


  Widget _actionsFor(Declaration d, String uid) => Wrap(
    spacing: 7, runSpacing: 7,
    children: [
      if (role == 'declarante' && d.status == 'BORRADOR') ...[
        _action(d, 'validate', 'Validar', primary: true),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EditorPage(existing: d))),
          icon: const Icon(Icons.edit_outlined, size: 16), label: const Text('Editar')),
      ],
      if (role == 'declarante' && d.status == 'VALIDADA') _action(d, 'submit', 'Enviar a firma', primary: true),
      if (role == 'declarante' && d.status == 'PENDIENTE_FIRMA_DECLARANTE') _action(d, 'signOwner', 'Firmar bajo juramento', primary: true),
      if (role == 'declarante' && d.status == 'FIRMADA_POR_DECLARANTE') _action(d, 'route', 'Remitir al superior', primary: true),
      if (role == 'declarante' && d.status == 'DEVUELTA') _action(d, 'newVersion', 'Crear nueva versión', primary: true),
      if ((role == 'superior' || role == 'admin') && d.superiorId == uid && d.status == 'PENDIENTE_FIRMA_SUPERIOR') ...[
        _action(d, 'signSuperior', 'Aprobar y firmar', primary: true),
        _action(d, 'return', 'Devolver'),
      ],
      if ((role == 'rrhh' || role == 'admin') && d.status == 'FIRMADA_POR_SUPERIOR') _action(d, 'sendHr', 'Enviar a RRHH', primary: true),
      if ((role == 'rrhh' || role == 'admin') && d.status == 'ENVIADA_A_RRHH') _action(d, 'receive', 'Recibir', primary: true),
      if ((role == 'rrhh' || role == 'admin') && d.status == 'RECIBIDA_RRHH') _action(d, 'finish', 'Finalizar', primary: true),
      OutlinedButton.icon(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TimelinePage(id: d.id))),
        icon: const Icon(Icons.history, size: 16), label: const Text('Historial')),
      OutlinedButton.icon(
        onPressed: () => service.generatePdf(d),
        icon: const Icon(Icons.picture_as_pdf_outlined, size: 16), label: const Text('PDF')),
    ],
  );

  
Widget _tableHeader() => Container(
  padding: const EdgeInsets.symmetric(
    horizontal: 22,
    vertical: 17,
  ),
  decoration: const BoxDecoration(
    color: Color(0xFFF1F6FB),
    border: Border(
      bottom: BorderSide(color: UcrColors.border),
    ),
  ),
  child: const Row(
    children: [
      Expanded(
        flex: 4,
        child: Text(
          'DECLARACIÓN',
          style: TextStyle(
            color: UcrColors.blue,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      Expanded(
        flex: 2,
        child: Text(
          'PERÍODO',
          style: TextStyle(
            color: UcrColors.blue,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      Expanded(
        flex: 2,
        child: Text(
          'ESTADO',
          style: TextStyle(
            color: UcrColors.blue,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      Expanded(
        flex: 2,
        child: Text(
          'ACTUALIZACIÓN',
          style: TextStyle(
            color: UcrColors.blue,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  ),
);


  
Widget _tableRow(Declaration d, String uid) {
  return Container(
    padding: const EdgeInsets.symmetric(
      horizontal: 22,
      vertical: 20,
    ),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(
        bottom: BorderSide(
          color: UcrColors.border,
          width: 0.8,
        ),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F2FA),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.description_outlined,
                      color: UcrColors.blue,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d.ownerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: UcrColors.text,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          d.unit.isEmpty
                              ? 'Sin unidad especificada'
                              : d.unit,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                '${d.periodId} · V${d.version}',
                style: const TextStyle(
                  fontSize: 13,
                  color: UcrColors.text,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _statusBadge(d.status),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                _date(d.updatedAt),
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.only(left: 54),
          child: _actionsFor(d, uid),
        ),
      ],
    ),
  );
}

  
Widget _mobileRow(Declaration d, String uid) {
  return Container(
    padding: const EdgeInsets.all(18),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(
        bottom: BorderSide(color: UcrColors.border),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F2FA),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.description_outlined,
                color: UcrColors.blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                d.ownerName,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: UcrColors.text,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _statusBadge(d.status),
        const SizedBox(height: 12),
        Text(
          '${d.periodId} · Versión ${d.version}',
          style: const TextStyle(
            fontSize: 13,
            color: UcrColors.text,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Actualizado: ${_date(d.updatedAt)}',
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 14),
        _actionsFor(d, uid),
      ],
    ),
  );
}

  Widget _action(Declaration d, String key, String label, {bool primary = false}) {
    final handler = () {
      if (key == 'return') {
        askReturn(d);
      } else if (key == 'signOwner') {
        askSign(d);
      } else {
        act(d, key);
      }
    };
    return primary
        ? FilledButton(onPressed: handler, child: Text(label))
        : OutlinedButton(onPressed: handler, child: Text(label));
  }

  Future<void> _resetPassword() async {
    final email = FirebaseAuth.instance.currentUser?.email;
    if (email == null || email.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La cuenta no tiene correo registrado.')));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cambiar contraseña'),
        content: Text('¿Enviar un enlace para cambiar la contraseña a $email?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enviar enlace')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Revisá tu correo para cambiar la contraseña.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo enviar el enlace: $e')));
    }
  }

  Widget _profileMenu() {
    final user = FirebaseAuth.instance.currentUser;
    final name = (profile['name'] ?? user?.displayName ?? 'Usuario').toString();
    final email = (profile['email'] ?? user?.email ?? '').toString();
    final id = (profile['identification'] ?? '').toString();
    return PopupMenuButton<String>(
      tooltip: 'Mi perfil',
      offset: const Offset(0, 10),
      constraints: const BoxConstraints(minWidth: 270, maxWidth: 345),
      onSelected: (value) {
        if (value == 'password') _resetPassword();
        if (value == 'logout') FirebaseAuth.instance.signOut();
        if (value == 'admin') Navigator.push(context,
          MaterialPageRoute(builder: (_) => const AdminPage()));
      },
      itemBuilder: (ctx) => [
        PopupMenuItem<String>(enabled: false, child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            const CircleAvatar(radius: 25, backgroundColor: Color(0xFFEAF3FA),
              child: Icon(Icons.person_outline, color: UcrColors.blue, size: 29)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.bold, color: UcrColors.text)),
              const SizedBox(height: 4),
              Text(email, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
              Text('Rol: $role', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
            ])),
          ]),
        )),
        if (id.isNotEmpty) PopupMenuItem<String>(enabled: false,
          child: Text('Identificación: $id', style: const TextStyle(color: UcrColors.text))),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'password', child: ListTile(
          contentPadding: EdgeInsets.zero, leading: Icon(Icons.key_outlined, color: UcrColors.blue),
          title: Text('Cambiar contraseña'))),
        if (role == 'admin') const PopupMenuItem(value: 'admin', child: ListTile(
          contentPadding: EdgeInsets.zero, leading: Icon(Icons.admin_panel_settings_outlined),
          title: Text('Administración'))),
        const PopupMenuItem(value: 'logout', child: ListTile(
          contentPadding: EdgeInsets.zero, leading: Icon(Icons.logout, color: Color(0xFFB42335)),
          title: Text('Cerrar sesión', style: TextStyle(color: Color(0xFFB42335))))),
      ],
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(radius: 19, backgroundColor: UcrColors.blue,
            child: Icon(Icons.person_outline, color: Colors.white)),
          SizedBox(width: 5),
          Icon(Icons.keyboard_arrow_down, color: UcrColors.blue),
        ]),
      ),
    );
  }

  Widget _quickCard(String label, String subtitle, IconData icon, VoidCallback action) {
    return Material(
      color: UcrColors.blue,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: action,
        borderRadius: BorderRadius.circular(13),
        hoverColor: Colors.white.withValues(alpha: 0.12),
        child: SizedBox(
          height: 172,
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, color: Colors.white, size: 35),
              const Spacer(),
              Text(label, style: const TextStyle(color: Colors.white,
                fontSize: 19, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(color: Color(0xFFE0F1FF), fontSize: 12)),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _chooseHistory(List<Declaration> list) async {
    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Todavía no hay declaraciones para consultar.')));
      return;
    }
    if (list.length == 1) {
      await Navigator.push(context, MaterialPageRoute(
        builder: (_) => TimelinePage(id: list.first.id)));
      return;
    }
    final selected = await showDialog<String>(context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Seleccione una declaración'),
        content: SizedBox(width: 480, height: 350, child: ListView.builder(
          itemCount: list.length,
          itemBuilder: (_, i) {
            final d = list[i];
            return ListTile(
              leading: const Icon(Icons.history, color: UcrColors.blue),
              title: Text(d.ownerName),
              subtitle: Text('${d.periodId} · Versión ${d.version} · ${_statusLabel(d.status)}'),
              onTap: () => Navigator.pop(ctx, d.id),
            );
          },
        )),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar'))],
      ));
    if (selected != null && mounted) {
      await Navigator.push(context, MaterialPageRoute(
        builder: (_) => TimelinePage(id: selected)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final width = MediaQuery.sizeOf(context).width;
    return Scaffold(
      backgroundColor: UcrColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: UcrColors.blue,
        elevation: 0,
        toolbarHeight: width < 600 ? 78 : 100,
        titleSpacing: 16,
        title: Align(alignment: Alignment.centerLeft,
          child: Image.asset('assets/images/logo_declara_ucr.png',
            height: width < 600 ? 62 : 85, fit: BoxFit.contain,
            alignment: Alignment.centerLeft)),
        actions: [_profileMenu(), const SizedBox(width: 8)],
        bottom: const PreferredSize(preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: UcrColors.border)),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Ayuda',
        onPressed: _help,
        backgroundColor: UcrColors.blue,
        foregroundColor: Colors.white,
        child: const Icon(Icons.help_outline),
      ),
      body: loading
        ? const Center(child: CircularProgressIndicator())
        : Center(child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: StreamBuilder<List<Declaration>>(
              stream: role == 'declarante' ? service.watchMine() :
                (role == 'superior' ? service.watchAssigned() : service.watchAll()),
              builder: (ctx, snapshot) {
                final list = snapshot.data?.where((d) => role == 'admin' ||
                  role == 'rrhh' || role == 'declarante' || d.superiorId == uid)
                  .toList() ?? <Declaration>[];
                final pending = list.where((d) =>
                  d.status != 'FINALIZADA' && d.status != 'ANULADA').length;
                final finished = list.where((d) => d.status == 'FINALIZADA').length;
                final statuses = list.map((d) => d.status).toSet().toList()..sort();
                final selectedStatus = _statusFilter == 'TODOS' || statuses.contains(_statusFilter)
                  ? _statusFilter : 'TODOS';
                final filtered = list.where((d) {
                  final query = _search.trim().toLowerCase();
                  final matchesQuery = query.isEmpty ||
                    d.ownerName.toLowerCase().contains(query) ||
                    d.periodId.toLowerCase().contains(query) ||
                    d.unit.toLowerCase().contains(query) ||
                    d.status.toLowerCase().contains(query);
                  return matchesQuery && (selectedStatus == 'TODOS' || d.status == selectedStatus);
                }).toList()
                  ..sort((a, b) => _newestFirst
                    ? b.updatedAt.compareTo(a.updatedAt)
                    : a.updatedAt.compareTo(b.updatedAt));
                final compact = width < 780;
                return ListView(
                  padding: EdgeInsets.symmetric(horizontal: width < 600 ? 14 : 24, vertical: 24),
                  children: [
                    if (_section != 'inicio') ...[
                      Align(alignment: Alignment.centerLeft, child: TextButton.icon(
                        onPressed: () => setState(() => _section = 'inicio'),
                        icon: const Icon(Icons.arrow_back), label: const Text('Volver al inicio'))),
                      const SizedBox(height: 14),
                    ],
                    if (_section == 'inicio') ...[
                      const SizedBox(height: 16),
                      Text('Bienvenido a DeclaraUCR',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800, color: UcrColors.text)),
                      const SizedBox(height: 8),
                      const Text('Seleccione la opción que desea realizar.',
                        style: TextStyle(color: Color(0xFF64748B), fontSize: 16)),
                      const SizedBox(height: 32),
                      LayoutBuilder(builder: (context, constraints) {
                        final available = constraints.maxWidth;
                        final columns = available >= 760 ? 3 : available >= 510 ? 2 : 1;
                        final cardWidth = (available - (columns - 1) * 16) / columns;
                        return Wrap(spacing: 16, runSpacing: 16,
                          alignment: WrapAlignment.center, children: [
                          if (role == 'declarante') SizedBox(width: cardWidth,
                            child: _quickCard('Nueva declaración', 'Registrar un nuevo horario',
                              Icons.note_add_outlined, () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => const EditorPage())))),
                          SizedBox(width: cardWidth,
                            child: _quickCard('Mis declaraciones', 'Consultar y gestionar trámites',
                              Icons.description_outlined,
                              () => setState(() => _section = 'declaraciones'))),
                          SizedBox(width: cardWidth,
                            child: _quickCard('Seguimiento', 'Ver el historial de movimientos',
                              Icons.track_changes_outlined, () => _chooseHistory(list))),
                          if (role == 'admin') SizedBox(width: cardWidth,
                            child: _quickCard('Administración', 'Gestionar el sistema',
                              Icons.admin_panel_settings_outlined, () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => const AdminPage())))),
                        ]);
                      }),
                      const SizedBox(height: 34),
                      buildInstitutionalFooter(),
                    ] else ...[
                      Text('Mis declaraciones',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800, color: UcrColors.text)),
                      const SizedBox(height: 8),
                      const Text('Consulte, filtre y gestione sus trámites.',
                        style: TextStyle(color: Color(0xFF64748B), fontSize: 15)),
                      const SizedBox(height: 20),
                      LayoutBuilder(builder: (context, constraints) {
                        final columns = constraints.maxWidth >= 760 ? 3 :
                          constraints.maxWidth >= 490 ? 2 : 1;
                        final cardWidth = (constraints.maxWidth - (columns - 1) * 12) / columns;
                        return Wrap(spacing: 12, runSpacing: 12, children: [
                          SizedBox(width: cardWidth, child: _summary('Total de declaraciones',
                            list.length, Icons.description_outlined, UcrColors.blue)),
                          SizedBox(width: cardWidth, child: _summary('Pendientes',
                            pending, Icons.schedule_outlined, const Color(0xFFE58A00))),
                          SizedBox(width: cardWidth, child: _summary('Finalizadas',
                            finished, Icons.check_circle_outline, const Color(0xFF28995B))),
                        ]);
                      }),
                      const SizedBox(height: 24),
                      Container(
                        decoration: BoxDecoration(color: Colors.white,
                          border: Border.all(color: UcrColors.border), borderRadius: BorderRadius.circular(12)),
                        clipBehavior: Clip.antiAlias,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Padding(padding: const EdgeInsets.all(18), child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Row(children: [
                                Icon(Icons.folder_open_outlined, color: UcrColors.blue, size: 22),
                                SizedBox(width: 9),
                                Text('Trámites registrados', style: TextStyle(fontSize: 19,
                                  fontWeight: FontWeight.w700, color: UcrColors.text)),
                              ]),
                              const SizedBox(height: 6),
                              Text('${filtered.length} de ${list.length} declaraciones',
                                style: const TextStyle(color: Color(0xFF687789), fontSize: 12)),
                              const SizedBox(height: 15),
                              Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  SizedBox(width: compact ? 260 : 330, child: TextField(
                                    onChanged: (value) => setState(() => _search = value),
                                    decoration: const InputDecoration(
                                      isDense: true, prefixIcon: Icon(Icons.search),
                                      hintText: 'Buscar por nombre, período o unidad',
                                      border: OutlineInputBorder()),
                                  )),
                                  SizedBox(width: 210, child: DropdownButtonFormField<String>(
                                    initialValue: selectedStatus,
                                    isExpanded: true,
                                    decoration: const InputDecoration(isDense: true,
                                      labelText: 'Estado', border: OutlineInputBorder()),
                                    items: [
                                      const DropdownMenuItem(value: 'TODOS', child: Text('Todos los estados')),
                                      for (final status in statuses)
                                        DropdownMenuItem(value: status, child: Text(_statusLabel(status),
                                          overflow: TextOverflow.ellipsis)),
                                    ],
                                    onChanged: (value) => setState(() => _statusFilter = value ?? 'TODOS'),
                                  )),
                                  OutlinedButton.icon(
                                    onPressed: () => setState(() => _newestFirst = !_newestFirst),
                                    icon: Icon(_newestFirst ? Icons.arrow_downward : Icons.arrow_upward, size: 17),
                                    label: Text(_newestFirst ? 'Más recientes' : 'Más antiguos')),
                                ]),
                            ]),
                          ),
                          if (snapshot.hasError)
                            _message('No fue posible cargar las declaraciones: ${snapshot.error}')
                          else if (!snapshot.hasData)
                            const Padding(padding: EdgeInsets.all(36), child: Center(child: CircularProgressIndicator()))
                          else if (list.isEmpty)
                            _message('No hay declaraciones disponibles para este usuario.')
                          else if (filtered.isEmpty)
                            _message('No hay trámites que coincidan con los filtros.')
                          else ...[
                            if (!compact) _tableHeader(),
                            for (final d in filtered)
                              if (compact) _mobileRow(d, uid) else _tableRow(d, uid),
                          ],
                        ]),
                      ),
                      const SizedBox(height: 24),
                      buildInstitutionalFooter(),
                    ],
                    const SizedBox(height: 72),
                  ],
                );
              },
            ),
          )),
    );
  }

  Widget buildInstitutionalFooter() {
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 36),
    padding: const EdgeInsets.symmetric(
      horizontal: 20,
      vertical: 24,
    ),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(
        top: BorderSide(
          color: Color(0xFF005DA4),
          width: 2,
        ),
      ),
    ),
    child: const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '© 2026 · DeclaraUCR · Universidad de Costa Rica',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF327FA5),
            fontSize: 14,
          ),
        ),
        SizedBox(height: 6),
        Text(
          'Sistema de Declaración Jurada de Horarios',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF64748B),
            fontSize: 12,
          ),
        ),
        SizedBox(height: 6),
        Text(
          'Versión 1.0.0',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF279D92),
            fontSize: 12,
          ),
        ),
      ],
    ),
  );
}

  Widget _message(String message) => Container(
    padding: const EdgeInsets.all(26),
    decoration: BoxDecoration(color: Colors.white, border: Border.all(color: UcrColors.border), borderRadius: BorderRadius.circular(10)),
    child: Text(message, style: const TextStyle(color: UcrColors.text)),
  );
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
        backgroundColor: UcrColors.background,
        appBar: AppBar(
            backgroundColor: UcrColors.blue,
            foregroundColor: Colors.white,
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
      backgroundColor: UcrColors.background,
      appBar: AppBar(
        backgroundColor: UcrColors.blue,
        foregroundColor: Colors.white,
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
      backgroundColor: UcrColors.background,
      appBar: AppBar(backgroundColor: UcrColors.blue, foregroundColor: Colors.white, title: const Text('Historial y auditoría')),
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
