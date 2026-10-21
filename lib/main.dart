
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../firebase_options.dart';
import '../pages/dashboard.dart';

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

      locale: const Locale('es', 'ES'),
supportedLocales: const [
  Locale('es', 'ES'),
],
localizationsDelegates: const [
  GlobalMaterialLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
],

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
  bool showPassword = false;
  bool rememberEmail = false;

  String? errorMessage;

  // Validación del nombre antes de crear la cuenta.
  // Acepta nombres compuestos, tildes, ñ, diéresis,
  // apóstrofos y guiones usados en apellidos.
  String? validateFullName(String name) {
    if (name.isEmpty) {
      return 'Ingresá tu nombre y apellidos completos.';
    }
    if (name.length < 5 || name.length > 100) {
      return 'El nombre completo debe tener entre 5 y 100 caracteres.';
    }

    final words = name.split(' ');
    if (words.length < 2) {
      return 'Ingresá al menos un nombre y un apellido.';
    }

    final validWord = RegExp(
      r"^[A-Za-zÁÉÍÓÚÜÑáéíóúüñÀÈÌÒÙàèìòùÂÊÎÔÛâêîôûÄËÏÖäëïöÇç]+(?:[A-Za-zÁÉÍÓÚÜÑáéíóúüñÀÈÌÒÙàèìòùÂÊÎÔÛâêîôûÄËÏÖäëïöÇç]+)*$",
    );
    if (words.any((word) => !validWord.hasMatch(word))) {
      return 'Use únicamente letras.';
    }

    // No es posible comprobar la identidad real solo con una expresión regular.
    return null;
  }

  // ==========================================================
  // AUTHENTICATION
  // ==========================================================

  Future<void> submit() async {
    if (isLoading) return;

    final String email = emailController.text.trim();
    final String password = passwordController.text;
    final String name = nameController.text.trim().replaceAll(RegExp(r'\s+'), ' ');

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        errorMessage = 'Complete el correo y la contraseña.';
      });
      return;
    }

    if (isRegistering) {
      final nameError = validateFullName(name);
      if (nameError != null) {
        setState(() => errorMessage = nameError);
        return;
      }
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
    final normalizedName = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    final nameError = validateFullName(normalizedName);
    if (nameError != null) {
      throw StateError(nameError);
    }

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

    await user.updateDisplayName(normalizedName);

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .set({
      'name': normalizedName,
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
      if (!rememberEmail) emailController.clear();
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

  Future<void> resetPassword() async {
    final email = emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => errorMessage = 'Ingresá tu correo para recuperar la contraseña.');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Si el correo está registrado, recibirás instrucciones para recuperar tu contraseña.'),
      ));
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() => errorMessage = getAuthErrorMessage(error.code));
    }
  }

  InputDecoration _fieldDecoration(String hint, IconData icon, {Widget? suffix}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF8399BA)),
      prefixIcon: Icon(icon, color: const Color(0xFF103C80)),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFFF8FBFF),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFBBD6F6)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF0076EF), width: 1.6),
      ),
    );
  }

  Widget _label(String value) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(value, style: const TextStyle(
        fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF092D6D),
      )),
    ),
  );

  Widget _authCard() {
    const navy = Color(0xFF092D6D);
    return Container(
      width: 490,
      padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 32),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(color: Color(0x180A3E79), blurRadius: 32, offset: Offset(0, 12))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: Image.asset(
            'assets/images/logo_declara_ucr.png',
            height: 76, fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Text('DeclaraUCR',
              style: TextStyle(color: navy, fontSize: 30, fontWeight: FontWeight.bold)),
          )),
          const SizedBox(height: 28),
          Text(isRegistering ? 'Crear cuenta' : 'Iniciar sesión',
            style: const TextStyle(fontSize: 28, color: navy, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(isRegistering
              ? 'Completá tus datos para registrarte.'
              : 'Ingresá tus credenciales para continuar.',
            style: const TextStyle(fontSize: 15, color: Color(0xFF758CB0))),
          const SizedBox(height: 24),
          if (isRegistering) ...[
            _label('Nombre y apellidos completos'),
            TextField(
              controller: nameController,
              textCapitalization: TextCapitalization.words,
              decoration: _fieldDecoration('Nombre y apellidos', Icons.person_outline),
            ),
            const SizedBox(height: 17),
          ],
          _label('Correo electrónico'),
          TextField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: _fieldDecoration('nombre@ucr.ac.cr', Icons.mail_outline),
          ),
          const SizedBox(height: 17),
          _label('Contraseña'),
          TextField(
            controller: passwordController,
            obscureText: !showPassword,
            onSubmitted: (_) => submit(),
            decoration: _fieldDecoration('Ingresá tu contraseña', Icons.lock_outline,
              suffix: IconButton(
                tooltip: showPassword ? 'Ocultar contraseña' : 'Mostrar contraseña',
                onPressed: () => setState(() => showPassword = !showPassword),
                icon: Icon(showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: navy),
              ),
            ),
          ),
          if (!isRegistering) ...[
            const SizedBox(height: 12),
            Row(children: [
              Checkbox(
                value: rememberEmail,
                visualDensity: VisualDensity.compact,
                activeColor: const Color(0xFF0077ED),
                onChanged: (value) => setState(() => rememberEmail = value ?? false),
              ),
              const Expanded(child: Text('Conservar correo al cambiar de pantalla',
                style: TextStyle(color: navy, fontSize: 13))),
              TextButton(onPressed: isLoading ? null : resetPassword,
                child: const Text('¿Olvidaste tu contraseña?',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
            ]),
          ],
          if (errorMessage != null) Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(errorMessage!, style: const TextStyle(color: Colors.red)),
          ),
          const SizedBox(height: 19),
          SizedBox(height: 52, child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0069D5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
            onPressed: isLoading ? null : submit,
            child: isLoading
              ? const SizedBox(width: 22, height: 22,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(isRegistering ? 'Crear cuenta' : 'Ingresar al sistema',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 15),
                  const Icon(Icons.arrow_forward),
                ]),
          )),
          const SizedBox(height: 22),
          Row(children: [
            const Expanded(child: Divider(color: Color(0xFFCCE0F7))),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(isRegistering ? '¿Ya tenés una cuenta?' : '¿No tenés una cuenta?',
                style: const TextStyle(fontSize: 13, color: navy))),
            const Expanded(child: Divider(color: Color(0xFFCCE0F7))),
          ]),
          const SizedBox(height: 15),
          OutlinedButton(
            onPressed: isLoading ? null : toggleAuthMode,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              side: const BorderSide(color: Color(0xFF0076EF), width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(isRegistering ? 'Iniciar sesión' : 'Registrarse',
              style: const TextStyle(color: Color(0xFF0071E8), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWide = screenWidth >= 1200;
    return Scaffold(
      body: Stack(children: [
        const Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFD7EFFF), Color(0xFFF8FCFF), Color(0xFFE5F4FF)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
        ))),
        if (isWide) Positioned(
          left: 0, top: 0, bottom: 0,
          width: screenWidth * 0.34,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Aplicar el difuminado sobre el rectángulo REAL de la imagen,
              // no sobre el espacio vacío que deja BoxFit.contain arriba.
              // Un poco más ancho para mostrar mejor los pétalos, conservando el difuminado.
              const imageRatio = 0.49;
              final imageWidth = constraints.maxWidth < constraints.maxHeight * imageRatio
                  ? constraints.maxWidth
                  : constraints.maxHeight * imageRatio;
              final imageHeight = imageWidth / imageRatio;
              return Align(
                alignment: Alignment.bottomLeft,
                child: SizedBox(
                  width: imageWidth,
                  height: imageHeight,
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (bounds) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
                      stops: [0.0, 0.11, 0.94, 1.0],
                    ).createShader(bounds),
                    child: ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (bounds) => const LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [Colors.white, Colors.white, Colors.transparent],
                        stops: [0.0, 0.72, 1.0],
                      ).createShader(bounds),
                      child: Image.asset(
                        'assets/images/login_girasol_fondo.png',
                        fit: BoxFit.fill,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        SafeArea(child: Center(child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: isWide ? 40 : 20, vertical: 28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1300),
            child: isWide
              ? Row(children: [
                  Expanded(child: Padding(
                    padding: EdgeInsets.only(left: screenWidth * 0.235, right: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        SizedBox(width: 58, child: Divider(color: Color(0xFF0074EC), thickness: 4)),
                        SizedBox(height: 18),
                        Text('Sistema de\ndeclaración de horarios',
                          style: TextStyle(fontSize: 31, fontWeight: FontWeight.w800,
                            color: Color(0xFF082C70), height: 1.14)),
                        SizedBox(height: 14),
                        Text('Gestión universitaria eficiente\nal servicio de la comunidad.',
                          style: TextStyle(fontSize: 20, color: Color(0xFF738AAE))),
                      ],
                    ),
                  )),
                  const SizedBox(width: 32),
                  _authCard(),
                ])
              : Center(child: _authCard()),
          ),
        ))),
      ]),
    );
  }
}
