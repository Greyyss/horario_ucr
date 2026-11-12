import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/ucr_colors.dart';
import '../models/declaration.dart';
import '../services/declaration_service.dart';
import 'notification_bell.dart';
import 'admin_page.dart';
import 'personal_profile_page.dart';
import 'declaration_editor_page.dart';
import 'timeline_page.dart';
import 'dashboard_welcome_curve_painter.dart';

import 'declaration_views.dart' as declaration_views;

export 'appointment_page.dart' show AppointmentPage, days;
export 'declaration_editor_page.dart' show EditorPage;
export 'timeline_page.dart' show TimelinePage;

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  final service = DeclarationService();
  final Set<String> _pdfBusy = {};

  String role = 'declarante';
  Map<String, dynamic> profile = {};
  bool loading = true;

  String _search = '';
  String _statusFilter = 'TODOS';
  bool _newestFirst = true;
  String _section = 'inicio';
  bool _sidebarExpanded = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Widget _notificationBell() {
    return NotificationBell(
      onOpenDeclaration: _openDeclarationFromNotification,
    );
  }

  void _openDeclarationFromNotification(String id) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => declaration_views.DeclarationDetailPage(
          id: id,
          actionsBuilder: (declaration) => _actionsFor(
            declaration,
            FirebaseAuth.instance.currentUser?.uid ?? '',
          ),
        ),
      ),
    );
  }

  Future<void> load() async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(FirebaseAuth.instance.currentUser!.uid)
        .get();

    if (mounted) {
      setState(() {
        profile = doc.data() ?? {};
        role = profile['role'] ?? 'declarante';
        loading = false;
      });
    }
  }

  Future<void> _runPdf(
    Declaration d,
    String action,
  ) async {
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
          content: Text(
            'No se pudo completar la operación: $message',
          ),
          duration: const Duration(seconds: 8),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _pdfBusy.remove(d.id));
      }
    }
  }

  Future<void> act(
    Declaration d,
    String action, {
    String note = '',
    bool confirmed = false,
  }) async {
    try {
      await service.transition(
        d,
        action,
        note: note,
        confirmed: confirmed,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Operación completada'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
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
          decoration: const InputDecoration(
            labelText: 'Motivo obligatorio',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('Devolver'),
          ),
        ],
      ),
    );

    if (note != null) {
      await act(d, 'return', note: note);
    }
  }

  Future<void> askSign(Declaration d) async {
    bool accepted = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Declaración bajo juramento'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Declaro bajo juramento que la información registrada '
                'es verdadera y completa. Esta es una firma electrónica '
                'interna, no una firma digital certificada.',
              ),
              CheckboxListTile(
                value: accepted,
                onChanged: (v) {
                  setLocal(() => accepted = v ?? false);
                },
                title: const Text('Confirmo expresamente'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: accepted ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Firmar'),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      await act(d, 'signOwner', confirmed: true);
    }
  }

  String _statusLabel(String status) {
    return status.replaceAll('_', ' ');
  }

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

    return '${two(d.day)}/${two(d.month)}/${d.year}  '
        '${two(d.hour)}:${two(d.minute)}';
  }

  void _help() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(
              Icons.help_outline,
              color: UcrColors.blue,
            ),
            SizedBox(width: 10),
            Text('Ayuda · DeclaraHorario'),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: const Text(
            'Este sistema permite crear y tramitar declaraciones '
            'de horario.\n\n'
            'En «Mis declaraciones» puede consultar el estado '
            'y realizar las acciones disponibles.\n\n'
            'Para consultar los movimientos de un trámite, '
            'utilice «Historial».\n\n'
            'Las opciones dependen de su rol institucional.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Widget _summary(
    String label,
    int count,
    IconData icon,
    Color accent,
  ) {
    final Color backgroundColor = switch (label) {
      'Total de declaraciones' => const Color(0xFFEAF4FF),
      'Pendientes' => const Color(0xFFF0F8FF),
      'Finalizadas' => const Color(0xFFF0F8FB),
      _ => const Color(0xFFF6F9FD),
    };

    return Container(
      height: 78,
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 11,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: accent.withValues(alpha: 0.38),
          width: 1.35,
        ),
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

  Widget _actionsFor(Declaration d, String uid) {
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        if (role == 'declarante' && d.status == 'BORRADOR') ...[
          _action(
            d,
            'validate',
            'Validar',
            primary: true,
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => EditorPage(existing: d),
              ),
            ),
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('Editar'),
          ),
        ],
        if (role == 'declarante' && d.status == 'VALIDADA')
          _action(
            d,
            'submit',
            'Enviar a firma',
            primary: true,
          ),
        if (role == 'declarante' && d.status == 'PENDIENTE_FIRMA_DECLARANTE')
          _action(
            d,
            'signOwner',
            'Firmar bajo juramento',
            primary: true,
          ),
        if (role == 'declarante' && d.status == 'FIRMADA_POR_DECLARANTE')
          _action(
            d,
            'route',
            'Remitir al superior',
            primary: true,
          ),
        if (role == 'declarante' && d.status == 'DEVUELTA')
          _action(
            d,
            'newVersion',
            'Crear nueva versión',
            primary: true,
          ),
        if (role == 'superior' &&
            d.superiorId == uid &&
            d.status == 'PENDIENTE_FIRMA_SUPERIOR') ...[
          _action(
            d,
            'signSuperior',
            'Aprobar y firmar',
            primary: true,
          ),
          _action(
            d,
            'return',
            'Devolver',
          ),
        ],
        if (role == 'superior' &&
            d.superiorId == uid &&
            d.status == 'FIRMADA_POR_SUPERIOR')
          _action(
            d,
            'sendHr',
            'Enviar a RRHH',
            primary: true,
          ),
        if (role == 'rrhh' && d.status == 'ENVIADA_A_RRHH')
          _action(
            d,
            'receive',
            'Recibir',
            primary: true,
          ),
        if (role == 'rrhh' && d.status == 'RECIBIDA_RRHH')
          _action(
            d,
            'finish',
            'Finalizar',
            primary: true,
          ),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TimelinePage(id: d.id),
            ),
          ),
          icon: const Icon(Icons.history, size: 16),
          label: const Text('Historial'),
        ),
        if (d.status != 'FINALIZADA')
          OutlinedButton.icon(
            onPressed:
                _pdfBusy.contains(d.id) ? null : () => _runPdf(d, 'preview'),
            icon: const Icon(
              Icons.picture_as_pdf_outlined,
              size: 16,
            ),
            label: const Text('Vista previa PDF'),
          ),
        if (d.status == 'FINALIZADA' && (role == 'rrhh' || role == 'admin'))
          OutlinedButton.icon(
            onPressed:
                _pdfBusy.contains(d.id) ? null : () => _runPdf(d, 'archive'),
            icon: const Icon(
              Icons.cloud_upload_outlined,
              size: 16,
            ),
            label: const Text('Archivar PDF'),
          ),
        if (d.status == 'FINALIZADA')
          OutlinedButton.icon(
            onPressed:
                _pdfBusy.contains(d.id) ? null : () => _runPdf(d, 'open'),
            icon: const Icon(
              Icons.picture_as_pdf_outlined,
              size: 16,
            ),
            label: const Text('Abrir PDF archivado'),
          ),
        if (_pdfBusy.contains(d.id))
          const Padding(
            padding: EdgeInsets.all(8),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
              ),
            ),
          ),
      ],
    );
  }

  Widget _tableHeader() {
    return Container(
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
  }

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

  Widget _action(
    Declaration d,
    String key,
    String label, {
    bool primary = false,
  }) {
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
        ? FilledButton(
            onPressed: handler,
            child: Text(label),
          )
        : OutlinedButton(
            onPressed: handler,
            child: Text(label),
          );
  }

  Future<void> _resetPassword() async {
    final email = FirebaseAuth.instance.currentUser?.email;

    if (email == null || email.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'La cuenta no tiene correo registrado.',
            ),
          ),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cambiar contraseña'),
        content: Text(
          '¿Enviar un enlace para cambiar la contraseña a $email?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enviar enlace'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: email,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Revisá tu correo para cambiar la contraseña.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No se pudo enviar el enlace: $e',
            ),
          ),
        );
      }
    }
  }

  Future<void> _openPersonalProfile() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => const PersonalProfilePage(),
      ),
    );

    if (!mounted) return;

    try {
      await load();
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudieron actualizar los datos del perfil.',
          ),
        ),
      );
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
      constraints: const BoxConstraints(
        minWidth: 270,
        maxWidth: 345,
      ),
      onSelected: (value) {
        if (value == 'profile') {
          _openPersonalProfile();
        }

        if (value == 'password') {
          _resetPassword();
        }

        if (value == 'logout') {
          FirebaseAuth.instance.signOut();
        }

        if (value == 'admin') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AdminPage(),
            ),
          );
        }
      },
      itemBuilder: (ctx) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 25,
                  backgroundColor: Color(0xFFEAF3FA),
                  child: Icon(
                    Icons.person_outline,
                    color: UcrColors.blue,
                    size: 29,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: UcrColors.text,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        email,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      Text(
                        'Rol: $role',
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
        ),
        if (id.isNotEmpty)
          PopupMenuItem<String>(
            enabled: false,
            child: Text(
              'Identificación: •••••'
              '${id.length >= 4 ? id.substring(id.length - 4) : ''}',
              style: const TextStyle(
                color: UcrColors.text,
              ),
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'profile',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.manage_accounts_outlined,
              color: UcrColors.blue,
            ),
            title: Text('Mis datos personales'),
          ),
        ),
        const PopupMenuItem<String>(
          value: 'password',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.key_outlined,
              color: UcrColors.blue,
            ),
            title: Text('Cambiar contraseña'),
          ),
        ),
        if (role == 'admin')
          const PopupMenuItem<String>(
            value: 'admin',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.admin_panel_settings_outlined,
              ),
              title: Text('Administración'),
            ),
          ),
        const PopupMenuItem<String>(
          value: 'logout',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.logout,
              color: Color(0xFFB42335),
            ),
            title: Text(
              'Cerrar sesión',
              style: TextStyle(
                color: Color(0xFFB42335),
              ),
            ),
          ),
        ),
      ],
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 19,
              backgroundColor: UcrColors.blue,
              child: Icon(
                Icons.person_outline,
                color: Colors.white,
              ),
            ),
            SizedBox(width: 5),
            Icon(
              Icons.keyboard_arrow_down,
              color: UcrColors.blue,
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickCard(
    String label,
    String subtitle,
    IconData icon,
    VoidCallback action,
  ) {
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
            border: Border.all(
              color: const Color(0xFFCEE6F9),
            ),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFEDF8FF),
                Color(0xFFC8E9FF),
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: const Color(0xFFD0E9FC),
                child: Icon(
                  icon,
                  color: const Color(0xFF0067B7),
                  size: 28,
                ),
              ),
              const Spacer(),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF07194D),
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF4C6F9A),
                  fontSize: 12,
                ),
              ),
            ],
          ),
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

  Widget _welcomeBanner() {
    return Container(
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
              Positioned.fill(
                child: CustomPaint(
                  painter: WelcomeCurvePainter(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'B I E N V E N I D O (A)',
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
                      'Gestioná tus declaraciones '
                      'de forma sencilla y segura.',
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
  }

  Widget _sideItem(
    String label,
    IconData icon,
    VoidCallback onTap, {
    bool selected = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 3,
      ),
      child: Tooltip(
        message: label,
        child: Semantics(
          selected: selected,
          child: Material(
            color: selected ? const Color(0xFF0B70C2) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            child: InkWell(
              borderRadius: BorderRadius.circular(9),
              hoverColor: Colors.white.withValues(alpha: 0.08),
              onTap: onTap,
              child: SizedBox(
                height: 52,
                child: Row(
                  children: [
                    SizedBox(
                      width: 56,
                      child: Icon(
                        icon,
                        color: Colors.white,
                        size: 23,
                      ),
                    ),
                    if (_sidebarExpanded)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sidebar(List<Declaration> list) {
    final sidebarWidth = _sidebarExpanded ? 232.0 : 80.0;

    return AnimatedContainer(
      width: sidebarWidth,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOutCubic,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF064E95),
            Color(0xFF073A77),
          ],
        ),
      ),
      child: ClipRect(
        // Evita desbordamientos del texto durante la animación.
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: sidebarWidth,
          maxWidth: sidebarWidth,
          child: SizedBox(
            width: sidebarWidth,
            child: Column(
              children: [
                const SizedBox(height: 8),

                // Botón para contraer o expandir.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 56,
                        height: 48,
                        child: IconButton(
                          tooltip: _sidebarExpanded
                              ? 'Contraer menú'
                              : 'Expandir menú',
                          onPressed: () {
                            setState(() {
                              _sidebarExpanded = !_sidebarExpanded;
                            });
                          },
                          icon: Icon(
                            _sidebarExpanded
                                ? Icons.chevron_left_rounded
                                : Icons.chevron_right_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      ),
                      if (_sidebarExpanded)
                        const Expanded(
                          child: Text(
                            'Menú',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Opciones de navegación.
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      _sideItem(
                        'Inicio',
                        Icons.home_outlined,
                        () => setState(() => _section = 'inicio'),
                        selected: _section == 'inicio',
                      ),
                      if (role == 'declarante')
                        _sideItem(
                          'Nueva declaración',
                          Icons.note_add_outlined,
                          () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const EditorPage(),
                            ),
                          ),
                        ),
                      _sideItem(
                        role == 'declarante'
                            ? 'Mis declaraciones'
                            : 'Declaraciones',
                        Icons.description_outlined,
                        () => setState(
                          () => _section = 'declaraciones',
                        ),
                        selected: _section == 'declaraciones',
                      ),
                      _sideItem(
                        'Seguimiento',
                        Icons.bar_chart_outlined,
                        () => _chooseHistory(list),
                      ),
                      if (role == 'admin')
                        _sideItem(
                          'Administración',
                          Icons.admin_panel_settings_outlined,
                          () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AdminPage(),
                            ),
                          ),
                        ),
                      const Divider(
                        color: Color(0xFF3978AE),
                        indent: 22,
                        endIndent: 22,
                      ),
                      _sideItem(
                        'Ayuda',
                        Icons.help_outline,
                        _help,
                      ),
                      _sideItem(
                        'Cerrar sesión',
                        Icons.logout,
                        () => FirebaseAuth.instance.signOut(),
                      ),
                    ],
                  ),
                ),

                // Pie de la barra lateral.
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: _sidebarExpanded
                      ? const Text(
                          'Universidad de Costa Rica',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                          ),
                        )
                      : const Tooltip(
                          message: 'Universidad de Costa Rica',
                          child: Icon(
                            Icons.account_balance_outlined,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _chooseHistory(
    List<Declaration> list,
  ) async {
    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Todavía no hay declaraciones para consultar.',
          ),
        ),
      );
      return;
    }

    final selected = list.length == 1
        ? list.first.id
        : await showDialog<String>(
            context: context,
            builder: (_) => declaration_views.DeclarationHistoryPicker(
              declarations: list,
            ),
          );

    if (selected == null || !mounted) return;

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => TimelinePage(id: selected),
      ),
    );
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
          child: Image.asset(
            'assets/images/logo_declara_ucr.png',
            height: width < 600 ? 55 : 70,
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
          ),
        ),
        actions: [
          if (width >= 650)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      _roleName,
                      style: const TextStyle(
                        color: Color(0xFF5876A0),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          _notificationBell(),
          _profileMenu(),
          const SizedBox(width: 8),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(
            height: 1,
            color: UcrColors.border,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Ayuda',
        onPressed: _help,
        backgroundColor: UcrColors.blue,
        foregroundColor: Colors.white,
        child: const Icon(Icons.help_outline),
      ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : StreamBuilder<List<Declaration>>(
              stream: role == 'declarante'
                  ? service.watchMine()
                  : role == 'superior'
                      ? service.watchAssigned()
                      : service.watchAll(),
              builder: (ctx, snapshot) {
                final list = snapshot.data
                        ?.where(
                          (d) =>
                              role == 'admin' ||
                              role == 'rrhh' ||
                              role == 'declarante' ||
                              d.superiorId == uid,
                        )
                        .toList() ??
                    <Declaration>[];

                final pending = list
                    .where(
                      (d) => d.status != 'FINALIZADA' && d.status != 'ANULADA',
                    )
                    .length;

                final finished = list
                    .where(
                      (d) => d.status == 'FINALIZADA',
                    )
                    .length;

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
                  ..sort(
                    (a, b) => _newestFirst
                        ? b.updatedAt.compareTo(a.updatedAt)
                        : a.updatedAt.compareTo(b.updatedAt),
                  );

                final compact = width < 780;

                final content = ListView(
                  padding: EdgeInsets.symmetric(
                    horizontal: width < 600 ? 14 : 24,
                    vertical: 24,
                  ),
                  children: [
                    if (width < 920) ...[
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            TextButton.icon(
                              onPressed: () => setState(
                                () => _section = 'inicio',
                              ),
                              icon: const Icon(
                                Icons.home_outlined,
                              ),
                              label: const Text('Inicio'),
                            ),
                            if (role == 'declarante')
                              TextButton.icon(
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const EditorPage(),
                                  ),
                                ),
                                icon: const Icon(Icons.add),
                                label: const Text(
                                  'Nueva declaración',
                                ),
                              ),
                            TextButton.icon(
                              onPressed: () => setState(
                                () => _section = 'declaraciones',
                              ),
                              icon: const Icon(
                                Icons.description_outlined,
                              ),
                              label: const Text(
                                'Declaraciones',
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () => _chooseHistory(list),
                              icon: const Icon(
                                Icons.history,
                              ),
                              label: const Text(
                                'Seguimiento',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_section != 'inicio') ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => setState(
                            () => _section = 'inicio',
                          ),
                          icon: const Icon(
                            Icons.arrow_back,
                          ),
                          label: const Text(
                            'Volver al inicio',
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (_section == 'inicio') ...[
                      _welcomeBanner(),
                      const SizedBox(height: 18),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final available = constraints.maxWidth;

                          final columns = available >= 720
                              ? 4
                              : available >= 480
                                  ? 2
                                  : 1;

                          final cardWidth =
                              (available - (columns - 1) * 12) / columns;

                          final draft = list
                              .where(
                                (d) => d.status == 'BORRADOR',
                              )
                              .length;

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
                                  const Color(0xFF2B91D4),
                                ),
                              ),
                              SizedBox(
                                width: cardWidth,
                                child: _summary(
                                  'Finalizadas',
                                  finished,
                                  Icons.check_circle_outline,
                                  const Color(0xFF0087B9),
                                ),
                              ),
                              SizedBox(
                                width: cardWidth,
                                child: _summary(
                                  'Borrador',
                                  draft,
                                  Icons.edit_note_outlined,
                                  const Color(0xFF416C9E),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Accesos principales',
                        style: TextStyle(
                          color: Color(0xFF07194D),
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Seleccioná la opción que deseás realizar.',
                        style: TextStyle(
                          color: Color(0xFF5476A4),
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, constraints) {
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
                                        builder: (_) => const EditorPage(),
                                      ),
                                    ),
                                  ),
                                ),
                              SizedBox(
                                width: cardWidth,
                                child: _quickCard(
                                  'Mis declaraciones',
                                  'Consultar y gestionar trámites',
                                  Icons.description_outlined,
                                  () => setState(
                                    () => _section = 'declaraciones',
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: cardWidth,
                                child: _quickCard(
                                  'Seguimiento',
                                  'Ver el historial de movimientos',
                                  Icons.track_changes_outlined,
                                  () => _chooseHistory(list),
                                ),
                              ),
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
                                        builder: (_) => const AdminPage(),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
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
                              color: UcrColors.text,
                            ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Consulte, filtre y gestione sus trámites.',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 20),
                      LayoutBuilder(
                        builder: (context, constraints) {
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
                        },
                      ),
                      const SizedBox(height: 24),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(
                            color: UcrColors.border,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(
                                        Icons.folder_open_outlined,
                                        color: UcrColors.blue,
                                        size: 22,
                                      ),
                                      SizedBox(width: 9),
                                      Text(
                                        'Trámites registrados',
                                        style: TextStyle(
                                          fontSize: 19,
                                          fontWeight: FontWeight.w700,
                                          color: UcrColors.text,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${filtered.length} de '
                                    '${list.length} declaraciones',
                                    style: const TextStyle(
                                      color: Color(0xFF687789),
                                      fontSize: 12,
                                    ),
                                  ),
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
                                          onChanged: (value) => setState(
                                            () => _search = value,
                                          ),
                                          decoration: const InputDecoration(
                                            isDense: true,
                                            prefixIcon: Icon(Icons.search),
                                            hintText:
                                                'Buscar por nombre, período o unidad',
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 210,
                                        child: DropdownButtonFormField<String>(
                                          initialValue: selectedStatus,
                                          isExpanded: true,
                                          decoration: const InputDecoration(
                                            isDense: true,
                                            labelText: 'Estado',
                                            border: OutlineInputBorder(),
                                          ),
                                          items: [
                                            const DropdownMenuItem<String>(
                                              value: 'TODOS',
                                              child: Text(
                                                'Todos los estados',
                                              ),
                                            ),
                                            for (final status in statuses)
                                              DropdownMenuItem<String>(
                                                value: status,
                                                child: Text(
                                                  _statusLabel(
                                                    status,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                          ],
                                          onChanged: (value) => setState(
                                            () => _statusFilter =
                                                value ?? 'TODOS',
                                          ),
                                        ),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: () => setState(
                                          () => _newestFirst = !_newestFirst,
                                        ),
                                        icon: Icon(
                                          _newestFirst
                                              ? Icons.arrow_downward
                                              : Icons.arrow_upward,
                                          size: 17,
                                        ),
                                        label: Text(
                                          _newestFirst
                                              ? 'Más recientes'
                                              : 'Más antiguos',
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (snapshot.hasError)
                              _message(
                                'No fue posible cargar las '
                                'declaraciones: ${snapshot.error}',
                              )
                            else if (!snapshot.hasData)
                              const Padding(
                                padding: EdgeInsets.all(36),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            else if (list.isEmpty)
                              _message(
                                'No hay declaraciones disponibles '
                                'para este usuario.',
                              )
                            else if (filtered.isEmpty)
                              _message(
                                'No hay trámites que coincidan '
                                'con los filtros.',
                              )
                            else ...[
                              if (!compact) _tableHeader(),
                              for (final d in filtered)
                                if (compact)
                                  _mobileRow(d, uid)
                                else
                                  _tableRow(d, uid),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      buildInstitutionalFooter(),
                    ],
                    const SizedBox(height: 72),
                  ],
                );

                return width >= 920
                    ? Row(
                        children: [
                          _sidebar(list),
                          Expanded(
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 1180,
                                ),
                                child: content,
                              ),
                            ),
                          ),
                        ],
                      )
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

  Widget _message(String message) {
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: UcrColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        message,
        style: const TextStyle(color: UcrColors.text),
      ),
    );
  }
}

// ============================================================
// DATOS DE ACTIVIDADES Y GENERACIÓN DE OBSERVACIONES
// ============================================================

