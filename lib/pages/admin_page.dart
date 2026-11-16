import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

typedef _User = QueryDocumentSnapshot<Map<String, dynamic>>;

class AdminPage extends StatefulWidget {
  const AdminPage({super.key, this.isHome = false});

  final bool isHome;

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  static const _blue = Color(0xFF005A91);
  static const _roles = {
    'declarante': 'Declarante',
    'superior': 'Superior',
    'rrhh': 'RRHH',
    'admin': 'Administrador',
  };

  final _db = FirebaseFirestore.instance;
  late final _users = _db.collection('users').snapshots();
  late final _periods = _db.collection('periods').snapshots();
  String _search = '';
  String _filter = '';
  String? _selected;
  String? _role;
  String? _superior;
  bool _busy = false;

  String _value(_User user, String field) =>
      (user.data()[field] ?? '').toString();

  Future<void> _run(Future<void> Function() action, String success) async {
    if (_busy) return;
    setState(() => _busy = true);
    var message = success;
    try {
      await action();
    } on FirebaseFunctionsException catch (error) {
      message = error.message ?? 'No se pudo guardar el cambio.';
    } catch (error) {
      message = 'No se pudo guardar el cambio: $error';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _deleteProfile(_User user) async {
    final name = _value(user, 'name');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: const Text('Eliminar perfil'),
        content: Text(
          'Se eliminarán la cuenta, el perfil y las declaraciones de $name. '
          'Los PDF archivados se conservarán.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar definitivamente'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;
    await _run(() async {
      await FirebaseFunctions.instanceFor(region: 'us-east1')
          .httpsCallable('eliminarPerfil')
          .call({'uid': user.id});
      if (!mounted) return;
      setState(() {
        _selected = null;
        _role = null;
        _superior = null;
      });
    }, 'Perfil eliminado.');
  }

  Widget _panel(Widget child) => Card(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0xFFD7E3EE)),
        ),
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      );

  Widget _details(_User? user, List<_User> users) {
    if (user == null) return _panel(const Text('Seleccioná un usuario.'));
    final self = user.id == FirebaseAuth.instance.currentUser?.uid;
    final currentRole = _value(user, 'role');
    final currentSuperior = _value(user, 'superiorId');
    final nextRole = _role ?? currentRole;
    final nextSuperior = _superior ?? currentSuperior;
    final choices = users
        .where((option) =>
            option.id != user.id && _value(option, 'role') == 'superior')
        .toList();
    final validSuperior = choices.any((option) => option.id == nextSuperior);
    final changeSuperior = nextRole == 'declarante' &&
        validSuperior &&
        _superior != null &&
        nextSuperior != currentSuperior;
    final canSave =
        !_busy && !self && (nextRole != currentRole || changeSuperior);

    return _panel(Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Perfil del usuario',
          style: TextStyle(
            color: Color(0xFF005A91),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Text(_value(user, 'name'),
            style: Theme.of(context).textTheme.titleLarge),
        Text(_value(user, 'email')),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
          key: ValueKey((user.id, 'role', nextRole)),
          initialValue: _roles.containsKey(nextRole) ? nextRole : null,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Rol',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final entry in _roles.entries)
              DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: _busy || self
              ? null
              : (value) {
                  setState(() => _role = value);
                },
        ),
        if (nextRole == 'declarante') ...[
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey((user.id, 'superior', nextSuperior)),
            initialValue: validSuperior ? nextSuperior : null,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Superior jerárquico',
              border: OutlineInputBorder(),
            ),
            hint: const Text('Seleccioná un superior'),
            items: [
              for (final option in choices)
                DropdownMenuItem(
                  value: option.id,
                  child: Text(
                    _value(option, 'name'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _busy || self
                ? null
                : (value) {
                    setState(() => _superior = value);
                  },
          ),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: canSave
              ? () => _run(() async {
                    if (nextRole != currentRole) {
                      await user.reference.update({'role': nextRole});
                    }
                    if (changeSuperior) {
                      await FirebaseFunctions.instanceFor(region: 'us-east1')
                          .httpsCallable('asignarSuperior')
                          .call({'uid': user.id, 'superiorId': nextSuperior});
                    }
                    if (mounted) {
                      setState(() {
                        _role = null;
                        _superior = null;
                      });
                    }
                  }, 'Cambios guardados.')
              : null,
          child: _busy
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
                    Text('Guardando…'),
                  ],
                )
              : const Text('Guardar cambios'),
        ),
        const Divider(height: 32),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _busy || self ? null : () => _deleteProfile(user),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Eliminar perfil'),
          ),
        ),
      ],
    ));
  }

  Widget _usersTab() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _users,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
                child: Text('No se pudieron cargar los usuarios.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final users = snapshot.data!.docs.toList()
            ..sort((a, b) => _value(a, 'name')
                .toLowerCase()
                .compareTo(_value(b, 'name').toLowerCase()));
          final visible = users.where((user) {
            final text = '${_value(user, 'name')} ${_value(user, 'email')}';
            return (_filter.isEmpty || _value(user, 'role') == _filter) &&
                text.toLowerCase().contains(_search);
          }).toList();
          _User? active;
          for (final user in visible) {
            if (user.id == _selected) active = user;
          }

          final table = _panel(Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 280,
                    child: TextFormField(
                      initialValue: _search,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        labelText: 'Buscar por nombre o correo',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (text) =>
                          setState(() => _search = text.trim().toLowerCase()),
                    ),
                  ),
                  DropdownButton<String>(
                    value: _filter,
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Todos los roles'),
                      ),
                      for (final entry in _roles.entries)
                        DropdownMenuItem(
                            value: entry.key, child: Text(entry.value)),
                    ],
                    onChanged: (value) => setState(() => _filter = value ?? ''),
                  ),
                ],
              ),
              if (visible.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Text('No hay usuarios para mostrar.'),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: DataTable(
                    showCheckboxColumn: false,
                    horizontalMargin: 12,
                    columnSpacing: 12,
                    dataRowMinHeight: 54,
                    dataRowMaxHeight: 64,
                    headingRowColor:
                        const WidgetStatePropertyAll(Color(0xFFE1EDF7)),
                    dataRowColor: WidgetStateProperty.resolveWith<Color?>(
                      (states) => states.contains(WidgetState.selected)
                          ? const Color(0xFFD9EBFA)
                          : null,
                    ),
                    columns: const [
                      DataColumn(
                          label: Text('Usuario'),
                          columnWidth: FlexColumnWidth(2.4)),
                      DataColumn(
                          label: Text('Rol'), columnWidth: FlexColumnWidth()),
                      DataColumn(
                          label: Text('Superior asignado'),
                          columnWidth: FlexColumnWidth(1.4)),
                    ],
                    rows: [
                      for (final user in visible)
                        DataRow(
                          selected: user.id == _selected,
                          onSelectChanged: _busy
                              ? null
                              : (_) {
                                  setState(() {
                                    _selected = user.id;
                                    _role = null;
                                    _superior = null;
                                  });
                                },
                          cells: [
                            DataCell(
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _value(user, 'name'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                  Tooltip(
                                    message: _value(user, 'email'),
                                    child: Text(
                                      _value(user, 'email'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF53657A)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            DataCell(Text(_roles[_value(user, 'role')] ?? '—')),
                            DataCell(Text(_value(user, 'role') != 'declarante'
                                ? '—'
                                : _value(user, 'superiorName').isEmpty
                                    ? 'Sin asignar'
                                    : _value(user, 'superiorName'))),
                          ],
                        ),
                    ],
                  ),
                ),
            ],
          ));

          return LayoutBuilder(builder: (context, constraints) {
            final details = _details(active, users);
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (constraints.maxWidth >= 950)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 7, child: table),
                      const SizedBox(width: 12),
                      Expanded(flex: 3, child: details),
                    ],
                  )
                else ...[table, details],
              ],
            );
          });
        },
      );

  Future<void> _addPeriod() async {
    final id = await showDialog<String>(
      context: context,
      builder: (_) => const _PeriodDialog(),
    );
    if (id == null || !mounted) return;
    await _run(() async {
      final ref = _db.collection('periods').doc(id);
      await _db.runTransaction((transaction) async {
        if ((await transaction.get(ref)).exists) {
          throw StateError('El período ya existe.');
        }
        transaction.set(ref, {'enabled': false});
      });
    }, 'Período creado.');
  }

  Widget _periodsTab() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _periods,
        builder: (context, snapshot) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _busy ? null : _addPeriod,
                icon: const Icon(Icons.add),
                label: const Text('Nuevo período'),
              ),
            ),
            if (snapshot.hasError)
              const Text('No se pudieron cargar los períodos.')
            else if (!snapshot.hasData)
              const LinearProgressIndicator()
            else ...[
              if (snapshot.data!.docs.isEmpty)
                const Text('No hay períodos registrados.'),
              for (final doc in snapshot.data!.docs)
                _panel(SwitchListTile(
                  title: Text(
                    (doc.data()['name'] ?? doc.data()['label'] ?? doc.id)
                        .toString(),
                  ),
                  value: doc.data()['enabled'] == true,
                  onChanged: _busy
                      ? null
                      : (enabled) => _run(
                            () => doc.reference.update({'enabled': enabled}),
                            'Período actualizado.',
                          ),
                )),
            ],
          ],
        ),
      );

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: const Color(0xFFEAF2F9),
          appBar: AppBar(
            backgroundColor: _blue,
            foregroundColor: Colors.white,
            title: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    child: Image.asset(
                      'assets/images/logo_declara_ucr.png',
                      width: 108,
                      height: 30,
                      fit: BoxFit.contain,
                      semanticLabel: 'DeclaraUCR',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const SizedBox(
                  height: 24,
                  child: VerticalDivider(width: 1, color: Colors.white54),
                ),
                const SizedBox(width: 12),
                const Flexible(
                  child: Text(
                    'Administración',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            automaticallyImplyLeading: !widget.isHome,
            actions: [
              if (widget.isHome)
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  icon: const Icon(Icons.logout),
                  label: const Text('Cerrar sesión'),
                  onPressed: () async {
                    await FirebaseAuth.instance.signOut();
                  },
                ),
            ],
          ),
          body: Column(
            children: [
              const TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [Tab(text: 'Usuarios'), Tab(text: 'Períodos')]),
              Expanded(
                  child: TabBarView(children: [_usersTab(), _periodsTab()])),
            ],
          ),
        ),
      );
}

class _PeriodDialog extends StatefulWidget {
  const _PeriodDialog();

  @override
  State<_PeriodDialog> createState() => _PeriodDialogState();
}

class _PeriodDialogState extends State<_PeriodDialog> {
  final _form = GlobalKey<FormState>();
  String _id = '';

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Nuevo período'),
        content: Form(
          key: _form,
          child: TextFormField(
            decoration:
                const InputDecoration(labelText: 'Identificador (2027-I)'),
            onChanged: (value) => _id = value.trim().toUpperCase(),
            validator: (_) => RegExp(r'^\d{4}-(I|II|III)$').hasMatch(_id)
                ? null
                : 'Usá un formato como 2027-I.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (_form.currentState!.validate()) Navigator.pop(context, _id);
            },
            child: const Text('Crear'),
          ),
        ],
      );
}
