import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

class RegistrarDeclarantePage extends StatefulWidget {
  const RegistrarDeclarantePage({super.key});

  @override
  State<RegistrarDeclarantePage> createState() =>
      _RegistrarDeclarantePageState();
}

class _RegistrarDeclarantePageState extends State<RegistrarDeclarantePage> {
  static const _blue = Color(0xFF02408A);
  static const _units = [
    'Sede Rodrigo Facio',
    'Sede de Occidente',
    'Sede del Atlántico',
    'Sede de Guanacaste',
    'Sede del Caribe',
    'Sede del Pacífico',
    'Sede del Sur',
    'Sede Interuniversitaria de Alajuela',
    'Recinto de Tacares',
    'Recinto de Paraíso',
    'Recinto de Guápiles',
    'Recinto de Santa Cruz',
    'Recinto de Siquirres',
  ];

  final _form = GlobalKey<FormState>();
  final _id = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();

  String _names = '';
  String _lastNames = '';
  String? _verifiedId;
  String? _unit;
  String? _lookupError;
  int _lookupRevision = 0;
  bool _lookingUp = false;
  bool _saving = false;

  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'us-east1');

  static final _idPattern = RegExp(r'^\d{9}$');
  static final _phonePattern = RegExp(r'^\d{8}$');
  static final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  @override
  void dispose() {
    _id.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _lookup(String value) async {
    final id = value.trim();
    final revision = ++_lookupRevision;
    final valid = _idPattern.hasMatch(id);
    setState(() {
      _names = '';
      _lastNames = '';
      _verifiedId = null;
      _lookupError = null;
      _lookingUp = valid;
    });
    if (!valid) return;

    try {
      final result = await _functions
          .httpsCallable('consultarPadronRegistro')
          .call<Map<String, dynamic>>({'cedula': id});
      if (!mounted || revision != _lookupRevision) return;
      setState(() {
        _names = (result.data['nombres'] ?? '').toString();
        _lastNames = (result.data['apellidos'] ?? '').toString();
        _verifiedId = id;
        _lookingUp = false;
      });
    } on FirebaseFunctionsException catch (error) {
      if (!mounted || revision != _lookupRevision) return;
      setState(() {
        _lookupError = error.message ?? 'No se pudo consultar el padrón.';
        _lookingUp = false;
      });
    }
  }

  Future<void> _register() async {
    if (_saving || _verifiedId != _id.text.trim()) return;
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final result = await _functions
          .httpsCallable('registrarDeclarante')
          .call<Map<String, dynamic>>({
        'cedula': _id.text.trim(),
        'correo': _email.text.trim(),
        'telefono': _phone.text.trim(),
        'unidad': _unit,
      });
      if (!mounted) return;

      final name = result.data['nombre'];
      _form.currentState!.reset();
      _id.clear();
      _email.clear();
      _phone.clear();
      setState(() {
        _verifiedId = null;
        _names = '';
        _lastNames = '';
        _unit = null;
      });
      _show('Cuenta registrada para $name.');
    } on FirebaseFunctionsException catch (error) {
      if (mounted) _show(error.message ?? 'No se pudo registrar la cuenta.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _show(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  InputDecoration _decoration(String label) => InputDecoration(
        labelText: label,
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      );

  Widget _readOnly(String label, String value) => InputDecorator(
        isEmpty: value.isEmpty,
        decoration: _decoration(label),
        child: Text(value, overflow: TextOverflow.ellipsis),
      );

  double get _progress {
    final completed = [
      _verifiedId != null,
      _emailPattern.hasMatch(_email.text.trim()),
      _phonePattern.hasMatch(_phone.text.trim()),
      _unit != null,
    ].where((done) => done).length;
    return completed / 4;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEAF4FC),
      appBar: AppBar(
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        title: const Text('Registrar declarante'),
      ),
      body: _FondoRegistroDeclarante(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Card(
                color: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: Color(0xFFD5E2EE)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Image.asset(
                            'assets/images/logo_declara_ucr.png',
                            height: 84,
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 380),
                            child: TweenAnimationBuilder<double>(
                              tween: Tween<double>(begin: 0, end: _progress),
                              duration: const Duration(milliseconds: 250),
                              builder: (_, value, __) =>
                                  LinearProgressIndicator(
                                value: value,
                                color: _blue,
                                backgroundColor: const Color(0xFFD5E6F4),
                                semanticsLabel: 'Progreso del registro',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Datos del declarante',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _blue,
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 20),
                        LayoutBuilder(builder: (context, constraints) {
                          final identity = Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextFormField(
                                controller: _id,
                                enabled: !_saving,
                                keyboardType: TextInputType.number,
                                maxLength: 9,
                                decoration: _decoration('Cédula').copyWith(
                                  counterText: '',
                                  errorText: _lookupError,
                                  suffixIcon: _lookingUp
                                      ? const Padding(
                                          padding: EdgeInsets.all(12),
                                          child: SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                        )
                                      : null,
                                ),
                                onChanged: _lookup,
                              ),
                              const SizedBox(height: 12),
                              _readOnly('Nombres', _names),
                              const SizedBox(height: 12),
                              _readOnly('Apellidos', _lastNames),
                            ],
                          );

                          final details = Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextFormField(
                                controller: _email,
                                enabled: !_saving,
                                keyboardType: TextInputType.emailAddress,
                                decoration: _decoration('Correo electrónico'),
                                onChanged: (_) => setState(() {}),
                                validator: (value) =>
                                    _emailPattern.hasMatch((value ?? '').trim())
                                        ? null
                                        : 'Ingresá un correo válido.',
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _phone,
                                enabled: !_saving,
                                keyboardType: TextInputType.phone,
                                decoration: _decoration('Teléfono'),
                                onChanged: (_) => setState(() {}),
                                validator: (value) =>
                                    _phonePattern.hasMatch((value ?? '').trim())
                                        ? null
                                        : 'Ingresá ocho dígitos.',
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                initialValue: _unit,
                                isExpanded: true,
                                decoration: _decoration(
                                    'Unidad académica o administrativa'),
                                items: [
                                  for (final unit in _units)
                                    DropdownMenuItem(
                                      value: unit,
                                      child: Text(unit,
                                          overflow: TextOverflow.ellipsis),
                                    ),
                                ],
                                onChanged: _saving
                                    ? null
                                    : (value) => setState(() => _unit = value),
                                validator: (value) => value == null
                                    ? 'Seleccioná una sede o recinto.'
                                    : null,
                              ),
                            ],
                          );

                          if (constraints.maxWidth < 580) {
                            return Column(
                              children: [
                                identity,
                                const SizedBox(height: 12),
                                details
                              ],
                            );
                          }

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: identity),
                              const SizedBox(width: 20),
                              Expanded(child: details),
                            ],
                          );
                        }),
                        const SizedBox(height: 20),
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: _blue),
                          onPressed:
                              _saving || _lookingUp || _verifiedId == null
                                  ? null
                                  : _register,
                          child: _saving
                              ? const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFF29557D),
                                      ),
                                    ),
                                    SizedBox(width: 10),
                                    Text('Registrando…'),
                                  ],
                                )
                              : const Text('Registrar declarante'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FondoRegistroDeclarante extends StatelessWidget {
  const _FondoRegistroDeclarante({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final showFlowers = width >= 1100;
        final sideWidth = ((width - 860) / 2).clamp(0.0, 420.0).toDouble();

        return Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
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
            ),
            if (showFlowers)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: sideWidth,
                child: IgnorePointer(
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Colors.white, Colors.white, Colors.transparent],
                      stops: [0, 0.65, 1],
                    ).createShader(bounds),
                    child: Image.asset(
                      'assets/images/login_girasol_fondo.png',
                      fit: BoxFit.cover,
                      alignment: Alignment.centerLeft,
                      excludeFromSemantics: true,
                    ),
                  ),
                ),
              ),
            if (showFlowers)
              Positioned(
                right: 0,
                bottom: 0,
                width: sideWidth,
                height: 220,
                child: IgnorePointer(
                  child: Stack(
                    children: [
                      Positioned(
                        right: 4,
                        bottom: 4,
                        width: sideWidth * 0.65,
                        child: const _GirasolRegistro(period: 36),
                      ),
                      Positioned(
                        right: sideWidth * 0.55,
                        bottom: 118,
                        width: sideWidth * 0.27,
                        child: const _GirasolRegistro(period: 48),
                      ),
                    ],
                  ),
                ),
              ),
            child,
          ],
        );
      },
    );
  }
}

class _GirasolRegistro extends StatefulWidget {
  const _GirasolRegistro({required this.period});

  final int period;

  @override
  State<_GirasolRegistro> createState() => _GirasolRegistroState();
}

class _GirasolRegistroState extends State<_GirasolRegistro>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotation = AnimationController(
    vsync: this,
    duration: Duration(seconds: widget.period),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _rotation.reset();
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
  Widget build(BuildContext context) => RotationTransition(
        turns: _rotation.drive(Tween<double>(begin: 0, end: -1)),
        child: Image.asset(
          'assets/images/girasol_registro.png',
          excludeFromSemantics: true,
        ),
      );
}
