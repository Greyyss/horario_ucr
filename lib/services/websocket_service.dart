import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketService {
  static const serverUrl = String.fromEnvironment(
    'NOTIFICATIONS_WS_URL',
    defaultValue: 'ws://localhost:8080',
  );

  final _events = StreamController<Map<String, dynamic>>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;

  Timer? _retryTimer;
  Timer? _authTimer;

  String? _userId;

  bool _stopped = true;
  bool _disposed = false;
  bool isConnected = false;

  int _attempt = 0;
  int _failures = 0;

  Stream<Map<String, dynamic>> get messages => _events.stream;

  void _emit(Map<String, dynamic> event) {
    if (!_disposed) {
      _events.add(event);
    }
  }

  Future<void> connect() async {
    if (_disposed) {
      throw StateError('El servicio ya fue cerrado.');
    }

    if (!_stopped) return;

    _userId = FirebaseAuth.instance.currentUser?.uid;

    if (_userId == null) {
      throw StateError('No hay un usuario autenticado.');
    }

    _stopped = false;
    await _open();
  }

  Future<void> _open() async {
    if (_stopped || _disposed) return;

    final attempt = ++_attempt;
    WebSocketChannel? socket;

    _emit({
      'type': 'connection',
      'message': 'Conectando notificaciones…',
    });

    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null || user.uid != _userId) {
        disconnect();
        return;
      }

      final token = await user.getIdToken(true);

      if (_stopped || attempt != _attempt) return;

      if (token == null) {
        throw StateError('No se pudo renovar la sesión.');
      }

      final uri = Uri.parse(serverUrl);

      if (!['ws', 'wss'].contains(uri.scheme) || uri.host.isEmpty) {
        throw StateError('Dirección WebSocket inválida.');
      }

      socket = WebSocketChannel.connect(uri);

      await socket.ready.timeout(
        const Duration(seconds: 10),
      );

      if (_stopped || attempt != _attempt) {
        unawaited(socket.sink.close());
        return;
      }

      _channel = socket;

      _subscription = socket.stream.listen(
        (raw) {
          if (_stopped || attempt != _attempt) return;

          try {
            final decoded = jsonDecode(raw.toString());

            if (decoded is! Map<String, dynamic>) return;

            if (decoded['type'] == 'authenticated') {
              _authTimer?.cancel();
              isConnected = true;
              _failures = 0;
            }

            _emit(decoded);
          } catch (_) {
            _emit({
              'type': 'error',
              'message': 'Se recibió un aviso inválido.',
            });
          }
        },
        onError: (Object error) => _lost(attempt),
        onDone: () => _lost(attempt),
        cancelOnError: true,
      );

      _authTimer = Timer(
        const Duration(seconds: 15),
        () => _lost(attempt),
      );

      socket.sink.add(
        jsonEncode({
          'type': 'auth',
          'token': token,
        }),
      );
    } catch (_) {
      if (socket != null) {
        unawaited(socket.sink.close());
      }

      _lost(attempt);
    }
  }

  void _lost(int attempt) {
    if (_stopped || _disposed || attempt != _attempt) {
      return;
    }

    _attempt++;
    isConnected = false;

    _authTimer?.cancel();
    _subscription?.cancel();
    _subscription = null;

    _channel?.sink.close();
    _channel = null;

    _retryTimer?.cancel();

    _emit({
      'type': 'connection',
      'message': 'Sin conexión con notificaciones. Reintentando…',
    });

    final seconds = [
      2,
      4,
      8,
      16,
      30,
    ][_failures.clamp(0, 4)];

    if (_failures < 4) {
      _failures++;
    }

    _retryTimer = Timer(
      Duration(seconds: seconds),
      () => unawaited(_open()),
    );
  }

  void _send(Map<String, dynamic> message) {
    if (!isConnected || _channel == null || _stopped) {
      throw StateError(
        'Esperá a que se conecten las notificaciones.',
      );
    }

    _channel!.sink.add(jsonEncode(message));
  }

  void markRead(String id) {
    _send({
      'type': 'mark_read',
      'id': id,
    });
  }

  void markAllRead() {
    _send({
      'type': 'mark_all_read',
    });
  }

  void disconnect() {
    _stopped = true;
    _attempt++;
    isConnected = false;

    _retryTimer?.cancel();
    _authTimer?.cancel();

    _subscription?.cancel();
    _subscription = null;

    _channel?.sink.close();
    _channel = null;

    _emit({
      'type': 'connection',
      'message': 'Notificaciones desconectadas.',
    });
  }

  void dispose() {
    if (_disposed) return;

    disconnect();
    _disposed = true;
    _events.close();
  }
}
