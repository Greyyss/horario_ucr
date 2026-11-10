import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

class SuperiorSelector extends StatefulWidget {
  final TextEditingController controller;
  final bool enabled;

  const SuperiorSelector({
    super.key,
    required this.controller,
    this.enabled = true,
  });

  @override
  State<SuperiorSelector> createState() => _SuperiorSelectorState();
}

class _SuperiorSelectorState extends State<SuperiorSelector> {
  List<({String uid, String name, String unit})> _superiors = [];
  bool _loading = true;
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
      final result = await FirebaseFunctions.instanceFor(region: 'us-east1')
          .httpsCallable('listSuperiors')
          .call();
      final response = Map<String, dynamic>.from(result.data as Map);
      final entries = (response['superiors'] as List).map((item) {
        final data = Map<String, dynamic>.from(item as Map);
        return (
          uid: data['uid'] as String,
          name: data['name'] as String,
          unit: data['unit'] as String,
        );
      }).toList();
      if (!mounted) return;
      setState(() => _superiors = entries);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar la lista de superiores.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.controller.text.trim();
    final available = _superiors.any((item) => item.uid == current);
    final missing = current.isNotEmpty && !available;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: LinearProgressIndicator(),
          ),
        DropdownButtonFormField<String>(
          key: ValueKey('superior-$current-${_superiors.length}'),
          initialValue: current.isEmpty ? null : current,
          isExpanded: true,
          itemHeight: null,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          decoration: InputDecoration(
            labelText: 'Superior jerárquico',
            prefixIcon: const Icon(Icons.supervisor_account_outlined),
            errorMaxLines: 3,
            helperMaxLines: 3,
            helperText: widget.enabled
                ? 'Seleccioná a la persona que revisará tu declaración.'
                : 'El superior de este borrador ya está asignado.',
          ),
          hint: const Text('Seleccioná tu superior'),
          items: [
            if (missing) _unavailableItem(current),
            for (final item in _superiors)
              DropdownMenuItem<String>(
                value: item.uid,
                child: Text(
                  item.unit.isEmpty ? item.name : '${item.name} — ${item.unit}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: !widget.enabled || _loading || _error != null
              ? null
              : (value) {
                  setState(() => widget.controller.text = value ?? '');
                },
          validator: (value) {
            if (_loading) return 'Esperá a que se carguen los superiores.';
            if (_error != null) return 'Reintentá la carga de superiores.';
            if (value == null || value.isEmpty) {
              return 'Seleccioná a tu superior.';
            }
            if (widget.enabled &&
                !_superiors.any((item) => item.uid == value)) {
              return 'Seleccioná un superior disponible en la lista.';
            }
            return null;
          },
        ),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: Colors.red)),
        if (!_loading && _error == null && _superiors.isEmpty)
          const Text('No hay superiores disponibles con nombre registrado.'),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(_error == null ? 'Actualizar lista' : 'Reintentar'),
          ),
        ),
      ],
    );
  }

  DropdownMenuItem<String> _unavailableItem(String uid) {
    return DropdownMenuItem<String>(
      value: uid,
      enabled: false,
      child: Text(
        _loading
            ? 'Cargando superior asignado...'
            : 'Superior asignado (no disponible en la lista)',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
