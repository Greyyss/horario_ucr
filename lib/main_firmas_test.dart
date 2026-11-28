import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'declara_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const enabled = bool.fromEnvironment('FIRMAS_TEST');

  if (!kDebugMode || !enabled) {
    throw StateError(
      'Esta entrada es exclusiva de pruebas locales en modo debug.',
    );
  }

  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: 'demo-api-key',
      appId: '1:1234567890:web:0123456789abcdef',
      messagingSenderId: '1234567890',
      projectId: 'demo-declara-firmas',
      authDomain: 'demo-declara-firmas.firebaseapp.com',
      storageBucket: 'demo-declara-firmas.appspot.com',
    ),
  );

  await FirebaseAuth.instance.useAuthEmulator(
    '127.0.0.1',
    9099,
  );

  FirebaseFirestore.instance.useFirestoreEmulator(
    '127.0.0.1',
    8080,
  );

  FirebaseFunctions.instanceFor(
    region: 'us-east1',
  ).useFunctionsEmulator('127.0.0.1', 5001);

  runApp(
    const Directionality(
      textDirection: TextDirection.ltr,
      child: Banner(
        message: 'PRUEBAS LOCALES',
        location: BannerLocation.topEnd,
        color: Colors.red,
        child: DeclaraApp(),
      ),
    ),
  );
}