import '../theme/ucr_colors.dart';
import 'admin_page.dart';
import 'dart:convert';
import 'dart:async';
import '../services/websocket_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/declaration.dart';
import '../services/declaration_service.dart';
import '../services/validation_service.dart';
import '../services/personal_data_validator.dart';

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
  StreamSubscription<dynamic>? _socketSubscription;
  final List<({String message, DateTime receivedAt, bool read})> _notices = [];
  int get _unreadCount => _notices.where((notice) => !notice.read).length;

  void _openNotifications() {
    setState(() {
      for (var i = 0; i < _notices.length; i++) {
        final notice = _notices[i];
        _notices[i] = (
          message: notice.message,
          receivedAt: notice.receivedAt,
          read: true
        );
      }
    });
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.notifications_outlined, color: UcrColors.blue),
          SizedBox(width: 10),
          Text('Notificaciones'),
        ]),
        content: SizedBox(
          width: 420,
          child: _notices.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Text(
                      'Todavía no recibiste notificaciones en esta sesión.'),
                )
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 380),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _notices.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final notice = _notices[index];
                      final time = notice.receivedAt;
                      final dateText = '${time.day.toString().padLeft(2, '0')}/'
                          '${time.month.toString().padLeft(2, '0')}/'
                          '${time.year}  '
                          '${time.hour.toString().padLeft(2, '0')}:'
                          '${time.minute.toString().padLeft(2, '0')}';
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 5),
                        leading: const Icon(Icons.info_outline,
                            color: UcrColors.blue),
                        title: Text(notice.message),
                        subtitle: Text(dateText),
                      );
                    },
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Widget _notificationBell() => IconButton(
        tooltip:
            'Notificaciones${_unreadCount > 0 ? ' ($_unreadCount nuevas)' : ''}',
        onPressed: _openNotifications,
        icon: Badge(
          isLabelVisible: _unreadCount > 0,
          label: Text(_unreadCount > 99 ? '99+' : '$_unreadCount'),
          child: const Icon(Icons.notifications_outlined),
        ),
      );

  final service = DeclarationService();
  final Set<String> _pdfBusy = {};
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

      _socketSubscription = webSocketService.messages?.listen((message) {
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
            final notificationText = text?.toString() ?? 'Nueva notificación';
            setState(() {
              _notices.insert(0, (
                message: notificationText,
                receivedAt: DateTime.now(),
                read: false,
              ));
              if (_notices.length > 100) _notices.removeLast();
            });
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
    _socketSubscription?.cancel();
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

  Future<void> _runPdf(Declaration d, String action) async {
    if (_pdfBusy.contains(d.id)) return;

    setState(() => _pdfBusy.add(d.id));

    try {
      switch (action) {
        case 'archive':
          final alreadyExists = await service.archivePdf(d);

          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                alreadyExists
                    ? 'El PDF ya estaba archivado. Se conservó el original.'
                    : 'PDF archivado correctamente.',
              ),
            ),
          );
          break;

        case 'open':
          await service.openArchivedPdf(d);
          break;

        case 'preview':
          await service.generatePdf(d);
          break;

        default:
          throw StateError('Acción de PDF desconocida.');
      }
    } catch (error) {
      if (!mounted) return;

      final message =
          error is StateError ? error.message.toString() : error.toString();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo completar la operación: $message'),
          duration: const Duration(seconds: 8),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _pdfBusy.remove(d.id));
      }
    }
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
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar'))
        ],
      ),
    );
  }

  Widget _summary(String label, int count, IconData icon, Color accent) {
    final Color backgroundColor = switch (label) {
      'Total de declaraciones' => const Color(0xFFEAF4FF),
      'Pendientes' => const Color(0xFFF0F8FF),
      'Finalizadas' => const Color(0xFFF0F8FB),
      _ => const Color(0xFFF6F9FD),
    };

    return Container(
      height: 78,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: accent.withValues(alpha: 0.38), width: 1.35),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: accent,
            child: Text(
              '$count',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 23,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF142B50),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
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
        spacing: 7,
        runSpacing: 7,
        children: [
          if (role == 'declarante' && d.status == 'BORRADOR') ...[
            _action(d, 'validate', 'Validar', primary: true),
            OutlinedButton.icon(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => EditorPage(existing: d))),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Editar')),
          ],
          if (role == 'declarante' && d.status == 'VALIDADA')
            _action(d, 'submit', 'Enviar a firma', primary: true),
          if (role == 'declarante' && d.status == 'PENDIENTE_FIRMA_DECLARANTE')
            _action(d, 'signOwner', 'Firmar bajo juramento', primary: true),
          if (role == 'declarante' && d.status == 'FIRMADA_POR_DECLARANTE')
            _action(d, 'route', 'Remitir al superior', primary: true),
          if (role == 'declarante' && d.status == 'DEVUELTA')
            _action(d, 'newVersion', 'Crear nueva versión', primary: true),
          if ((role == 'superior' || role == 'admin') &&
              d.superiorId == uid &&
              d.status == 'PENDIENTE_FIRMA_SUPERIOR') ...[
            _action(d, 'signSuperior', 'Aprobar y firmar', primary: true),
            _action(d, 'return', 'Devolver'),
          ],
          if ((role == 'rrhh' || role == 'admin') &&
              d.status == 'FIRMADA_POR_SUPERIOR')
            _action(d, 'sendHr', 'Enviar a RRHH', primary: true),
          if ((role == 'rrhh' || role == 'admin') &&
              d.status == 'ENVIADA_A_RRHH')
            _action(d, 'receive', 'Recibir', primary: true),
          if ((role == 'rrhh' || role == 'admin') &&
              d.status == 'RECIBIDA_RRHH')
            _action(d, 'finish', 'Finalizar', primary: true),
          OutlinedButton.icon(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => TimelinePage(id: d.id))),
              icon: const Icon(Icons.history, size: 16),
              label: const Text('Historial')),
          if (d.status != 'FINALIZADA')
            OutlinedButton.icon(
              onPressed:
                  _pdfBusy.contains(d.id) ? null : () => _runPdf(d, 'preview'),
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
              label: const Text('Vista previa PDF'),
            ),
          if (d.status == 'FINALIZADA' && (role == 'rrhh' || role == 'admin'))
            OutlinedButton.icon(
              onPressed:
                  _pdfBusy.contains(d.id) ? null : () => _runPdf(d, 'archive'),
              icon: const Icon(Icons.cloud_upload_outlined, size: 16),
              label: const Text('Archivar PDF'),
            ),
          if (d.status == 'FINALIZADA')
            OutlinedButton.icon(
              onPressed:
                  _pdfBusy.contains(d.id) ? null : () => _runPdf(d, 'open'),
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
              label: const Text('Abrir PDF archivado'),
            ),
          if (_pdfBusy.contains(d.id))
            const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
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
                            d.unit.isEmpty ? 'Sin unidad especificada' : d.unit,
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

  Widget _action(Declaration d, String key, String label,
      {bool primary = false}) {
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
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('La cuenta no tiene correo registrado.')));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cambiar contraseña'),
        content: Text('¿Enviar un enlace para cambiar la contraseña a $email?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enviar enlace')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Revisá tu correo para cambiar la contraseña.')));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
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
        if (value == 'admin')
          Navigator.push(
              context, MaterialPageRoute(builder: (_) => const AdminPage()));
      },
      itemBuilder: (ctx) => [
        PopupMenuItem<String>(
            enabled: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                const CircleAvatar(
                    radius: 25,
                    backgroundColor: Color(0xFFEAF3FA),
                    child: Icon(Icons.person_outline,
                        color: UcrColors.blue, size: 29)),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: UcrColors.text)),
                      const SizedBox(height: 4),
                      Text(email,
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF64748B))),
                      Text('Rol: $role',
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF64748B))),
                    ])),
              ]),
            )),
        if (id.isNotEmpty)
          PopupMenuItem<String>(
              enabled: false,
              child: Text('Identificación: $id',
                  style: const TextStyle(color: UcrColors.text))),
        const PopupMenuDivider(),
        const PopupMenuItem(
            value: 'password',
            child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.key_outlined, color: UcrColors.blue),
                title: Text('Cambiar contraseña'))),
        if (role == 'admin')
          const PopupMenuItem(
              value: 'admin',
              child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.admin_panel_settings_outlined),
                  title: Text('Administración'))),
        const PopupMenuItem(
            value: 'logout',
            child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.logout, color: Color(0xFFB42335)),
                title: Text('Cerrar sesión',
                    style: TextStyle(color: Color(0xFFB42335))))),
      ],
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(
              radius: 19,
              backgroundColor: UcrColors.blue,
              child: Icon(Icons.person_outline, color: Colors.white)),
          SizedBox(width: 5),
          Icon(Icons.keyboard_arrow_down, color: UcrColors.blue),
        ]),
      ),
    );
  }

  Widget _quickCard(
      String label, String subtitle, IconData icon, VoidCallback action) {
    return Material(
      color: const Color(0xFFE5F3FF),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: action,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 184,
          padding: const EdgeInsets.all(21),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFCEE6F9)),
            gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFEDF8FF), Color(0xFFC8E9FF)]),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(
                radius: 26,
                backgroundColor: const Color(0xFFD0E9FC),
                child: Icon(icon, color: const Color(0xFF0067B7), size: 28)),
            const Spacer(),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Color(0xFF07194D),
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            Text(subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF4C6F9A), fontSize: 12)),
          ]),
        ),
      ),
    );
  }

  String get _roleName {
    switch (role) {
      case 'superior':
        return 'Superior jerárquico';
      case 'rrhh':
        return 'Recursos Humanos';
      case 'admin':
        return 'Administrador';
      default:
        return 'Declarante';
    }
  }

  String get _displayName {
    final raw = (profile['name'] ??
            FirebaseAuth.instance.currentUser?.displayName ??
            'Usuario')
        .toString()
        .trim();
    return raw.isEmpty ? 'Usuario' : raw.split(RegExp(r'\s+')).first;
  }

  Widget _welcomeBanner() => Container(
        height: 236,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: const Color(0xFFD8E8F5),
          ),
          color: const Color(0xFFF5FAFF),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;

            return Stack(
              children: [
                // Fotografía real de la UCR

                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 0,
                  width: width * 0.57,
                  child: Image.asset(
                    'assets/images/ucr_fondo.png',
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                  ),
                ),

                // Curvas azules sobre la fotografía
                Positioned.fill(
                  child: CustomPaint(
                    painter: _WelcomeCurvePainter(),
                  ),
                ),

                // Textos originales de bienvenida
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'B I E N V E N I D A',
                        style: TextStyle(
                          color: Color(0xFF496E9E),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 42,
                          height: 1.1,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF07194D),
                        ),
                      ),
                      const SizedBox(height: 9),
                      const Text(
                        'Sistema de declaración de horarios',
                        style: TextStyle(
                          color: Color(0xFF41699C),
                          fontSize: 19,
                        ),
                      ),
                      const SizedBox(height: 9),
                      const Text(
                        'Gestioná tus declaraciones de forma sencilla y segura.',
                        style: TextStyle(
                          color: Color(0xFF5476A4),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        width: 55,
                        height: 3,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2795F0),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      );

  Widget _sideItem(String label, IconData icon, VoidCallback onTap,
      {bool selected = false}) {
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        child: Material(
            color: selected ? const Color(0xFF0B70C2) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            child: InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: onTap,
                child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 15, vertical: 14),
                    child: Row(children: [
                      Icon(icon, color: Colors.white, size: 23),
                      const SizedBox(width: 16),
                      Expanded(
                          child: Text(label,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 14)))
                    ])))));
  }

  Widget _sidebar(List<Declaration> list) {
    return Container(
      width: 232,
      decoration: const BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF064E95), Color(0xFF073A77)])),
      child: Column(children: [
        const SizedBox(height: 20),
        _sideItem('Inicio', Icons.home_outlined,
            () => setState(() => _section = 'inicio'),
            selected: _section == 'inicio'),
        if (role == 'declarante')
          _sideItem(
              'Nueva declaración',
              Icons.note_add_outlined,
              () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const EditorPage()))),
        _sideItem(
            role == 'declarante' ? 'Mis declaraciones' : 'Declaraciones',
            Icons.description_outlined,
            () => setState(() => _section = 'declaraciones'),
            selected: _section == 'declaraciones'),
        _sideItem('Seguimiento', Icons.bar_chart_outlined,
            () => _chooseHistory(list)),
        if (role == 'admin')
          _sideItem(
              'Administración',
              Icons.admin_panel_settings_outlined,
              () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const AdminPage()))),
        const Divider(color: Color(0xFF3978AE), indent: 22, endIndent: 22),
        _sideItem('Ayuda', Icons.help_outline, _help),
        _sideItem('Cerrar sesión', Icons.logout,
            () => FirebaseAuth.instance.signOut()),
        const Spacer(),
        const Padding(
            padding: EdgeInsets.all(20),
            child: Text('Universidad de Costa Rica',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 15))),
      ]),
    );
  }

  Future<void> _chooseHistory(List<Declaration> list) async {
    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Todavía no hay declaraciones para consultar.')));
      return;
    }
    if (list.length == 1) {
      await Navigator.push(context,
          MaterialPageRoute(builder: (_) => TimelinePage(id: list.first.id)));
      return;
    }
    final selected = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('Seleccione una declaración'),
              content: SizedBox(
                  width: 480,
                  height: 350,
                  child: ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final d = list[i];
                      return ListTile(
                        leading:
                            const Icon(Icons.history, color: UcrColors.blue),
                        title: Text(d.ownerName),
                        subtitle: Text(
                            '${d.periodId} · Versión ${d.version} · ${_statusLabel(d.status)}'),
                        onTap: () => Navigator.pop(ctx, d.id),
                      );
                    },
                  )),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancelar'))
              ],
            ));
    if (selected != null && mounted) {
      await Navigator.push(context,
          MaterialPageRoute(builder: (_) => TimelinePage(id: selected)));
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
        title: Align(
            alignment: Alignment.centerLeft,
            child: Image.asset('assets/images/logo_declara_ucr.png',
                height: width < 600 ? 55 : 70,
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft)),
        actions: [
          if (width >= 650)
            Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Center(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                      Text(_displayName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                      Text(_roleName,
                          style: const TextStyle(
                              color: Color(0xFF5876A0), fontSize: 12)),
                    ]))),
          _notificationBell(),
          _profileMenu(),
          const SizedBox(width: 8),
        ],
        bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
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
          : StreamBuilder<List<Declaration>>(
              stream: role == 'declarante'
                  ? service.watchMine()
                  : (role == 'superior'
                      ? service.watchAssigned()
                      : service.watchAll()),
              builder: (ctx, snapshot) {
                final list = snapshot.data
                        ?.where((d) =>
                            role == 'admin' ||
                            role == 'rrhh' ||
                            role == 'declarante' ||
                            d.superiorId == uid)
                        .toList() ??
                    <Declaration>[];
                final pending = list
                    .where((d) =>
                        d.status != 'FINALIZADA' && d.status != 'ANULADA')
                    .length;
                final finished =
                    list.where((d) => d.status == 'FINALIZADA').length;
                final statuses = list.map((d) => d.status).toSet().toList()
                  ..sort();
                final selectedStatus =
                    _statusFilter == 'TODOS' || statuses.contains(_statusFilter)
                        ? _statusFilter
                        : 'TODOS';
                final filtered = list.where((d) {
                  final query = _search.trim().toLowerCase();
                  final matchesQuery = query.isEmpty ||
                      d.ownerName.toLowerCase().contains(query) ||
                      d.periodId.toLowerCase().contains(query) ||
                      d.unit.toLowerCase().contains(query) ||
                      d.status.toLowerCase().contains(query);
                  return matchesQuery &&
                      (selectedStatus == 'TODOS' || d.status == selectedStatus);
                }).toList()
                  ..sort((a, b) => _newestFirst
                      ? b.updatedAt.compareTo(a.updatedAt)
                      : a.updatedAt.compareTo(b.updatedAt));
                final compact = width < 780;
                final content = ListView(
                  padding: EdgeInsets.symmetric(
                      horizontal: width < 600 ? 14 : 24, vertical: 24),
                  children: [
                    if (width < 920) ...[
                      SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(children: [
                            TextButton.icon(
                                onPressed: () =>
                                    setState(() => _section = 'inicio'),
                                icon: const Icon(Icons.home_outlined),
                                label: const Text('Inicio')),
                            if (role == 'declarante')
                              TextButton.icon(
                                  onPressed: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) => const EditorPage())),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Nueva declaración')),
                            TextButton.icon(
                                onPressed: () =>
                                    setState(() => _section = 'declaraciones'),
                                icon: const Icon(Icons.description_outlined),
                                label: const Text('Declaraciones')),
                            TextButton.icon(
                                onPressed: () => _chooseHistory(list),
                                icon: const Icon(Icons.history),
                                label: const Text('Seguimiento')),
                          ])),
                      const SizedBox(height: 12),
                    ],
                    if (_section != 'inicio') ...[
                      Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                              onPressed: () =>
                                  setState(() => _section = 'inicio'),
                              icon: const Icon(Icons.arrow_back),
                              label: const Text('Volver al inicio'))),
                      const SizedBox(height: 14),
                    ],
                    if (_section == 'inicio') ...[
                      _welcomeBanner(),
                      const SizedBox(height: 18),
                      LayoutBuilder(builder: (context, constraints) {
                        final available = constraints.maxWidth;
                        final columns = available >= 720
                            ? 4
                            : available >= 480
                                ? 2
                                : 1;
                        final cardWidth =
                            (available - (columns - 1) * 12) / columns;
                        final draft =
                            list.where((d) => d.status == 'BORRADOR').length;
                        return Wrap(spacing: 12, runSpacing: 12, children: [
                          SizedBox(
                              width: cardWidth,
                              child: _summary(
                                  'Total de declaraciones',
                                  list.length,
                                  Icons.description_outlined,
                                  const Color(0xFF005DA4))),
                          SizedBox(
                              width: cardWidth,
                              child: _summary(
                                  'Pendientes',
                                  pending,
                                  Icons.schedule_outlined,
                                  const Color(0xFF2B91D4))),
                          SizedBox(
                              width: cardWidth,
                              child: _summary(
                                  'Finalizadas',
                                  finished,
                                  Icons.check_circle_outline,
                                  const Color(0xFF0087B9))),
                          SizedBox(
                              width: cardWidth,
                              child: _summary(
                                  'Borrador',
                                  draft,
                                  Icons.edit_note_outlined,
                                  const Color(0xFF416C9E))),
                        ]);
                      }),
                      const SizedBox(height: 24),
                      const Text('Accesos principales',
                          style: TextStyle(
                              color: Color(0xFF07194D),
                              fontSize: 24,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      const Text('Seleccioná la opción que deseás realizar.',
                          style: TextStyle(
                              color: Color(0xFF5476A4), fontSize: 14)),
                      const SizedBox(height: 12),
                      LayoutBuilder(builder: (context, constraints) {
                        final available = constraints.maxWidth;
                        final columns = available >= 760
                            ? 3
                            : available >= 510
                                ? 2
                                : 1;
                        final cardWidth =
                            (available - (columns - 1) * 16) / columns;
                        return Wrap(
                            spacing: 16,
                            runSpacing: 16,
                            alignment: WrapAlignment.center,
                            children: [
                              if (role == 'declarante')
                                SizedBox(
                                    width: cardWidth,
                                    child: _quickCard(
                                        'Nueva declaración',
                                        'Registrar un nuevo horario',
                                        Icons.note_add_outlined,
                                        () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                                builder: (_) =>
                                                    const EditorPage())))),
                              SizedBox(
                                  width: cardWidth,
                                  child: _quickCard(
                                      'Mis declaraciones',
                                      'Consultar y gestionar trámites',
                                      Icons.description_outlined,
                                      () => setState(
                                          () => _section = 'declaraciones'))),
                              SizedBox(
                                  width: cardWidth,
                                  child: _quickCard(
                                      'Seguimiento',
                                      'Ver el historial de movimientos',
                                      Icons.track_changes_outlined,
                                      () => _chooseHistory(list))),
                              if (role == 'admin')
                                SizedBox(
                                    width: cardWidth,
                                    child: _quickCard(
                                        'Administración',
                                        'Gestionar el sistema',
                                        Icons.admin_panel_settings_outlined,
                                        () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                                builder: (_) =>
                                                    const AdminPage())))),
                            ]);
                      }),
                      const SizedBox(height: 34),
                      buildInstitutionalFooter(),
                    ] else ...[
                      Text(
                          role == 'declarante'
                              ? 'Mis declaraciones'
                              : 'Declaraciones',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: UcrColors.text)),
                      const SizedBox(height: 8),
                      const Text('Consulte, filtre y gestione sus trámites.',
                          style: TextStyle(
                              color: Color(0xFF64748B), fontSize: 15)),
                      const SizedBox(height: 20),
                      LayoutBuilder(builder: (context, constraints) {
                        final columns = constraints.maxWidth >= 760
                            ? 3
                            : constraints.maxWidth >= 490
                                ? 2
                                : 1;
                        final cardWidth =
                            (constraints.maxWidth - (columns - 1) * 12) /
                                columns;
                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            SizedBox(
                              width: cardWidth,
                              child: _summary(
                                'Total de declaraciones',
                                list.length,
                                Icons.description_outlined,
                                const Color(0xFF005DA4),
                              ),
                            ),
                            SizedBox(
                              width: cardWidth,
                              child: _summary(
                                'Pendientes',
                                pending,
                                Icons.schedule_outlined,
                                const Color(0xFF248BD2),
                              ),
                            ),
                            SizedBox(
                              width: cardWidth,
                              child: _summary(
                                'Finalizadas',
                                finished,
                                Icons.check_circle_outline,
                                const Color(0xFF426F9F),
                              ),
                            ),
                          ],
                        );
                      }),
                      const SizedBox(height: 24),
                      Container(
                        decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: UcrColors.border),
                            borderRadius: BorderRadius.circular(12)),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(18),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Row(children: [
                                        Icon(Icons.folder_open_outlined,
                                            color: UcrColors.blue, size: 22),
                                        SizedBox(width: 9),
                                        Text('Trámites registrados',
                                            style: TextStyle(
                                                fontSize: 19,
                                                fontWeight: FontWeight.w700,
                                                color: UcrColors.text)),
                                      ]),
                                      const SizedBox(height: 6),
                                      Text(
                                          '${filtered.length} de ${list.length} declaraciones',
                                          style: const TextStyle(
                                              color: Color(0xFF687789),
                                              fontSize: 12)),
                                      const SizedBox(height: 15),
                                      Wrap(
                                          spacing: 10,
                                          runSpacing: 10,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            SizedBox(
                                                width: compact ? 260 : 330,
                                                child: TextField(
                                                  onChanged: (value) =>
                                                      setState(() =>
                                                          _search = value),
                                                  decoration: const InputDecoration(
                                                      isDense: true,
                                                      prefixIcon:
                                                          Icon(Icons.search),
                                                      hintText:
                                                          'Buscar por nombre, período o unidad',
                                                      border:
                                                          OutlineInputBorder()),
                                                )),
                                            SizedBox(
                                                width: 210,
                                                child: DropdownButtonFormField<
                                                    String>(
                                                  initialValue: selectedStatus,
                                                  isExpanded: true,
                                                  decoration: const InputDecoration(
                                                      isDense: true,
                                                      labelText: 'Estado',
                                                      border:
                                                          OutlineInputBorder()),
                                                  items: [
                                                    const DropdownMenuItem(
                                                        value: 'TODOS',
                                                        child: Text(
                                                            'Todos los estados')),
                                                    for (final status
                                                        in statuses)
                                                      DropdownMenuItem(
                                                          value: status,
                                                          child: Text(
                                                              _statusLabel(
                                                                  status),
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis)),
                                                  ],
                                                  onChanged: (value) =>
                                                      setState(() =>
                                                          _statusFilter =
                                                              value ?? 'TODOS'),
                                                )),
                                            OutlinedButton.icon(
                                                onPressed: () => setState(() =>
                                                    _newestFirst =
                                                        !_newestFirst),
                                                icon: Icon(
                                                    _newestFirst
                                                        ? Icons.arrow_downward
                                                        : Icons.arrow_upward,
                                                    size: 17),
                                                label: Text(_newestFirst
                                                    ? 'Más recientes'
                                                    : 'Más antiguos')),
                                          ]),
                                    ]),
                              ),
                              if (snapshot.hasError)
                                _message(
                                    'No fue posible cargar las declaraciones: ${snapshot.error}')
                              else if (!snapshot.hasData)
                                const Padding(
                                    padding: EdgeInsets.all(36),
                                    child: Center(
                                        child: CircularProgressIndicator()))
                              else if (list.isEmpty)
                                _message(
                                    'No hay declaraciones disponibles para este usuario.')
                              else if (filtered.isEmpty)
                                _message(
                                    'No hay trámites que coincidan con los filtros.')
                              else ...[
                                if (!compact) _tableHeader(),
                                for (final d in filtered)
                                  if (compact)
                                    _mobileRow(d, uid)
                                  else
                                    _tableRow(d, uid),
                              ],
                            ]),
                      ),
                      const SizedBox(height: 24),
                      buildInstitutionalFooter(),
                    ],
                    const SizedBox(height: 72),
                  ],
                );
                return width >= 920
                    ? Row(children: [
                        _sidebar(list),
                        Expanded(
                            child: Center(
                                child: ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 1180),
                                    child: content))),
                      ])
                    : content;
              },
            ),
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
        decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: UcrColors.border),
            borderRadius: BorderRadius.circular(10)),
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
  final _formKey = GlobalKey<FormState>();
  final jobs = <Appointment>[];
  final external = <Appointment>[];
  bool busy = false;
  String period = '';
  String superior = '';
  String _registeredName = '';
  bool _nameLoaded = false;

  Future<void> _loadRegisteredName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = doc.data();
      final fromProfile = (data?['name'] ?? '').toString().trim();
      final fromAuth = (user.displayName ?? '').trim();
      final name = fromProfile.isNotEmpty ? fromProfile : fromAuth;
      if (!mounted) return;
      setState(() {
        _registeredName = name;
        fields[0].text = name;
        _nameLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _registeredName = (user.displayName ?? '').trim();
        fields[0].text = _registeredName;
        _nameLoaded = true;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadRegisteredName();
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

    if (!_nameLoaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Esperá a que se cargue tu nombre registrado.',
          ),
        ),
      );
      return;
    }

    fields[0].text = PersonalDataValidator.normalizeName(_registeredName);

    for (final index in [1, 2, 3, 4, 5]) {
      fields[index].text = fields[index].text.trim();
    }

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() => busy = true);
    try {
      if (!_nameLoaded || _registeredName.isEmpty) {
        throw StateError(
            'No se pudo cargar tu nombre registrado. Revisá tu perfil.');
      }
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
            'Completá los datos, ingresá el UID del superior y agregá al menos un nombramiento.');
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

  InputDecoration _fieldStyle(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: UcrColors.blue),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
      );

  Widget _input(
    int index,
    String label,
    IconData icon, {
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: fields[index],
      readOnly: index == 0,
      maxLines: maxLines,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (value) {
        return _validatePersonalField(index, value);
      },
      keyboardType: index == 1
          ? TextInputType.number
          : index == 2
              ? TextInputType.phone
              : index == 3
                  ? TextInputType.emailAddress
                  : TextInputType.text,
      decoration: _fieldStyle(label, icon).copyWith(
        errorMaxLines: 3,
      ),
    );
  }

  Widget _pair(Widget first, Widget second) => LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 580) {
            return Column(
                children: [first, const SizedBox(height: 14), second]);
          }
          return Row(children: [
            Expanded(child: first),
            const SizedBox(width: 14),
            Expanded(child: second),
          ]);
        },
      );

  Widget _heading(String title, IconData icon) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(children: [
          Icon(icon, color: UcrColors.blue, size: 23),
          const SizedBox(width: 10),
          Text(title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF123663),
              )),
        ]),
      );

  Widget _panel(List<Widget> children) => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F9FE),
          border: Border.all(color: const Color(0xFFD7E8F7)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );

  Widget _periodDropdown() =>
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('periods')
            .where('enabled', isEqualTo: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Text(
                'No se pudieron consultar los períodos: ${snapshot.error}',
                style: const TextStyle(color: Colors.red));
          }
          if (!snapshot.hasData) return const LinearProgressIndicator();
          final docs = snapshot.data!.docs;
          final current = fields[6].text.trim();
          final available = docs.any((doc) => doc.id == current);
          // Conservar el valor de un borrador antiguo aunque ya esté deshabilitado.
          final items = <DropdownMenuItem<String>>[
            if (current.isNotEmpty && !available)
              DropdownMenuItem(
                  value: current,
                  child: Text('$current (período anterior)',
                      overflow: TextOverflow.ellipsis)),
            for (final doc in docs)
              DropdownMenuItem(
                value: doc.id,
                child: Text(
                    (doc.data()['name'] ?? doc.data()['label'] ?? doc.id)
                        .toString(),
                    overflow: TextOverflow.ellipsis),
              ),
          ];
          if (items.isEmpty)
            return const Text('No hay períodos activos disponibles.');
          return DropdownButtonFormField<String>(
            key: ValueKey('period-$current'),
            initialValue: current.isEmpty ? null : current,
            isExpanded: true,
            decoration:
                _fieldStyle('Período activo', Icons.event_available_outlined),
            hint: const Text('Seleccioná un período'),
            items: items,
            onChanged: (value) => setState(() => fields[6].text = value ?? ''),
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UcrColors.background,
      appBar: AppBar(
        backgroundColor: UcrColors.blue,
        foregroundColor: Colors.white,
        title: Text(widget.existing == null
            ? 'Nueva declaración'
            : 'Editar declaración'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(22),
              children: [
                const Text('Datos de la declaración',
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF123663))),
                const SizedBox(height: 6),
                const Text('Completá la información y agregá tus horarios.',
                    style: TextStyle(color: Color(0xFF55749A))),
                const SizedBox(height: 22),
                _panel([
                  _heading('Información personal', Icons.person_outline),
                  _pair(
                    _input(
                        0, 'Nombre completo (registrado)', Icons.lock_outline),
                    _input(1, 'Identificación', Icons.credit_card_outlined),
                  ),
                  const SizedBox(height: 14),
                  _pair(
                    _input(3, 'Correo electrónico', Icons.mail_outline),
                    _input(2, 'Teléfono', Icons.phone_outlined),
                  ),
                ]),
                const SizedBox(height: 16),
                _panel([
                  _heading('Información institucional',
                      Icons.account_balance_outlined),
                  _input(4, 'Unidad académica o administrativa',
                      Icons.apartment_outlined),
                  const SizedBox(height: 14),
                  _pair(
                    _periodDropdown(),
                    _input(7, 'UID del superior',
                        Icons.supervisor_account_outlined),
                  ),
                ]),
                const SizedBox(height: 16),
                _panel([
                  _heading('Observaciones adicionales', Icons.notes_outlined),
                  _input(
                      5, 'Observaciones (opcional)', Icons.edit_note_outlined,
                      maxLines: 3),
                ]),
                const SizedBox(height: 16),
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
                                style:
                                    const TextStyle(color: Colors.deepOrange))),
                          ]),
                    ),
                  );
                }),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: busy ? null : save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(busy ? 'Guardando...' : 'Guardar borrador'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
  bool noEndDate = false;

  @override
  void initState() {
    super.initState();
    final appointment = widget.existing;
    if (appointment != null) {
      f[0].text = appointment.workplace;
      f[1].text = appointment.position;
      f[2].text = appointment.expectedHours.toString();
      f[3].text = appointment.startDate;
      noEndDate = appointment.endDate.trim().toLowerCase() == 'no aplica' ||
          appointment.endDate.trim().isEmpty;
      f[4].text = noEndDate ? '' : appointment.endDate;
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

  Future<void> _chooseDate(TextEditingController controller) async {
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
    setState(() => controller.text =
        '${chosen.year.toString().padLeft(4, '0')}-${chosen.month.toString().padLeft(2, '0')}-${chosen.day.toString().padLeft(2, '0')}');
  }

  Future<void> _chooseTime(TextEditingController controller) async {
    final parts = controller.text.trim().split(':');
    final parsedHour = parts.isNotEmpty ? int.tryParse(parts[0]) : null;
    final parsedMinute = parts.length > 1 ? int.tryParse(parts[1]) : null;
    int hour = (parsedHour != null && parsedHour >= 0 && parsedHour < 24)
        ? parsedHour
        : 8;
    int minute =
        (parsedMinute != null && parsedMinute >= 0 && parsedMinute < 60)
            ? parsedMinute
            : 0;

    final hourController = FixedExtentScrollController(initialItem: hour);
    final minuteController = FixedExtentScrollController(initialItem: minute);

    final selected = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => Dialog(
        backgroundColor: const Color(0xFF1D1D20),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 205,
                  child: Center(
                    child: SizedBox(
                      width: 208,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Una sola franja detrás de las dos ruedas.
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
                                SizedBox(
                                  width: 84,
                                  child: CupertinoPicker(
                                    scrollController: hourController,
                                    itemExtent: 44,
                                    diameterRatio: 1.8,
                                    squeeze: 1.0,
                                    useMagnifier: false,
                                    selectionOverlay: null,
                                    onSelectedItemChanged: (value) =>
                                        hour = value,
                                    children: List.generate(
                                        24,
                                        (index) => Center(
                                              child: Text(
                                                index
                                                    .toString()
                                                    .padLeft(2, '0'),
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 25,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            )),
                                  ),
                                ),
                                const SizedBox(
                                  width: 26,
                                  child: Center(
                                    child: Text(':',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 26,
                                          fontWeight: FontWeight.bold,
                                        )),
                                  ),
                                ),
                                SizedBox(
                                  width: 84,
                                  child: CupertinoPicker(
                                    scrollController: minuteController,
                                    itemExtent: 44,
                                    diameterRatio: 1.8,
                                    squeeze: 1.0,
                                    useMagnifier: false,
                                    selectionOverlay: null,
                                    onSelectedItemChanged: (value) =>
                                        minute = value,
                                    children: List.generate(
                                        60,
                                        (index) => Center(
                                              child: Text(
                                                index
                                                    .toString()
                                                    .padLeft(2, '0'),
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 25,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            )),
                                  ),
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
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancelar'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('Aceptar',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // El formato HH:mm se conserva para las validaciones y Firestore.
    if (selected == true && mounted) {
      setState(() => controller.text =
          '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}');
    }
  }

  @override
  Widget build(BuildContext context) {
    const labels = [
      'Lugar de trabajo / institución',
      'Cargo o categoría',
      'Jornada semanal esperada (horas)',
      'Inicio de vigencia',
      'Fin de vigencia',
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
                  child: i == 4 && noEndDate
                      ? TextField(
                          controller: f[i],
                          readOnly: true,
                          enabled: false,
                          decoration: InputDecoration(
                            labelText: labels[i],
                            hintText: 'No aplica',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        )
                      : i >= 3
                          ? TextField(
                              controller: f[i],
                              readOnly: true,
                              onTap: () => _chooseDate(f[i]),
                              decoration: InputDecoration(
                                labelText: labels[i],
                                suffixIcon: IconButton(
                                  tooltip: 'Abrir calendario',
                                  icon: const Icon(Icons.event_outlined),
                                  onPressed: () => _chooseDate(f[i]),
                                ),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                            )
                          : TextField(
                              controller: f[i],
                              keyboardType: i == 2
                                  ? const TextInputType.numberWithOptions(
                                      decimal: true)
                                  : TextInputType.text,
                              decoration: InputDecoration(
                                labelText: labels[i],
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                ),
              CheckboxListTile(
                value: noEndDate,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('No aplica'),
                subtitle: const Text(
                    'El nombramiento no tiene fecha de finalización definida'),
                onChanged: (value) => setState(() {
                  noEndDate = value ?? false;
                  if (noEndDate) f[4].clear();
                }),
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
                      readOnly: true,
                      onTap: () => _chooseTime(start),
                      decoration: const InputDecoration(
                        labelText: 'Inicio HH:MM',
                        prefixIcon: Icon(Icons.access_time_outlined),
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
                        prefixIcon: Icon(Icons.access_time_outlined),
                        border: OutlineInputBorder(),
                      ),
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
                      f[1].text.trim().isEmpty ||
                      blocks.isEmpty ||
                      expected == null ||
                      !expected.isFinite ||
                      expected <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'Completá institución, puesto, una jornada numérica mayor que cero y al menos un horario.'),
                      ),
                    );
                    return;
                  }
                  final beginDate =
                      ValidationService.parseDate(f[3].text.trim());

                  final finishDate =
                      ValidationService.parseDate(f[4].text.trim());
                  if (beginDate == null ||
                      (!noEndDate &&
                          (finishDate == null ||
                              finishDate.isBefore(beginDate)))) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              'Seleccioná fechas válidas; el fin no puede ser anterior al inicio.')),
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
                      endDate: noEndDate ? 'No aplica' : f[4].text.trim(),
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
      appBar: AppBar(
          backgroundColor: UcrColors.blue,
          foregroundColor: Colors.white,
          title: const Text('Historial y auditoría')),
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

class _WelcomeCurvePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Capa celeste de transición

    // Curva exterior celeste
    final outerPath = Path()
      ..moveTo(0, 0)
      ..lineTo(w * 0.52, 0)
      ..cubicTo(
        w * 0.64,
        h * 0.25,
        w * 0.64,
        h * 0.75,
        w * 0.58,
        h,
      )
      ..lineTo(0, h)
      ..close();

    canvas.drawPath(
      outerPath,
      Paint()..color = const Color(0xFF4BA9ED).withValues(alpha: 0.70),
    );

    // Segunda curva azul claro
    final middlePath = Path()
      ..moveTo(0, 0)
      ..lineTo(w * 0.48, 0)
      ..cubicTo(
        w * 0.60,
        h * 0.25,
        w * 0.60,
        h * 0.75,
        w * 0.54,
        h,
      )
      ..lineTo(0, h)
      ..close();

    canvas.drawPath(
      middlePath,
      Paint()..color = const Color(0xFFB7E3FF).withValues(alpha: 0.96),
    );

    // Curva principal blanca-celeste
    final innerPath = Path()
      ..moveTo(0, 0)
      ..lineTo(w * 0.43, 0)
      ..cubicTo(
        w * 0.55,
        h * 0.25,
        w * 0.55,
        h * 0.75,
        w * 0.49,
        h,
      )
      ..lineTo(0, h)
      ..close();

    canvas.drawPath(
      innerPath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0xFFF5FAFF),
            Color(0xFFE8F6FF),
            Color(0xFFD4EDFF),
          ],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}
