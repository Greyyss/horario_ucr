import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../services/personal_data_validator.dart';

final registroPadronEnCurso = ValueNotifier<bool>(false);

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
        () => errorMessage = e.message ?? 'No se pudo consultar el padrón.',
      );
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
          () => errorMessage = 'Consultá tu cédula antes de registrarte.',
        );
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
        await registerUser(email: email, password: password);
      } else {
        await loginUser(email: email, password: password);
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

      emailController.clear();

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
      setState(
        () => errorMessage = 'Ingresá tu correo para recuperar la contraseña.',
      );
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Si el correo está registrado, recibirás instrucciones para recuperar tu contraseña.',
          ),
        ),
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() => errorMessage = getAuthErrorMessage(error.code));
    }
  }

  InputDecoration _fieldDecoration(String hint, {Widget? suffix}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF8399BA)),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      suffixIcon: suffix,
      suffixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      filled: true,
      fillColor: Colors.white,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFB5C2D0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF0076EF), width: 1.6),
      ),
    );
  }

  Widget _label(String value) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        value,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: Color(0xFF092D6D),
        ),
      ),
    ),
  );

  Widget _fieldColumn(List<Widget> fields) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: fields);

  Widget _registrationProgress() {
    return ListenableBuilder(
      listenable: Listenable.merge([
        emailController,
        passwordController,
        confirmPasswordController,
      ]),
      builder: (context, child) {
        final password = passwordController.text;
        final completed = [
          if (consultaPrevia) nombreConsultado != null,
          emailController.text.trim().isNotEmpty &&
              PersonalDataValidator.email(emailController.text.trim()) == null,
          password.isNotEmpty,
          password.isNotEmpty && confirmPasswordController.text == password,
        ];
        final count = completed.where((done) => done).length;

        return TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: count / completed.length),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 280),
          curve: Curves.easeOut,
          builder: (context, value, child) => LinearProgressIndicator(
            value: value,
            minHeight: 4,
            borderRadius: BorderRadius.circular(4),
            color: const Color(0xFF1974B8),
            backgroundColor: const Color(0xFFD4E5F3),
            semanticsLabel: 'Progreso del registro',
            semanticsValue: '$count de ${completed.length} campos completados',
          ),
        );
      },
    );
  }

  Widget _authCard({bool twoColumns = false}) {
    const navy = Color(0xFF092D6D);
    final identityFields = <Widget>[
      _label('Cédula'),
      TextField(
        controller: cedulaRegistro,
        enabled: !isLoading,
        keyboardType: TextInputType.number,
        onChanged: (valor) => consultarCedula(valor.trim()),
        decoration: _fieldDecoration('9 dígitos, sin guiones'),
      ),
      if (consultando) const LinearProgressIndicator(),
      const SizedBox(height: 17),
      _label('Nombres'),
      TextField(
        controller: nombresRegistro,
        readOnly: true,
        decoration: _fieldDecoration('Nombres'),
      ),
      const SizedBox(height: 17),
      _label('Apellidos'),
      TextField(
        controller: apellidosRegistro,
        readOnly: true,
        decoration: _fieldDecoration('Apellidos'),
      ),
    ];
    final credentialFields = <Widget>[
      _label('Correo electrónico'),
      TextField(
        controller: emailController,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        decoration: _fieldDecoration('nombre@ucr.ac.cr'),
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
          suffix: IconButton(
            tooltip: showPassword ? 'Ocultar contraseña' : 'Mostrar contraseña',
            onPressed: () => setState(() => showPassword = !showPassword),
            icon: Icon(
              showPassword
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: navy,
            ),
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
    ];

    final logo = Image.asset(
      'assets/images/logo_declara_ucr.png',
      height: 84,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => const Text(
        'DeclaraUCR',
        style: TextStyle(
          color: navy,
          fontSize: 30,
          fontWeight: FontWeight.bold,
        ),
      ),
    );

    return Container(
      width: twoColumns ? 820 : 490,
      padding: EdgeInsets.symmetric(
        horizontal: twoColumns ? 24 : 34,
        vertical: twoColumns ? 22 : 32,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDCE5EE)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(alignment: Alignment.center, child: logo),
          if (isRegistering) ...[
            const SizedBox(height: 10),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: _registrationProgress(),
              ),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 12),
          Text(
            isRegistering ? 'Crear cuenta' : 'Iniciar sesión',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 28,
              color: navy,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          if (isRegistering)
            Text(
              consultaPrevia
                  ? 'Ingresá tu cédula para completar tus datos.'
                  : 'Creá tu cuenta para continuar con la consulta de cédula.',
              style: const TextStyle(fontSize: 15, color: Color(0xFF758CB0)),
            ),
          const SizedBox(height: 20),
          if (isRegistering) ...[
            const Divider(height: 1, color: Color(0xFFDCE5EE)),
            const SizedBox(height: 18),
          ],
          if (twoColumns)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _fieldColumn(identityFields)),
                const SizedBox(width: 20),
                Expanded(child: _fieldColumn(credentialFields)),
              ],
            )
          else ...[
            if (isRegistering && consultaPrevia) ...[
              ...identityFields,
              const SizedBox(height: 17),
            ],
            ...credentialFields,
          ],
          if (!isRegistering) ...[
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: isLoading ? null : resetPassword,
                child: const Text('¿Olvidaste tu contraseña?'),
              ),
            ),
          ],
          if (errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          const SizedBox(height: 19),
          SizedBox(
            height: isRegistering ? 52 : 44,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: isRegistering ? navy : const Color(0xFF02408A),
                foregroundColor: Colors.white,
                disabledBackgroundColor: isRegistering
                    ? const Color(0xFFE8EDF3)
                    : null,
                disabledForegroundColor: isRegistering
                    ? const Color(0xFF53657A)
                    : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed:
                  isLoading ||
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
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(isRegistering ? 'Crear cuenta' : 'Ingresar'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWide = screenWidth >= 1200;
    final twoColumns = isRegistering && consultaPrevia && screenWidth >= 640;
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFFD7EFFF),
                    Color(0xFFF8FCFF),
                    Color(0xFFE5F4FF),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          if (!isRegistering)
            const Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _LoginBackgroundPainter()),
              ),
            ),
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
                  final imageRatio = isRegistering ? 0.49 : 0.59;
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
                            Colors.transparent,
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
                              Colors.transparent,
                            ],
                            stops: [0.0, 0.65, 0.94],
                          ).createShader(bounds),
                          child: isRegistering
                              ? _sunflowerImage()
                              : ClipRect(
                                  child: _WindSunflower(
                                    child: _sunflowerImage(),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          if (isWide && twoColumns)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: (screenWidth - 820) / 2,
              child: const IgnorePointer(
                child: CustomPaint(
                  painter: _RegistrationBackgroundPainter(),
                  child: Stack(
                    children: [
                      Positioned(
                        right: -30,
                        bottom: -20,
                        width: 178,
                        child: _RotatingSunflower(),
                      ),
                      Positioned(
                        right: 40,
                        bottom: 164,
                        width: 82,
                        child: _RotatingSunflower(
                          period: Duration(seconds: 48),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (isWide && !isRegistering)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: (screenWidth - 490) / 2,
              child: const IgnorePointer(child: _LoginGarden()),
            ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: isWide ? 40 : 20,
                  vertical: 28,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1300),
                  child: twoColumns
                      ? Center(child: _authCard(twoColumns: true))
                      : isWide && !isRegistering
                      ? Row(
                          children: [
                            const Expanded(child: SizedBox.shrink()),
                            _authCard(),
                            const Expanded(child: SizedBox.shrink()),
                          ],
                        )
                      : isWide
                      ? Row(
                          children: [
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(
                                  left:
                                      screenWidth *
                                      (isRegistering ? 0.235 : 0.21),
                                  right: 12,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    SizedBox(
                                      width: 58,
                                      child: Divider(
                                        color: Color(0xFF0074EC),
                                        thickness: 4,
                                      ),
                                    ),
                                    SizedBox(height: 18),
                                    Text(
                                      'Sistema de\ndeclaración de horarios',
                                      style: TextStyle(
                                        fontSize: 31,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF082C70),
                                        height: 1.14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 32),
                            _authCard(),
                          ],
                        )
                      : Center(child: _authCard()),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RegistrationBackgroundPainter extends CustomPainter {
  const _RegistrationBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(size.width, 0);
    canvas.scale(size.width / 100, size.height / 100);

    final lightRibbon = Path()
      ..moveTo(-24, 0)
      ..cubicTo(-5, 27, -38, 56, -92, 100)
      ..lineTo(-62, 100)
      ..cubicTo(-31, 75, -4, 47, 0, 20)
      ..lineTo(0, 0)
      ..close();
    canvas.drawPath(lightRibbon, Paint()..color = const Color(0x3864CAFA));

    final blueRibbon = Path()
      ..moveTo(0, 24)
      ..cubicTo(-9, 60, -27, 79, -63, 100)
      ..lineTo(-41, 100)
      ..cubicTo(-17, 85, -4, 67, 0, 55)
      ..close();
    canvas.drawPath(blueRibbon, Paint()..color = const Color(0x390071DD));
    canvas.restore();

    Offset point(double x, double y) => Offset(size.width * x, size.height * y);
    final upperDot = point(0.58, 0.17);
    final lowerDot = point(0.24, 0.81);
    final lines = Path()
      ..moveTo(size.width, size.height * 0.41)
      ..cubicTo(
        size.width * 0.91,
        size.height * 0.26,
        size.width * 0.72,
        size.height * 0.22,
        upperDot.dx,
        upperDot.dy,
      )
      ..moveTo(size.width, size.height * 0.49)
      ..cubicTo(
        size.width * 0.67,
        size.height * 0.53,
        size.width * 0.51,
        size.height * 0.72,
        lowerDot.dx,
        lowerDot.dy,
      );
    const blue = Color(0xAE0075E8);
    canvas.drawPath(
      lines,
      Paint()
        ..color = blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    final dotPaint = Paint()..color = blue;
    canvas.drawCircle(upperDot, 3.5, dotPaint);
    canvas.drawCircle(lowerDot, 3.5, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _RegistrationBackgroundPainter oldDelegate) =>
      false;
}

class _RotatingSunflower extends StatefulWidget {
  const _RotatingSunflower({this.period = const Duration(seconds: 36)});

  final Duration period;

  @override
  State<_RotatingSunflower> createState() => _RotatingSunflowerState();
}

class _RotatingSunflowerState extends State<_RotatingSunflower>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotation = AnimationController(
    vsync: this,
    duration: widget.period,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _rotation.stop();
    } else if (!_rotation.isAnimating) {
      _rotation.repeat();
    }
  }

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _rotation.drive(Tween<double>(begin: 0, end: -1)),
      child: const Image(
        image: AssetImage('assets/images/girasol_registro.png'),
        excludeFromSemantics: true,
      ),
    );
  }
}

class _LoginBackgroundPainter extends CustomPainter {
  const _LoginBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width, size.height);

    final lowerWave = Path()
      ..moveTo(0.06, 1)
      ..cubicTo(0.38, 0.63, 0.69, 1.04, 1, 0.56)
      ..lineTo(1, 1)
      ..close();

    canvas.drawPath(lowerWave, Paint()..color = const Color(0x346AB4E2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LoginBackgroundPainter oldDelegate) => false;
}

Widget _sunflowerImage() => Image.asset(
  'assets/images/login_girasol_fondo.png',
  fit: BoxFit.fill,
  excludeFromSemantics: true,
);

class _WindSunflower extends StatefulWidget {
  const _WindSunflower({required this.child});

  final Widget child;

  @override
  State<_WindSunflower> createState() => _WindSunflowerState();
}

class _WindSunflowerState extends State<_WindSunflower>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wind = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _wind.reset();
    } else if (!_wind.isAnimating) {
      _wind.repeat();
    }
  }

  @override
  void dispose() {
    _wind.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _wind,
      child: widget.child,
      builder: (context, child) {
        final sway = math.sin(_wind.value * 2 * math.pi) * 0.024;
        return Transform(
          transform: Matrix4.identity()
            ..setEntry(1, 0, sway)
            ..setEntry(0, 0, 1 + sway * 0.7),
          child: child,
        );
      },
    );
  }
}

class _LoginGarden extends StatelessWidget {
  const _LoginGarden();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      label: 'Sistema de Declaración de Horarios',
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => const RadialGradient(
          center: Alignment.topLeft,
          radius: 0.95,
          colors: [Colors.transparent, Colors.transparent, Colors.white],
          stops: [0.0, 0.20, 1.0],
        ).createShader(bounds),
        child: FittedBox(
          fit: BoxFit.fill,
          child: ClipRect(
            child: Align(
              alignment: Alignment.centerRight,
              widthFactor: 619 / 1823,
              child: Image.asset(
                'assets/images/login_lateral_maqueta.png',
                width: 1823,
                height: 863,
                fit: BoxFit.fill,
                excludeFromSemantics: true,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
