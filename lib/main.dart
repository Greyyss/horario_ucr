import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'firebase_options.dart';
import 'pages/dashboard.dart';
import 'services/personal_data_validator.dart';

final registroPadronEnCurso = ValueNotifier<bool>(false);
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

          final uid = snapshot.data!.uid;

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            key: ValueKey(uid),
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .snapshots(),
            builder: (context, perfil) {
              if (perfil.hasError) {
                return Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed: () => FirebaseAuth.instance.signOut(),
                      child: Text(
                          'Error al leer el perfil: ${perfil.error}\nCerrar sesión'),
                    ),
                  ),
                );
              }

              if (!perfil.hasData) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              if (perfil.data!.exists) {
                return const Dashboard();
              }

              return ValueListenableBuilder<bool>(
                valueListenable: registroPadronEnCurso,
                builder: (context, guardando, child) {
                  if (guardando) {
                    return const Scaffold(
                      body: Center(child: CircularProgressIndicator()),
                    );
                  }

                  return const RegistroPadronPage();
                },
              );
            },
          );
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
  final TextEditingController emailController = TextEditingController();

  final TextEditingController passwordController = TextEditingController();

  final TextEditingController confirmPasswordController =
      TextEditingController();

    static const consultaPrevia =
      bool.fromEnvironment('USE_FIREBASE_EMULATORS') ||
      bool.fromEnvironment('ENABLE_PADRON_AUTOCOMPLETE');
  final cedulaRegistro = TextEditingController();
  final nombresRegistro = TextEditingController();
  final apellidosRegistro = TextEditingController();
  String? nombreConsultado;
  int revisionConsulta = 0;
  bool consultando = false;

  Future<void> consultarCedula(String cedula) async {
    final revision = ++revisionConsulta;
    final valida = RegExp(r'^[0-9]{9}$').hasMatch(cedula);

    setState(() {
      nombresRegistro.clear();
      apellidosRegistro.clear();
      nombreConsultado = null;
      errorMessage = null;
      consultando = valida;
    });
    if (!valida) return;

    try {
      final resultado = await FirebaseFunctions.instanceFor(region: 'us-east1')
          .httpsCallable('consultarPadronRegistro')
          .call<Map<String, dynamic>>({'cedula': cedula});
      if (!mounted || revision != revisionConsulta) return;

      final datos = resultado.data;
      setState(() {
        nombresRegistro.text = datos['nombres'] as String;
        apellidosRegistro.text = datos['apellidos'] as String;
        nombreConsultado = datos['nombreCompleto'] as String;
      });
    } on FirebaseFunctionsException catch (e) {
      if (!mounted || revision != revisionConsulta) return;
      setState(
          () => errorMessage = e.message ?? 'No se pudo consultar el padrón.');
    } catch (_) {
      if (!mounted || revision != revisionConsulta) return;
      setState(() => errorMessage = 'No se pudo consultar el padrón.');
    } finally {
      if (mounted && revision == revisionConsulta) {
        setState(() => consultando = false);
      }
    }
  }

  bool isRegistering = false;
  bool isLoading = false;
  bool showPassword = false;
  bool showConfirmPassword = false;
  bool rememberEmail = false;

  String? errorMessage;

  // ==========================================================
  // AUTHENTICATION
  // ==========================================================

  Future<void> submit() async {
    if (isLoading) return;

    final email = emailController.text.trim();
    final password = passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        errorMessage = 'Complete el correo y la contraseña.';
      });
      return;
    }

    // Confirmar contraseña únicamente al registrarse.
    if (isRegistering) {
      if (consultaPrevia && (consultando || nombreConsultado == null)) {
        setState(
            () => errorMessage = 'Consultá tu cédula antes de registrarte.');
        return;
      }

      final confirmPassword = confirmPasswordController.text;

      if (confirmPassword.isEmpty) {
        setState(() {
          errorMessage = 'Confirmá tu contraseña.';
        });
        return;
      }

      if (password != confirmPassword) {
        setState(() {
          errorMessage = 'Las contraseñas no coinciden.';
        });
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
          } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      setState(() {
        errorMessage = error.message ?? 'No se pudo comprobar la cédula.';
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
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim();
    final emailError = PersonalDataValidator.email(normalizedEmail);

    if (emailError != null) {
      throw StateError(emailError);
    }

    final cedula = cedulaRegistro.text.trim();
    final nombre = nombreConsultado;

    final completarAutomaticamente = consultaPrevia && nombre != null;
    registroPadronEnCurso.value = completarAutomaticamente;

    try {
            if (completarAutomaticamente) {
        await FirebaseFunctions.instanceFor(region: 'us-east1')
            .httpsCallable('consultarPadronRegistro')
            .call<Map<String, dynamic>>({
          'accion': 'verificarDisponibilidad',
          'cedula': cedula,
        });
      }
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );

      if (completarAutomaticamente) {
        await FirebaseFunctions.instanceFor(region: 'us-east1')
            .httpsCallable('registroPadron')
            .call<Map<String, dynamic>>({
          'accion': 'confirmar',
          'cedula': cedula,
          'nombreMostrado': nombre,
        });
      }
    } finally {
      registroPadronEnCurso.value = false;
    }
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
      revisionConsulta++;
      cedulaRegistro.clear();
      nombresRegistro.clear();
      apellidosRegistro.clear();
      nombreConsultado = null;
      consultando = false;

      if (!rememberEmail) {
        emailController.clear();
      }

      passwordController.clear();
      confirmPasswordController.clear();

      showPassword = false;
      showConfirmPassword = false;
      errorMessage = null;
    });
  }

  // ==========================================================
  // CLEAN UP CONTROLLERS
  // ==========================================================

  @override
  void dispose() {
    cedulaRegistro.dispose();
    nombresRegistro.dispose();
    apellidosRegistro.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> resetPassword() async {
    final email = emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() =>
          errorMessage = 'Ingresá tu correo para recuperar la contraseña.');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Si el correo está registrado, recibirás instrucciones para recuperar tu contraseña.'),
      ));
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() => errorMessage = getAuthErrorMessage(error.code));
    }
  }

  InputDecoration _fieldDecoration(String hint, IconData icon,
      {Widget? suffix}) {
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
          child: Text(value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF092D6D),
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
        boxShadow: const [
          BoxShadow(
              color: Color(0x180A3E79), blurRadius: 32, offset: Offset(0, 12))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
              child: Image.asset(
            'assets/images/logo_declara_ucr.png',
            height: 76,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Text('DeclaraUCR',
                style: TextStyle(
                    color: navy, fontSize: 30, fontWeight: FontWeight.bold)),
          )),
          const SizedBox(height: 28),
          Text(isRegistering ? 'Crear cuenta' : 'Iniciar sesión',
              style: const TextStyle(
                  fontSize: 28, color: navy, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
              isRegistering
                  ? (consultaPrevia
                      ? 'Ingresá tu cédula para completar tus datos.'
                      : 'Creá tu cuenta para continuar con la consulta de cédula.')
                  : 'Ingresá tus credenciales para continuar.',
              style: const TextStyle(fontSize: 15, color: Color(0xFF758CB0))),
          const SizedBox(height: 24),
          if (isRegistering && consultaPrevia) ...[
            _label('Cédula'),
            TextField(
              controller: cedulaRegistro,
              enabled: !isLoading,
              keyboardType: TextInputType.number,
              onChanged: (valor) => consultarCedula(valor.trim()),
              decoration: _fieldDecoration(
                '9 dígitos, sin guiones',
                Icons.badge_outlined,
              ),
            ),
            if (consultando) const LinearProgressIndicator(),
            const SizedBox(height: 17),
            _label('Nombres'),
            TextField(
              controller: nombresRegistro,
              readOnly: true,
              decoration: _fieldDecoration('Nombres', Icons.person_outline),
            ),
            const SizedBox(height: 17),
            _label('Apellidos'),
            TextField(
              controller: apellidosRegistro,
              readOnly: true,
              decoration: _fieldDecoration('Apellidos', Icons.person_outline),
            ),
            const SizedBox(height: 17),
          ],
          _label('Correo electrónico'),
          TextField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration:
                _fieldDecoration('nombre@ucr.ac.cr', Icons.mail_outline),
          ),
          const SizedBox(height: 17),
          _label('Contraseña'),
          TextField(
            controller: passwordController,
            obscureText: !showPassword,
            enableSuggestions: false,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            decoration: _fieldDecoration(
              'Ingresá tu contraseña',
              Icons.lock_outline,
              suffix: IconButton(
                tooltip:
                    showPassword ? 'Ocultar contraseña' : 'Mostrar contraseña',
                onPressed: () => setState(() => showPassword = !showPassword),
                icon: Icon(
                    showPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: navy),
              ),
            ),
          ),
          if (isRegistering) ...[
            const SizedBox(height: 17),
            _label('Confirmar contraseña'),
            TextField(
              controller: confirmPasswordController,
              obscureText: !showConfirmPassword,
              enableSuggestions: false,
              autocorrect: false,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => submit(),
              decoration: _fieldDecoration(
                'Ingresá nuevamente tu contraseña',
                Icons.lock_outline,
                suffix: IconButton(
                  tooltip: showConfirmPassword
                      ? 'Ocultar confirmación de contraseña'
                      : 'Mostrar confirmación de contraseña',
                  onPressed: () {
                    setState(() {
                      showConfirmPassword = !showConfirmPassword;
                    });
                  },
                  icon: Icon(
                    showConfirmPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: navy,
                  ),
                ),
              ),
            ),
          ],
          if (!isRegistering) ...[
            const SizedBox(height: 12),
            Row(children: [
              Checkbox(
                value: rememberEmail,
                visualDensity: VisualDensity.compact,
                activeColor: const Color(0xFF0077ED),
                onChanged: (value) =>
                    setState(() => rememberEmail = value ?? false),
              ),
              const Expanded(
                  child: Text('Conservar correo al cambiar de pantalla',
                      style: TextStyle(color: navy, fontSize: 13))),
              TextButton(
                  onPressed: isLoading ? null : resetPassword,
                  child: const Text('¿Olvidaste tu contraseña?',
                      style: TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w600))),
            ]),
          ],
          if (errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(errorMessage!,
                  style: const TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 19),
          SizedBox(
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0069D5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                ),
                onPressed: isLoading ||
                        (isRegistering &&
                            consultaPrevia &&
                            (consultando || nombreConsultado == null))
                    ? null
                    : submit,
                child: isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                            Text(
                                isRegistering
                                    ? 'Crear cuenta'
                                    : 'Ingresar al sistema',
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 15),
                            const Icon(Icons.arrow_forward),
                          ]),
              )),
          const SizedBox(height: 22),
          Row(children: [
            const Expanded(child: Divider(color: Color(0xFFCCE0F7))),
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                    isRegistering
                        ? '¿Ya tenés una cuenta?'
                        : '¿No tenés una cuenta?',
                    style: const TextStyle(fontSize: 13, color: navy))),
            const Expanded(child: Divider(color: Color(0xFFCCE0F7))),
          ]),
          const SizedBox(height: 15),
          OutlinedButton(
            onPressed: isLoading ? null : toggleAuthMode,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              side: const BorderSide(color: Color(0xFF0076EF), width: 1.5),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(isRegistering ? 'Iniciar sesión' : 'Registrarse',
                style: const TextStyle(
                    color: Color(0xFF0071E8), fontWeight: FontWeight.bold)),
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
        const Positioned.fill(
            child: DecoratedBox(
                decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFD7EFFF), Color(0xFFF8FCFF), Color(0xFFE5F4FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ))),
        if (isWide)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: screenWidth * 0.34,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Aplicar el difuminado sobre el rectángulo REAL de la imagen,
                // no sobre el espacio vacío que deja BoxFit.contain arriba.
                // Un poco más ancho para mostrar mejor los pétalos, conservando el difuminado.
                const imageRatio = 0.49;
                final imageWidth =
                    constraints.maxWidth < constraints.maxHeight * imageRatio
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
                        colors: [
                          Colors.transparent,
                          Colors.white,
                          Colors.white,
                          Colors.transparent
                        ],
                        stops: [0.0, 0.11, 0.94, 1.0],
                      ).createShader(bounds),
                      child: ShaderMask(
                        blendMode: BlendMode.dstIn,
                        shaderCallback: (bounds) => const LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Colors.white,
                            Colors.white,
                            Colors.transparent
                          ],
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
        SafeArea(
            child: Center(
                child: SingleChildScrollView(
          padding:
              EdgeInsets.symmetric(horizontal: isWide ? 40 : 20, vertical: 28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1300),
            child: isWide
                ? Row(children: [
                    Expanded(
                        child: Padding(
                      padding:
                          EdgeInsets.only(left: screenWidth * 0.235, right: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          SizedBox(
                              width: 58,
                              child: Divider(
                                  color: Color(0xFF0074EC), thickness: 4)),
                          SizedBox(height: 18),
                          Text('Sistema de\ndeclaración de horarios',
                              style: TextStyle(
                                  fontSize: 31,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF082C70),
                                  height: 1.14)),
                          SizedBox(height: 14),
                          Text(
                              'Gestión universitaria eficiente\nal servicio de la comunidad.',
                              style: TextStyle(
                                  fontSize: 20, color: Color(0xFF738AAE))),
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

class RegistroPadronPage extends StatefulWidget {
  const RegistroPadronPage({super.key});

  @override
  State<RegistroPadronPage> createState() => _RegistroPadronPageState();
}

class _RegistroPadronPageState extends State<RegistroPadronPage> {
  final cedulaController = TextEditingController();

  String? nombre;
  String? cedulaConsultada;
  String? error;
  bool cargando = false;

  @override
  void dispose() {
    cedulaController.dispose();
    super.dispose();
  }

  Future<void> ejecutar({required bool confirmar}) async {
    if (cargando) return;

    final cedula = cedulaController.text.trim();

    if (!RegExp(r'^[0-9]{9}$').hasMatch(cedula)) {
      setState(() => error = 'Ingresá una cédula de 9 dígitos.');
      return;
    }

    if (confirmar && (nombre == null || cedulaConsultada != cedula)) {
      setState(() => error = 'Consultá la cédula antes de confirmar.');
      return;
    }

    setState(() {
      cargando = true;
      error = null;
      if (!confirmar) {
        nombre = null;
        cedulaConsultada = null;
      }
    });

    try {
      final funcion = FirebaseFunctions.instanceFor(region: 'us-east1')
          .httpsCallable('registroPadron');

      final resultado = await funcion.call<Map<String, dynamic>>({
        'accion': confirmar ? 'confirmar' : 'consultar',
        'cedula': cedula,
        if (confirmar) 'nombreMostrado': nombre,
      });

      if (!mounted || confirmar) return;

      setState(() {
        nombre = resultado.data['nombre'] as String;
        cedulaConsultada = cedula;
      });
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        setState(() {
          error = e.message ?? 'No se pudo completar la operación.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'No se pudo completar la operación.');
      }
    } finally {
      if (mounted) setState(() => cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const azul = Color(0xFF0069D5);
    const azulOscuro = Color(0xFF10356B);
    final theme = Theme.of(context);
    final nombreEncontrado = nombre;
    final mensajeError = error;

    return Scaffold(
      body: Container(
        constraints: const BoxConstraints.expand(),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFD7EFFF),
              Color(0xFFF8FCFF),
              Color(0xFFE5F4FF),
            ],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const margen = 16.0;
              final altoDisponible = constraints.maxHeight - margen * 2;

              return SingleChildScrollView(
                padding: const EdgeInsets.all(margen),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: altoDisponible > 0 ? altoDisponible : 0,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Card(
                        margin: EdgeInsets.zero,
                        elevation: 0,
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                          side: const BorderSide(color: Color(0xFFDCE8F4)),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(
                            constraints.maxWidth < 480 ? 24 : 36,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Image.asset(
                                'assets/images/logo_declara_ucr.png',
                                height: 72,
                                fit: BoxFit.contain,
                                semanticLabel: 'DeclaraUCR',
                                errorBuilder: (context, error, stackTrace) =>
                                    const Text(
                                  'DeclaraUCR',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: azulOscuro,
                                    fontSize: 26,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                'Completar registro',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  color: azulOscuro,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Ingresá tu cédula de 9 dígitos, sin guiones.',
                                style: TextStyle(color: Color(0xFF526681)),
                              ),
                              const SizedBox(height: 20),
                              TextField(
                                controller: cedulaController,
                                enabled: !cargando,
                                keyboardType: TextInputType.number,
                                textInputAction: TextInputAction.search,
                                onSubmitted: cargando
                                    ? null
                                    : (_) => ejecutar(confirmar: false),
                                onChanged: (_) => setState(() {
                                  nombre = null;
                                  cedulaConsultada = null;
                                  error = null;
                                }),
                                decoration: const InputDecoration(
                                  labelText: 'Cédula',
                                  prefixIcon: Icon(Icons.badge_outlined),
                                  filled: true,
                                  fillColor: Color(0xFFF4F8FC),
                                ),
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: cargando
                                    ? null
                                    : () => ejecutar(confirmar: false),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: azulOscuro,
                                  minimumSize: const Size(0, 48),
                                ),
                                icon: const Icon(Icons.search),
                                label: const Text('Consultar cédula'),
                              ),
                              if (cargando) ...[
                                const SizedBox(height: 16),
                                const LinearProgressIndicator(),
                              ],
                              if (mensajeError != null) ...[
                                const SizedBox(height: 16),
                                Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    mensajeError,
                                    style: TextStyle(
                                      color: theme.colorScheme.error,
                                    ),
                                  ),
                                ),
                              ],
                              if (nombreEncontrado != null) ...[
                                const SizedBox(height: 20),
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEEF6FF),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Nombre registrado en el padrón',
                                        style: TextStyle(color: azulOscuro),
                                      ),
                                      const SizedBox(height: 6),
                                      SelectableText(
                                        nombreEncontrado,
                                        style: const TextStyle(
                                          color: azulOscuro,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Al confirmar, tu nombre y tu cédula quedan '
                                  'registrados y se bloquea su edición.',
                                ),
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  onPressed: cargando
                                      ? null
                                      : () => ejecutar(confirmar: true),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: azul,
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size(0, 48),
                                  ),
                                  icon: const Icon(Icons.check),
                                  label: const Text('Confirmar registro'),
                                ),
                              ],
                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: cargando
                                    ? null
                                    : () => FirebaseAuth.instance.signOut(),
                                child: const Text('Cerrar sesión'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
