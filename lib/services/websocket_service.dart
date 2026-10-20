import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketService {
  WebSocketChannel? channel;

  Future<void> connect() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw Exception('No hay un usuario autenticado');
    }

    final token = await user.getIdToken();

    if (token == null) {
      throw Exception('No se pudo obtener el token');
    }

    channel = WebSocketChannel.connect(
      Uri.parse('ws://localhost:8080'),
    );

    await channel!.ready;

    channel!.sink.add(
      jsonEncode({
        'type': 'auth',
        'token': token,
      }),
    );
  }

  Stream? get messages => channel?.stream;

  void disconnect() {
    channel?.sink.close();
    channel = null;
  }
}
