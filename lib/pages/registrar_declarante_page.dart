import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

class RegistrarDeclarantePage extends StatefulWidget {
  const RegistrarDeclarantePage({super.key});

  @override
  State<RegistrarDeclarantePage> createState() =>
      _RegistrarDeclarantePageState();
}

class _RegistrarDeclarantePageState extends State<RegistrarDeclarantePage> {
  final _form = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{
    for (final key in ['cedula', 'correo', 'telefono', 'unidad'])
      key: TextEditingController(),
  };
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _register() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'us-east1')
          .httpsCallable('registrarDeclarante')
          .call<Map<String, dynamic>>({
            for (final field in _fields.entries)
              field.key: field.value.text.trim(),
          });
      if (!mounted) return;
      for (final controller in _fields.values) {
        controller.clear();
      }
      setState(() => _message = 'Cuenta creada para ${result.data['nombre']}.');
    } on FirebaseFunctionsException catch (error) {
      if (mounted)
        setState(() => _message = error.message ?? 'No se pudo registrar.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const labels = {
      'cedula': 'Cédula',
      'correo': 'Correo electrónico',
      'telefono': 'Teléfono',
      'unidad': 'Unidad académica o administrativa',
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Registrar declarante')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                for (final field in labels.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: TextFormField(
                      controller: _fields[field.key],
                      enabled: !_busy,
                      decoration: InputDecoration(
                        labelText: field.value,
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) => (value ?? '').trim().isEmpty
                          ? 'Completá este campo.'
                          : null,
                    ),
                  ),
                FilledButton(
                  onPressed: _busy ? null : _register,
                  child: Text(_busy ? 'Registrando…' : 'Registrar declarante'),
                ),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_message!),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
