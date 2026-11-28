import 'package:flutter/material.dart';

import '../models/declaration.dart';
import '../services/signed_pdf_service.dart';

class SignedPdfPanel extends StatefulWidget {
  final Declaration declaration;
  final String role;
  final List<Widget> extraActions;

  const SignedPdfPanel({
    super.key,
    required this.declaration,
    required this.role,
    this.extraActions = const [],
  });

  @override
  State<SignedPdfPanel> createState() => _SignedPdfPanelState();
}

class _SignedPdfPanelState extends State<SignedPdfPanel> {
  final _service = SignedPdfService();

  SigningPdfStatus? _status;

  bool _loading = true;
  bool _busy = false;

  String? _error;
  String _operation = '';

  int _request = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant SignedPdfPanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.declaration.id != widget.declaration.id ||
        oldWidget.declaration.version != widget.declaration.version ||
        oldWidget.declaration.status != widget.declaration.status) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final request = ++_request;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await _service.status(widget.declaration);

      if (!mounted || request != _request) return;

      setState(() => _status = result);
    } catch (error) {
      if (!mounted || request != _request) return;

      setState(() {
        _error =
            error is StateError ? error.message.toString() : error.toString();
      });
    } finally {
      if (mounted && request == _request) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _run(
    String label,
    Future<String?> Function() action,
  ) async {
    if (_busy || _loading) return;

    setState(() {
      _busy = true;
      _operation = label;
      _error = null;
    });

    try {
      final message = await action();

      if (!mounted) return;

      if (message != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }

      await _refresh();
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error =
            error is StateError ? error.message.toString() : error.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.declaration;

    final owner = widget.role == 'declarante';
    final superior = widget.role == 'superior';

    final ownerStage = owner &&
        [
          'VALIDADA',
          'PENDIENTE_FIRMA_DECLARANTE',
        ].contains(d.status);

    final superiorStage = superior && d.status == 'PENDIENTE_FIRMA_SUPERIOR';

    final ready = !_loading && !_busy && _error == null && _status != null;

    final legacy = [
          'FIRMADA_POR_DECLARANTE',
          'FIRMADA_POR_SUPERIOR',
        ].contains(d.status) ||
        (d.status == 'PENDIENTE_FIRMA_SUPERIOR' &&
            _status != null &&
            !_status!.prepared);

    final verified = owner
        ? (_status?.ownerVerified ?? false)
        : (_status?.superiorVerified ?? false);

    String instructions;

    if (legacy) {
      instructions = 'Esta versión usa el proceso anterior. '
          'Sus registros de clic no acreditan firmas digitales del PDF.';
    } else if (ownerStage) {
      instructions = 'Descargá el PDF, firmalo con tu certificado digital '
          'y subilo. Después enviá la declaración al superior.';
    } else if (superiorStage) {
      instructions = 'Descargá el PDF firmado por el declarante, agregá tu '
          'firma conservando la primera y subilo para aceptar.';
    } else if (widget.role == 'rrhh') {
      instructions = 'Revisá el PDF final con ambas firmas digitales '
          'antes de recibir o finalizar el trámite.';
    } else {
      instructions = 'Tu PDF fue enviado. La declaración continúa en revisión.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F6FC),
        border: Border.all(
          color: const Color(0xFFCEDFEE),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Firma digital del PDF',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(instructions),
          const SizedBox(height: 8),
          if (!_loading && !legacy && _status != null)
            Text(
              verified
                  ? '✓ Firma digital verificada'
                  : 'Falta cargar el PDF firmado.',
              style: TextStyle(
                color: verified ? Colors.green.shade800 : Colors.blueGrey,
              ),
            ),
          if (_loading || _busy)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _busy ? _operation : 'Consultando firmas…',
                    ),
                  ),
                ],
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!legacy && (ownerStage || superiorStage)) ...[
                OutlinedButton.icon(
                  onPressed: ready
                      ? () => _run(
                            'Preparando y descargando el PDF…',
                            () => _service.download(
                              d,
                              prepare: ownerStage,
                            ),
                          )
                      : null,
                  icon: const Icon(Icons.download_outlined),
                  label: Text(
                    superiorStage
                        ? 'Descargar PDF del declarante'
                        : 'Descargar PDF para firmar',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: ready && (_status?.prepared ?? false) && !verified
                      ? () => _run(
                            'Seleccionando y verificando el PDF…',
                            () => _service.upload(d),
                          )
                      : null,
                  icon: const Icon(Icons.upload_file_outlined),
                  label: Text(
                    superiorStage
                        ? 'Subir PDF con ambas firmas'
                        : 'Subir PDF firmado',
                  ),
                ),
                FilledButton.icon(
                  onPressed: ready && verified
                      ? () => _run(
                            superiorStage
                                ? 'Aceptando y enviando a RRHH…'
                                : 'Enviando al superior…',
                            () => superiorStage
                                ? _service.accept(d)
                                : _service.send(d),
                          )
                      : null,
                  icon: const Icon(Icons.send_outlined),
                  label: Text(
                    superiorStage
                        ? 'Aceptar y enviar a RRHH'
                        : 'Enviar al superior',
                  ),
                ),
              ],
              if (!legacy &&
                  !ownerStage &&
                  !superiorStage &&
                  (_status?.ownerVerified ?? false))
                OutlinedButton.icon(
                  onPressed: ready
                      ? () => _run(
                            'Descargando el PDF firmado…',
                            () => _service.download(
                              d,
                              prepare: false,
                            ),
                          )
                      : null,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Descargar PDF firmado'),
                ),
              AbsorbPointer(
                absorbing:
                    _busy || _loading || (widget.role == 'rrhh' && !verified),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.extraActions,
                ),
              ),
              TextButton.icon(
                onPressed: _busy || _loading ? null : _refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Actualizar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
