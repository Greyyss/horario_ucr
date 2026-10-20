# Requerimientos y arquitectura

Fuente: Proyecto Integrador 2: DeclaraHorario, IF0009 UCR, II Ciclo 2026.

## Entidades

- `users/{uid}`: nombre, correo, rol, unidad, identificación y teléfono.
- `periods/{periodId}`: nombre y habilitación.
- `declarations/{id}`: propietario, superior, estado, período, datos y versión actual.
- `declarations/{id}/versions/{number}`: instantánea de la versión.
- `.../versions/{number}/signatures/{owner|superior}`: identidad, fecha, versión y huella SHA-256.
- `declarations/{id}/events/{id}`: tipo, actor, fecha, versión, estado anterior, nuevo y observación.
- `pdf/{declarationId}/v{version}.pdf`: documento archivado.

## Estados

BORRADOR → VALIDADA → PENDIENTE_FIRMA_DECLARANTE → FIRMADA_POR_DECLARANTE → PENDIENTE_FIRMA_SUPERIOR → FIRMADA_POR_SUPERIOR → ENVIADA_A_RRHH → RECIBIDA_RRHH → FINALIZADA.

Alternativa desde PENDIENTE_FIRMA_SUPERIOR: DEVUELTA → BORRADOR (nueva versión). ANULADA es estado adicional previsto.

## Reglas temporales

Se evalúan bloques lunes-sábado, inicio anterior al fin, exclusión 12:00–13:00, máximo diario 10 horas, traslapes internos/externos y diferencia de horas institucionales frente a jornada esperada.

## Limitaciones técnicas pendientes

La aplicación requiere endurecer el modelo de seguridad mediante Cloud Functions para operaciones atómicas de firma y validación, PDF servidor, control estricto de períodos, trazabilidad a prueba de manipulación y pruebas E2E. Los datos sensibles no deben utilizarse en producción sin auditoría.
