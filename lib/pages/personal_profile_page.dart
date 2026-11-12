import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/personal_data_validator.dart';
import '../services/profile_service.dart';
import '../theme/ucr_colors.dart';

class PersonalProfilePage extends StatefulWidget {
  const PersonalProfilePage({super.key});

  @override
  State<PersonalProfilePage> createState() => _PersonalProfilePageState();
}

class _PersonalProfilePageState extends State<PersonalProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _service = ProfileService();
  final _name = TextEditingController();
  final _identification = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _unit = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _padronLocked = false;
  bool _identificationLocked = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.load();
      if (!mounted) return;
      setState(() {
        _name.text = (data['name'] ?? '').toString();
        _identification.text = (data['identification'] ?? '').toString();
        _phone.text = (data['phone'] ?? '').toString();
        _email.text = (data['email'] ?? '').toString();
        _unit.text = (data['unit'] ?? '').toString();
        _padronLocked = data['identitySource'] == 'padron';
        _identificationLocked =
            _padronLocked || _identification.text.isNotEmpty;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar tus datos. Revisá tu conexión '
            'y volvé a intentarlo.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving || _loading) return;
    if (!_padronLocked) {
      _name.text = PersonalDataValidator.normalizeName(_name.text);
    }
    for (final controller in [_identification, _phone, _email, _unit]) {
      controller.text = controller.text.trim();
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // Desactivar la edición también mientras se confirma la primera cédula.
    setState(() => _saving = true);
    try {
      if (!_identificationLocked) {
        final confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Confirmar cédula'),
            content: Text(
              'Vas a registrar la cédula ${_identification.text}. '
              'Revisala antes de continuar: después del guardado '
              'no podrás modificarla desde la aplicación.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Revisar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Confirmar y guardar'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
      }

      await _service.save(
        name: _name.text,
        identification: _identification.text,
        phone: _phone.text,
        email: _email.text,
        unit: _unit.text,
      );
      if (!mounted) return;
      setState(() => _identificationLocked = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tus datos personales quedaron guardados.'),
        ),
      );
    } on StateError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message.toString())));
    } on FirebaseException catch (error) {
      if (!mounted) return;
      final message = error.code == 'permission-denied'
          ? 'No se autorizó el cambio. La cédula guardada no se puede '
              'modificar. Si el dato es incorrecto, contactá al administrador.'
          : 'No se pudieron guardar los datos. Revisá tu conexión '
              'y volvé a intentarlo.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudieron guardar tus datos.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String? Function(String?) validator,
    TextInputType keyboardType = TextInputType.text,
    int? digits,
    bool readOnly = false,
    String? helperText,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: TextFormField(
        controller: controller,
        readOnly: readOnly,
        keyboardType: keyboardType,
        maxLength: digits,
        inputFormatters:
            digits == null ? null : [FilteringTextInputFormatter.digitsOnly],
        autovalidateMode: AutovalidateMode.onUserInteraction,
        validator: readOnly ? null : validator,
        decoration: InputDecoration(
          labelText: label,
          helperText: helperText,
          helperMaxLines: 4,
          errorMaxLines: 3,
          suffixIcon: readOnly ? const Icon(Icons.lock_outline) : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        backgroundColor: UcrColors.background,
        appBar: AppBar(
          backgroundColor: UcrColors.blue,
          foregroundColor: Colors.white,
          title: const Text('Mis datos personales'),
          automaticallyImplyLeading: !_saving,
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _load,
                            child: const Text('Reintentar'),
                          ),
                        ],
                      ),
                    ),
                  )
                : Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: AbsorbPointer(
                        absorbing: _saving,
                        child: Form(
                          key: _formKey,
                          child: ListView(
                            padding: const EdgeInsets.all(24),
                            children: [
                              Text(
                                _padronLocked
                                    ? 'Tu nombre y cédula se tomaron del padrón. '
                                        'Podés actualizar tu teléfono, correo de contacto y unidad.'
                                    : 'Podés actualizar tu nombre, teléfono, correo de contacto '
                                        'y unidad. La cédula se registra una sola vez.',
                              ),
                              const SizedBox(height: 24),
                              _field(
                                controller: _name,
                                label: 'Nombre y apellidos',
                                readOnly: _padronLocked,
                                validator: PersonalDataValidator.name,
                              ),
                              _field(
                                controller: _identification,
                                label: 'Cédula',
                                keyboardType: TextInputType.number,
                                digits: 9,
                                readOnly: _identificationLocked,
                                validator: PersonalDataValidator.identification,
                                helperText: _identificationLocked
                                    ? 'Cédula registrada. Si cometiste un error, '
                                        'solicitá una revisión al administrador.'
                                    : 'Revisá los 9 dígitos: después de guardar '
                                        'la cédula quedará bloqueada.',
                              ),
                              _field(
                                controller: _phone,
                                label: 'Teléfono',
                                keyboardType: TextInputType.phone,
                                digits: 8,
                                validator: PersonalDataValidator.phone,
                              ),
                              _field(
                                controller: _email,
                                label: 'Correo de contacto',
                                keyboardType: TextInputType.emailAddress,
                                validator: PersonalDataValidator.email,
                                helperText: 'Se usa en las declaraciones. '
                                    'Cambiarlo aquí no cambia tu correo para iniciar sesión.',
                              ),
                              _field(
                                controller: _unit,
                                label: 'Unidad académica o administrativa',
                                validator: PersonalDataValidator.unit,
                              ),
                              FilledButton.icon(
                                onPressed: _saving ? null : _save,
                                icon: const Icon(Icons.save_outlined),
                                label: Text(
                                  _saving
                                      ? 'Guardando...'
                                      : 'Guardar mis datos',
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

  @override
  void dispose() {
    for (final controller in [_name, _identification, _phone, _email, _unit]) {
      controller.dispose();
    }
    super.dispose();
  }
}
