
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }

    throw UnsupportedError(
      'Esta aplicación está configurada únicamente para Flutter Web.',
    );
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBpEbdzRXsrx5ozmnMBaTqieD-yR_S1KaU',
    appId: '1:807844528626:web:16b8dd49aa2bf8105a2b6b',
    messagingSenderId: '807844528626',
    projectId: 'declarahorario-ucr-cff7a',
    authDomain: 'declarahorario-ucr-cff7a.firebaseapp.com',
    storageBucket: 'declarahorario-ucr-cff7a.firebasestorage.app',
  );
}
