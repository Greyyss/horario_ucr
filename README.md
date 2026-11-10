# Horario UCR Integrador — Proyecto Integrador 2

Aplicación Flutter Web académica para declaraciones juradas de horario, basada en el enunciado IF0009 de la UCR.

## IMPORTANTE: una sola carpeta

El ZIP tiene **una sola carpeta raíz** `horario_ucr_integrador/`. Abrí ESA carpeta con **Archivo > Abrir carpeta** en VS Code. Nunca ejecutés los comandos desde su carpeta padre. El `pubspec.yaml` debe estar en la misma carpeta donde se ejecutan los comandos.

## Preparación (Windows PowerShell)

```powershell
Get-Location
Get-ChildItem pubspec.yaml
flutter pub get
# Instalar FlutterFire CLI si no está instalado:
dart pub global activate flutterfire_cli
# Requiere Firebase CLI: npm install -g firebase-tools; firebase login
dart pub global run flutterfire_cli:flutterfire configure --project=declarahorario-ucr-cff7a --platforms=web
flutter analyze
flutter test
flutter run -d chrome
```

**No ejecutés `flutter create`**: la estructura `web/` ya está incluida. El archivo `lib/firebase_options.dart` incluido es temporal y se reemplaza al ejecutar FlutterFire. Sin esa configuración la aplicación mostrará un mensaje explicativo, no una pantalla en blanco.

## Firebase (configuración manual necesaria)

1. En Firebase Console, proyecto `declarahorario-ucr-cff7a`, activar **Authentication > Email/Password**.
2. Crear **Cloud Firestore** y **Cloud Storage** en el proyecto (revisar cuotas, región y facturación).
3. Instalar Firebase CLI y ejecutar `firebase deploy --only firestore:rules,storage` desde esta carpeta. **Revisá las reglas antes de producción.**
4. En Firestore crear un período en `periods/2026-II` con `enabled: true`.
5. Registrá usuarios desde la aplicación; el registro crea un perfil con rol `declarante`.
6. Para pruebas de otros roles, un administrador autorizado debe asignar `superior`, `rrhh` o `admin` a perfiles en Firestore; nunca otorgar roles elevados desde el cliente público. El campo `superiorId` de la declaración debe contener el UID real del superior.
7. Para publicar: `flutter build web` y `firebase deploy --only hosting`.

## Funcionalidad incluida

- Registro e inicio de sesión por Firebase Auth.
- Declaraciones y nombramientos múltiples; horarios externos y observaciones.
- Validación de horas, traslapes, exclusión 12:00–13:00 y máximo diario 10 h.
- Estados, firmas electrónicas internas, devoluciones y nuevas versiones.
- Historial de eventos y generación de PDF; carga en Storage para trámites finalizados según permisos.
- Reglas iniciales de Firestore y Storage, pruebas unitarias de validación y documentación.

## Límites / pendientes importantes

**No se ha compilado ni probado este ZIP en un entorno con Flutter SDK**, por lo que no puede garantizarse que funcione sin ajustes. Requiere configuración de Firebase, habilitación de servicios, datos iniciales y pruebas integrales. Faltan una interfaz administrativa para gestionar roles/períodos, pruebas de reglas de seguridad con emulador, endurecimiento transaccional de auditoría/firmas, y verificar que el PDF reproduzca fielmente el formulario institucional. Las firmas internas **no son firmas digitales certificadas**. No usar con datos reales hasta completar auditoría de seguridad y validación funcional.

## Estructura

`lib/main.dart`, `lib/models/`, `lib/pages/`, `lib/services/`, `test/`, `web/`, `docs/`, `firebase.json`, `firestore.rules`, `storage.rules`.
