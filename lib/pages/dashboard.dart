import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../theme/ucr_colors.dart';
import '../models/declaration.dart';
import '../services/declaration_service.dart';
import '../services/validation_service.dart';
import '../services/personal_data_validator.dart';
import '../services/profile_service.dart';
import 'notification_bell.dart';

import 'admin_page.dart';
import 'personal_profile_page.dart';
import 'superior_selector.dart';
import 'declaration_views.dart' as declaration_views;

const days = [
  '',
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
];

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
                  painter: _WelcomeCurvePainter(),
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

class _ObservationTools {
  static const teachingPositions = <String>{
    'Interino Bachiller',
    'Interino Licenciado',
    'Instructor',
    'Adjunto',
    'Asociado',
    'Catedrático',
  };

  static const activityLabels = <String, String>{
    'CONTACTO': 'horas contacto',
    'CONSULTA': 'horas de consulta',
    'PREPARACION': 'preparación',
  };

  static const dayNames = <String>[
    '',
    'lunes',
    'martes',
    'miércoles',
    'jueves',
    'viernes',
    'sábado',
  ];

  static bool isTeaching(String position) {
    return teachingPositions.contains(position.trim());
  }

  static String normalizeCode(String value) {
    return value.trim().toUpperCase();
  }

  static String? blockError(
    TimeBlock block,
    String position,
    bool isExternal,
  ) {
    // Los trabajos externos no requieren datos de cursos UCR.
    if (isExternal) return null;

    if (isTeaching(position)) {
      final code = block.courseCode ?? '';

      if (code != normalizeCode(code) ||
          !RegExp(r'^[A-Z0-9][A-Z0-9-]{1,19}$').hasMatch(code)) {
        return 'Ingresá las siglas del curso: de 2 a 20 letras, '
            'números o guiones, sin espacios.';
      }

      if (!activityLabels.containsKey(block.activityType)) {
        return 'Seleccioná contacto, consulta o preparación.';
      }

      if ((block.activityName ?? '').trim().isNotEmpty) {
        return 'El cargo cambió: editá este bloque y asignale '
            'curso y tipo de actividad.';
      }
    } else {
      final name = block.activityName ?? '';

      if (name != name.trim() ||
          name.length < 2 ||
          name.length > 150 ||
          RegExp(r'[\r\n\t]').hasMatch(name)) {
        return 'Indicá el nombre de la actividad, '
            'entre 2 y 150 caracteres.';
      }

      if ((block.courseCode ?? '').isNotEmpty ||
          (block.activityType ?? '').isNotEmpty) {
        return 'El cargo cambió: editá este bloque e indicá '
            'una actividad sin curso.';
      }
    }

    return null;
  }

  static String? firstError(List<Appointment> jobs) {
    for (var i = 0; i < jobs.length; i++) {
      for (var j = 0; j < jobs[i].blocks.length; j++) {
        final error = blockError(
          jobs[i].blocks[j],
          jobs[i].position,
          false,
        );

        if (error != null) {
          return 'Nombramiento ${i + 1}, bloque ${j + 1}: $error';
        }
      }
    }

    return null;
  }

  static String blockDescription(TimeBlock block) {
    final code = (block.courseCode ?? '').trim();

    if (code.isNotEmpty) {
      final activity =
          activityLabels[block.activityType] ?? 'actividad sin especificar';

      return '$code · $activity';
    }

    return (block.activityName ?? '').trim();
  }

  static String ranges(List<TimeBlock> source) {
    final blocks = List<TimeBlock>.of(source)
      ..sort((a, b) {
        final byDay = a.day.compareTo(b.day);

        if (byDay != 0) return byDay;

        final byStart = a.start.compareTo(b.start);

        return byStart != 0 ? byStart : a.end.compareTo(b.end);
      });

    return blocks.map((block) {
      final day = block.day >= 1 && block.day <= 6
          ? dayNames[block.day]
          : 'día sin especificar';

      return '$day de ${block.start} a ${block.end}';
    }).join(', ');
  }

  static String generate(
    List<Appointment> jobs,
    List<Appointment> external,
  ) {
    final lines = <String>[];

    for (final job in jobs) {
      if (isTeaching(job.position)) {
        final courses = <String, Map<String, List<TimeBlock>>>{};

        for (final block in job.blocks) {
          final code = (block.courseCode ?? '').trim();

          final course = code.isEmpty ? 'Curso sin especificar' : code;

          final type = block.activityType ?? '';

          courses.putIfAbsent(
            course,
            () => <String, List<TimeBlock>>{},
          );

          courses[course]!.putIfAbsent(type, () => <TimeBlock>[]).add(block);
        }

        final codes = courses.keys.toList()..sort();

        for (final code in codes) {
          final types = courses[code]!;
          final parts = <String>[];

          for (final type in activityLabels.keys) {
            if (types.containsKey(type)) {
              parts.add(
                '${activityLabels[type]}: '
                '${ranges(types[type]!)}',
              );
            }
          }

          for (final type in types.keys.where(
            (type) => !activityLabels.containsKey(type),
          )) {
            parts.add(
              'actividad sin especificar: '
              '${ranges(types[type]!)}',
            );
          }

          lines.add('$code: ${parts.join('; ')}.');
        }
      } else {
        final activities = <String, List<TimeBlock>>{};

        for (final block in job.blocks) {
          final name = (block.activityName ?? '').trim();

          final activity = name.isEmpty ? job.position : name;

          activities.putIfAbsent(activity, () => <TimeBlock>[]).add(block);
        }

        for (final entry in activities.entries) {
          lines.add(
            '${entry.key}: ${ranges(entry.value)}.',
          );
        }
      }
    }

    for (final job in external) {
      if (job.blocks.isNotEmpty) {
        lines.add(
          '${job.position} en ${job.workplace}: '
          '${ranges(job.blocks)}.',
        );
      }
    }

    return lines.join('\n');
  }
}

// ============================================================
// FORMULARIO DE DECLARACIÓN
// ============================================================

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
      fields[5].text = _ObservationTools.generate(
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
      final activityError = _ObservationTools.firstError(jobs);

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
        _automaticObservations ? _ObservationTools.firstError(jobs) : null;

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

class AppointmentPage extends StatefulWidget {
  final Appointment? existing;

  // Tiene valor para UCR y es null para otras instituciones.
  final String? institutionalWorkplace;

  const AppointmentPage({
    super.key,
    this.existing,
    this.institutionalWorkplace,
  });

  @override
  State<AppointmentPage> createState() => _AppointmentPageState();
}

class _AppointmentPageState extends State<AppointmentPage> {
  final f = List.generate(
    5,
    (_) => TextEditingController(),
  );

  final blocks = <TimeBlock>[];

  final start = TextEditingController(text: '08:00');
  final end = TextEditingController(text: '12:00');

  final _courseCode = TextEditingController();
  final _activityName = TextEditingController();

  int day = 1;
  bool noEndDate = false;

  String? _workloadFraction;
  String? _activityType;
  int? _editingBlock;

  bool get _institutional => widget.institutionalWorkplace != null;

  bool get _requiresCourse =>
      _institutional && _ObservationTools.isTeaching(f[1].text);

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

      noEndDate = appointment.endDate.trim().toLowerCase() == 'no aplica' ||
          appointment.endDate.trim().isEmpty;

      f[4].text = noEndDate ? '' : appointment.endDate;

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
      labelText: label,
      helperText: helper,
      helperMaxLines: 3,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  Widget _positionField() {
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
      items: _positions.map((position) {
        return DropdownMenuItem<String>(
          value: position,
          child: Text(
            position,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
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
        const SizedBox(height: 12),
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

    final hourController = FixedExtentScrollController(
      initialItem: hour,
    );

    final minuteController = FixedExtentScrollController(
      initialItem: minute,
    );

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
                const SizedBox(height: 12),
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

    setState(() {
      _editingBlock = index;

      day = block.day;
      start.text = block.start;
      end.text = block.end;

      _courseCode.text = block.courseCode ?? '';

      _activityType =
          _ObservationTools.activityLabels.containsKey(block.activityType)
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
    if (!_positions.contains(f[1].text.trim())) {
      _showMessage(
        'Primero seleccioná el cargo o categoría.',
      );
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

    final block = TimeBlock(
      day: day,
      start: start.text.trim(),
      end: end.text.trim(),
      courseCode: _requiresCourse
          ? _ObservationTools.normalizeCode(_courseCode.text)
          : null,
      activityType: _requiresCourse ? _activityType : null,
      activityName:
          _institutional && !_requiresCourse ? _activityName.text.trim() : null,
    );

    final error = _ObservationTools.blockError(
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
      _showMessage(
        'Seleccioná un cargo de la lista.',
      );
      return;
    }

    if (_institutional && _workloadFraction == null) {
      _showMessage(
        'Seleccioná la jornada del nombramiento UCR.',
      );
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

    final beginDate = ValidationService.parseDate(
      f[3].text.trim(),
    );

    final finishDate = ValidationService.parseDate(
      f[4].text.trim(),
    );

    if (beginDate == null ||
        (!noEndDate &&
            (finishDate == null || finishDate.isBefore(beginDate)))) {
      _showMessage(
        'Seleccioná fechas válidas; el fin no puede '
        'ser anterior al inicio.',
      );
      return;
    }

    for (var i = 0; i < blocks.length; i++) {
      final error = _ObservationTools.blockError(
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
        workplace: f[0].text.trim(),
        position: f[1].text.trim(),
        expectedHours: expected,
        workloadFraction: fraction,
        startDate: f[3].text.trim(),
        endDate: noEndDate ? 'No aplica' : f[4].text.trim(),
        blocks: List.of(blocks),
      ),
    );
  }

  Widget _dateField(
    int index,
    String label,
  ) {
    final disabled = index == 4 && noEndDate;

    return TextField(
      controller: f[index],
      readOnly: true,
      enabled: !disabled,
      onTap: disabled ? null : () => _chooseDate(f[index]),
      decoration: _decoration(label).copyWith(
        hintText: disabled ? 'No aplica' : null,
        suffixIcon: disabled
            ? null
            : IconButton(
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
          TextField(
            controller: _courseCode,
            maxLength: 20,
            textCapitalization: TextCapitalization.characters,
            decoration: _decoration(
              'Siglas del curso',
              helper: 'Ejemplo: IF0011. Podés usar '
                  'cursos diferentes en cada bloque.',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey(
              'activity-$_editingBlock-$_activityType',
            ),
            initialValue: _activityType,
            isExpanded: true,
            decoration: _decoration(
              'Actividad del bloque',
            ),
            hint: const Text('Seleccioná la actividad'),
            items: _ObservationTools.activityLabels.entries.map((entry) {
              return DropdownMenuItem<String>(
                value: entry.key,
                child: Text(entry.value),
              );
            }).toList(),
            onChanged: (value) {
              setState(() => _activityType = value);
            },
          ),
          const SizedBox(height: 12),
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
          helper: 'Podés conservar el cargo o indicar '
              'una actividad específica, por ejemplo: '
              'Comisión de autoevaluación.',
        ),
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
          widget.existing == null
              ? 'Agregar nombramiento'
              : 'Editar nombramiento',
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextField(
                controller: f[0],
                readOnly: _institutional,
                decoration: _decoration(
                  'Lugar de trabajo / institución',
                ),
              ),
              const SizedBox(height: 12),
              _positionField(),
              const SizedBox(height: 12),
              _workloadField(),
              const SizedBox(height: 12),
              _dateField(3, 'Inicio de vigencia'),
              const SizedBox(height: 12),
              _dateField(4, 'Fin de vigencia'),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: noEndDate,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('No aplica'),
                subtitle: const Text(
                  'El nombramiento no tiene '
                  'fecha de finalización definida',
                ),
                onChanged: (value) {
                  setState(() {
                    noEndDate = value ?? false;

                    if (noEndDate) {
                      f[4].clear();
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
              Text(
                _editingBlock == null
                    ? 'Agregar bloque horario'
                    : 'Editar bloque ${_editingBlock! + 1}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
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
              const SizedBox(height: 12),
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
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: _addOrUpdateBlock,
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
                    _ObservationTools.blockDescription(
                      blocks[i],
                    ).isEmpty
                        ? _institutional
                            ? 'Actividad pendiente de completar'
                            : f[1].text
                        : _ObservationTools.blockDescription(
                            blocks[i],
                          ),
                  ),
                  leading: _ObservationTools.blockError(
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
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _editBlock(i),
                      ),
                      IconButton(
                        tooltip: 'Quitar bloque',
                        icon: const Icon(Icons.close),
                        onPressed: () => _removeBlock(i),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _saveAppointment,
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

  const TimelinePage({
    super.key,
    required this.id,
  });

  @override
  Widget build(BuildContext context) {
    return declaration_views.DeclarationHistoryPage(
      id: id,
    );
  }
}

class _WelcomeCurvePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

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
      Paint()
        ..color = const Color(0xFF4BA9ED).withValues(
          alpha: 0.70,
        ),
    );

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
      Paint()
        ..color = const Color(0xFFB7E3FF).withValues(
          alpha: 0.96,
        ),
    );

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
        ).createShader(
          Offset.zero & size,
        ),
    );
  }

  @override
  bool shouldRepaint(
    covariant CustomPainter oldDelegate,
  ) {
    return false;
  }
}
