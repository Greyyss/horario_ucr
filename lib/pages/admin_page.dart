import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AdminPage extends StatelessWidget {
  const AdminPage({super.key});

  static const roles = ['declarante', 'superior', 'rrhh', 'admin'];

  Future<void> changeRole(BuildContext context, String uid, String role) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'role': role,
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rol actualizado correctamente')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo actualizar el rol: $error')),
        );
      }
    }
  }

  Future<void> savePeriod(BuildContext context, String id, bool enabled) async {
    try {
      await FirebaseFirestore.instance.collection('periods').doc(id).set({
        'enabled': enabled,
      }, SetOptions(merge: true));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Período guardado correctamente')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo guardar el período: $error')),
        );
      }
    }
  }

  Future<void> addPeriod(BuildContext context) async {
    final controller = TextEditingController();
    final id = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nuevo período'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Identificador (ejemplo: 2027-I)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              controller.text.trim(),
            ),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (id == null || id.isEmpty || !context.mounted) return;
    if (!RegExp(r'^\d{4}-(I|II|III)$').hasMatch(id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Use un formato como 2027-I o 2027-II')),
      );
      return;
    }
    await savePeriod(context, id, false);
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final db = FirebaseFirestore.instance;

    return Scaffold(
      appBar: AppBar(title: const Text('Administración')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Usuarios', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: db.collection('users').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text('Error al consultar usuarios: ${snapshot.error}');
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.data!.docs.isEmpty) {
                return const Text('No hay usuarios registrados.');
              }
              return Column(
                children: snapshot.data!.docs.map((doc) {
                  final data = doc.data();
                  final currentRole = data['role']?.toString() ?? 'declarante';
                  final isSelf = doc.id == currentUid;
                  return Card(
                    child: ListTile(
                      title: Text(data['name']?.toString() ?? 'Sin nombre'),
                      subtitle: Text(data['email']?.toString() ?? ''),
                      trailing: DropdownButton<String>(
                        value: roles.contains(currentRole) ? currentRole : null,
                        hint: const Text('Rol'),
                        items: roles.map((role) => DropdownMenuItem(
                          value: role,
                          child: Text(role),
                        )).toList(),
                        onChanged: isSelf ? null : (role) async {
                          if (role != null && role != currentRole) {
                            await changeRole(context, doc.id, role);
                          }
                        },
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text('Períodos', style: Theme.of(context).textTheme.titleLarge),
              ),
              FilledButton.icon(
                onPressed: () => addPeriod(context),
                icon: const Icon(Icons.add),
                label: const Text('Nuevo período'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: db.collection('periods').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text('Error al consultar períodos: ${snapshot.error}');
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.data!.docs.isEmpty) {
                return const Text('No hay períodos registrados.');
              }
              return Column(
                children: snapshot.data!.docs.map((doc) {
                  final enabled = doc.data()['enabled'] == true;
                  return Card(
                    child: SwitchListTile(
                      title: Text(doc.id),
                      subtitle: Text(enabled ? 'Habilitado' : 'Deshabilitado'),
                      value: enabled,
                      onChanged: (value) => savePeriod(context, doc.id, value),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
