
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_options.dart';
import 'pages/dashboard.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    runApp(const DeclaraApp());
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

// ============================================================
// MAIN APPLICATION
// ============================================================

class DeclaraApp extends StatelessWidget {
  const DeclaraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DeclaraHorario',
      debugShowCheckedModeBanner: false,

     theme: ThemeData(
  useMaterial3: true,

  fontFamily: 'MyriadPro',

  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF244D72),
  ),

        scaffoldBackgroundColor: const Color(0xFFF3F6FA),

        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
        ),
      ),

      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),

        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }

          if (snapshot.hasError) {
            return Scaffold(
              body: Center(
                child: Text(
                  'Error de autenticación: ${snapshot.error}',
                ),
              ),
            );
          }

          if (snapshot.data == null) {
            return const LoginPage();
          }

          return const Dashboard();
        },
      ),
    );
  }
}

// ============================================================
// LOGIN AND REGISTRATION PAGE
// ============================================================

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController emailController =
      TextEditingController();

  final TextEditingController passwordController =
      TextEditingController();

  final TextEditingController nameController =
      TextEditingController();

  bool isRegistering = false;
  bool isLoading = false;

  String? errorMessage;

  // ==========================================================
  // AUTHENTICATION
  // ==========================================================

  Future<void> submit() async {
    if (isLoading) return;

    final String email = emailController.text.trim();
    final String password = passwordController.text;
    final String name = nameController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        errorMessage = 'Complete el correo y la contraseña.';
      });
      return;
    }

    if (isRegistering && name.isEmpty) {
      setState(() {
        errorMessage = 'Ingrese su nombre completo.';
      });
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      if (isRegistering) {
        await registerUser(
          name: name,
          email: email,
          password: password,
        );
      } else {
        await loginUser(
          email: email,
          password: password,
        );
      }
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;

      setState(() {
        errorMessage = getAuthErrorMessage(error.code);
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        errorMessage = 'Ocurrió un error: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // ==========================================================
  // USER REGISTRATION
  // ==========================================================

  Future<void> registerUser({
    required String name,
    required String email,
    required String password,
  }) async {
    final UserCredential credential =
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    final User? user = credential.user;

    if (user == null) {
      throw StateError(
        'No se pudo obtener la información del usuario.',
      );
    }

    await user.updateDisplayName(name);

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .set({
      'name': name,
      'email': email,
      'role': 'declarante',
      'unit': '',
      'identification': '',
      'phone': '',
    });
  }

  // ==========================================================
  // USER LOGIN
  // ==========================================================

  Future<void> loginUser({
    required String email,
    required String password,
  }) async {
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  // ==========================================================
  // AUTHENTICATION ERROR MESSAGES
  // ==========================================================

  String getAuthErrorMessage(String code) {
    switch (code) {
      case 'invalid-email':
        return 'El correo electrónico no es válido.';

      case 'email-already-in-use':
        return 'Este correo electrónico ya está registrado.';

      case 'weak-password':
        return 'La contraseña es demasiado débil.';

      case 'user-not-found':
        return 'No existe una cuenta con este correo.';

      case 'wrong-password':
        return 'La contraseña es incorrecta.';

      case 'invalid-credential':
        return 'El correo o la contraseña son incorrectos.';

      case 'network-request-failed':
        return 'No se pudo conectar a Internet.';

      case 'too-many-requests':
        return 'Demasiados intentos. Intente nuevamente más tarde.';

      default:
        return 'Error de autenticación: $code';
    }
  }

  // ==========================================================
  // SWITCH BETWEEN LOGIN AND REGISTRATION
  // ==========================================================

  void toggleAuthMode() {
    setState(() {
      isRegistering = !isRegistering;
      errorMessage = null;
    });
  }

  // ==========================================================
  // CLEAN UP CONTROLLERS
  // ==========================================================

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    nameController.dispose();

    super.dispose();
  }

  // ==========================================================
  // USER INTERFACE
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 430,
            ),
            child: Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.fact_check_outlined,
                      size: 54,
                      color: Color(0xFF244D72),
                    ),

                    const SizedBox(height: 12),

                    Text(
                      'DeclaraHorario',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),

                    const SizedBox(height: 8),

                    const Text(
                      'Universidad de Costa Rica · Sede del Sur',
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 28),

                    if (isRegistering) ...[
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Nombre completo',
                          prefixIcon: Icon(
                            Icons.person_outline,
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),
                    ],

                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [
                        AutofillHints.email,
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Correo electrónico',
                        prefixIcon: Icon(
                          Icons.email_outlined,
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Contraseña',
                        prefixIcon: Icon(
                          Icons.lock_outline,
                        ),
                      ),
                    ),

                    if (errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.red,
                          ),
                        ),
                      ),

                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: isLoading ? null : submit,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                          ),
                          child: isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  isRegistering
                                      ? 'Crear cuenta'
                                      : 'Ingresar',
                                ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    TextButton(
                      onPressed: isLoading ? null : toggleAuthMode,
                      child: Text(
                        isRegistering
                            ? 'Ya tengo una cuenta'
                            : 'Crear una cuenta',
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
}
