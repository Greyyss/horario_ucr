import 'dart:async';

import 'package:flutter/material.dart';

import '../services/websocket_service.dart';
import '../theme/ucr_colors.dart';

class NotificationBell extends StatefulWidget {
  final ValueChanged<String> onOpenDeclaration;

  const NotificationBell({
    super.key,
    required this.onOpenDeclaration,
  });

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  final _service = WebSocketService();

  final _notices = ValueNotifier<List<Map<String, dynamic>>>([]);

  final _status = ValueNotifier<String>(
    'Conectando notificaciones…',
  );

  StreamSubscription<Map<String, dynamic>>? _subscription;

  int get _unread =>
      _notices.value.where((notice) => notice['read'] != true).length;

  @override
  void initState() {
    super.initState();

    _subscription = _service.messages.listen(
      _onMessage,
    );

    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await _service.connect();
    } catch (_) {
      if (mounted) {
        _status.value = 'No se pudieron conectar las notificaciones.';
      }
    }
  }

  void _onMessage(Map<String, dynamic> data) {
    if (!mounted) return;

    switch (data['type']) {
      case 'notifications_sync':
        final items = data['notifications'];

        if (items is List) {
          _notices.value = items
              .whereType<Map>()
              .map(
                (item) => Map<String, dynamic>.from(item),
              )
              .toList();

          _status.value = 'Últimas 100 notificaciones';
        }
        break;

      case 'connection':
        _status.value = data['message']?.toString() ?? 'Sin conexión.';
        break;

      case 'error':
        _showMessage(
          data['message']?.toString() ?? 'No se pudo completar la operación.',
        );
        break;

      case 'notification':
        _showMessage(
          data['message']?.toString() ?? 'Nueva notificación',
        );
        break;
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _markRead(String id) {
    try {
      _service.markRead(id);
    } on StateError catch (error) {
      _showMessage(error.message.toString());
    }
  }

  void _markAllRead() {
    try {
      _service.markAllRead();
    } on StateError catch (error) {
      _showMessage(error.message.toString());
    }
  }

  String _dateText(dynamic value) {
    final date = DateTime.tryParse(
      value?.toString() ?? '',
    )?.toLocal();

    if (date == null) return '';

    String two(int number) => number.toString().padLeft(2, '0');

    return '${two(date.day)}/${two(date.month)}/'
        '${date.year} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  void _openNotifications() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AnimatedBuilder(
        animation: Listenable.merge([
          _notices,
          _status,
        ]),
        builder: (context, child) => AlertDialog(
          title: const Row(
            children: [
              Icon(
                Icons.notifications_outlined,
                color: UcrColors.blue,
              ),
              SizedBox(width: 10),
              Text('Notificaciones'),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _status.value,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                if (_notices.value.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: 20,
                    ),
                    child: Text(
                      'No hay notificaciones para mostrar.',
                    ),
                  )
                else
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxHeight: 380,
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _notices.value.length,
                        separatorBuilder: (_, __) => const Divider(
                          height: 1,
                        ),
                        itemBuilder: (context, index) {
                          final notice = _notices.value[index];

                          final read = notice['read'] == true;

                          final id = notice['id']?.toString() ?? '';

                          final declarationId =
                              notice['declarationId']?.toString() ?? '';

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 5,
                            ),
                            leading: Icon(
                              read
                                  ? Icons.drafts_outlined
                                  : Icons.mark_email_unread_outlined,
                              color: UcrColors.blue,
                            ),
                            title: Text(
                              notice['title']?.toString() ?? 'Notificación',
                              style: TextStyle(
                                fontWeight:
                                    read ? FontWeight.normal : FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              '${notice['message'] ?? ''}\n'
                              '${_dateText(notice['createdAt'])}',
                            ),
                            isThreeLine: true,
                            trailing: read
                                ? null
                                : IconButton(
                                    tooltip: 'Marcar como leída',
                                    onPressed: _service.isConnected
                                        ? () => _markRead(id)
                                        : null,
                                    icon: const Icon(
                                      Icons.done,
                                    ),
                                  ),
                            onTap: () {
                              if (!read && _service.isConnected) {
                                _markRead(id);
                              }

                              if (declarationId.isNotEmpty) {
                                Navigator.pop(
                                  dialogContext,
                                );

                                widget.onOpenDeclaration(
                                  declarationId,
                                );
                              }
                            },
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  _unread > 0 && _service.isConnected ? _markAllRead : null,
              child: const Text(
                'Marcar todas como leídas',
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(
                dialogContext,
              ),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Map<String, dynamic>>>(
      valueListenable: _notices,
      builder: (context, notices, child) => IconButton(
        tooltip: 'Notificaciones'
            '${_unread > 0 ? ' ($_unread sin leer)' : ''}',
        onPressed: _openNotifications,
        icon: Badge(
          isLabelVisible: _unread > 0,
          label: Text(
            _unread > 99 ? '99+' : '$_unread',
          ),
          child: const Icon(
            Icons.notifications_outlined,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _service.dispose();
    _notices.dispose();
    _status.dispose();

    super.dispose();
  }
}
