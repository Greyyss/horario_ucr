import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'declara_app.dart';

export 'declara_app.dart' show DeclaraApp;
export 'pages/login_page.dart' show LoginPage;
export 'pages/registro_padron_page.dart' show RegistroPadronPage;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const usarEmuladores = bool.fromEnvironment('USE_FIREBASE_EMULATORS');
  const habilitarPadron = bool.fromEnvironment('ENABLE_PADRON_AUTOCOMPLETE');

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    if (usarEmuladores) {
      await FirebaseAuth.instance.useAuthEmulator('127.0.0.1', 9099);
      FirebaseFirestore.instance.useFirestoreEmulator('127.0.0.1', 8080);
      FirebaseFunctions.instanceFor(region: 'us-east1')
          .useFunctionsEmulator('127.0.0.1', 5001);
    }

    runApp(const DeclaraApp());

    if (habilitarPadron && !usarEmuladores) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await FirebaseAppCheck.instance.activate(
            webProvider: ReCaptchaEnterpriseProvider('6LfySBwuAAAAAA1VQllwG09gmsEvtTsVgq8SZQnR'),
          );
        } catch (error) {
          debugPrint('App Check falló: $error');
        }
      });
    }
  } catch (error) {
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SelectableText(
                'Firebase todavía no está configurado.\n\n'
                'Desde esta carpeta ejecutá:\n'
                'flutterfire configure '
                '--project=declarahorario-ucr-cff7a '
                '--platforms=web\n\n'
                'Error: $error',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
