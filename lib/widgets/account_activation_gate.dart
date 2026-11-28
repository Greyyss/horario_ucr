import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AccountActivationGate extends StatefulWidget {
  const AccountActivationGate({super.key});

  @override
  State<AccountActivationGate> createState() => _AccountActivationGateState();
}

class _AccountActivationGateState extends State<AccountActivationGate> {
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _activate();
  }

  Future<void> _activate() async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);

      final response = await FirebaseFunctions.instanceFor(
        region: 'us-east1',
      ).httpsCallable('completeAccountActivation').call();

      final data = Map<String, dynamic>.from(
        response.data as Map,
      );

      if (!mounted) return;

      setState(() {
        _message = switch (data['state']) {
          'expired' => 'La invitación venció. Solicitá a Administración '
              'que la renueve. Cambiar la contraseña '
              'no renueva este plazo.',
          'active' || 'legacy' => 'Activación confirmada. Abriendo tu cuenta…',
          _ => 'La cuenta no está disponible. '
              'Contactá a Administración.',
        };
      });
    } on FirebaseFunctionsException catch (error) {
      if (mounted) {
        setState(() {
          _message = error.message ?? 'No se pudo activar la cuenta.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = 'No se pudo comprobar la activación. Reintentá.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activación de cuenta'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.manage_accounts_outlined,
                  size: 56,
                ),
                const SizedBox(height: 20),
                const Text(
                  'Primer acceso a DeclaraUCR',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _message ?? 'Comprobando tu acceso inicial…',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (_busy)
                  const CircularProgressIndicator()
                else
                  FilledButton(
                    onPressed: _activate,
                    child: const Text('Reintentar'),
                  ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          await FirebaseAuth.instance.signOut();
                        },
                  child: const Text('Cerrar sesión'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
