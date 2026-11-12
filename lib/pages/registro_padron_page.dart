import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

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
