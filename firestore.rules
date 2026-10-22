rules_version = '2';

service cloud.firestore {
  match /databases/{database}/documents {

    function validName(value) {
  let letters =
    "A-Za-zÁÉÍÓÚÜÑáéíóúüñÀÈÌÒÙàèìòùÂÊÎÔÛâêîôûÄËÏÖäëïöÇç";

  return value is string
    && value.size() >= 5
    && value.size() <= 100
    && value.matches(
      "[" + letters + "]+([-’'][" + letters + "]+)*"
      + "( [" + letters + "]+([-’'][" + letters + "]+)*)+"
    );
}

function validIdentification(value) {
  return value is string
    && value.matches('[0-9]{9}');
}

function validPhone(value) {
  return value is string
    && value.matches('[0-9]{8}');
}

function validEmail(value) {
  return value is string
    && value.size() <= 254
    && value.matches('[^@\\s]+@[^@\\s]+\\.[^@\\s]+');
}

function validUnit(value) {
  return value is string
    && value.size() >= 2
    && value.size() <= 150
    && value.matches('\\S([^\\r\\n\\t]*\\S)?');
}

function validPersonalData(data) {
  return validName(data.get('ownerName', null))
    && validIdentification(data.get('identification', null))
    && validPhone(data.get('phone', null))
    && validEmail(data.get('email', null))
    && validUnit(data.get('unit', null))
    && data.get('observations', null) is string
    && data.observations.size() <= 2000;
}

function validInitialProfile(data) {
  return validName(data.get('name', null))
    && validEmail(data.get('email', null))
    && (
      data.get('identification', null) == ''
      || validIdentification(data.get('identification', null))
    )
    && (
      data.get('phone', null) == ''
      || validPhone(data.get('phone', null))
    )
    && (
      data.get('unit', null) == ''
      || validUnit(data.get('unit', null))
    );
}

function validProfileChanges() {
  let changed =
    request.resource.data.diff(resource.data).affectedKeys();

  let data = request.resource.data;

  return (
      !changed.hasAny(['name'])
      || validName(data.get('name', null))
    )
    && (
      !changed.hasAny(['email'])
      || validEmail(data.get('email', null))
    )
    && (
      !changed.hasAny(['identification'])
      || data.get('identification', null) == ''
      || validIdentification(data.get('identification', null))
    )
    && (
      !changed.hasAny(['phone'])
      || data.get('phone', null) == ''
      || validPhone(data.get('phone', null))
    )
    && (
      !changed.hasAny(['unit'])
      || data.get('unit', null) == ''
      || validUnit(data.get('unit', null))
    );
}

    // FUNCIONES DE SEGURIDAD
    function signed() {
      return request.auth != null;
    }

    function userDoc() {
      return get(/databases/$(database)/documents/users/$(request.auth.uid));
    }

    function role() {
      return signed() ? userDoc().data.role : 'none';
    }

    function staff() {
      return role() in ['admin', 'rrhh'];
    }

    function owner(d) {
      return signed() && d.ownerId == request.auth.uid;
    }

    function superior(d) {
      return signed() &&
        d.superiorId == request.auth.uid &&
        role() in ['superior', 'admin'];
    }

    function canRead(d) {
      return owner(d) || superior(d) || staff();
    }

    function declarationAfter(id) {
      return getAfter(/databases/$(database)/documents/declarations/$(id)).data;
    }

    function declarationBefore(id) {
      return get(/databases/$(database)/documents/declarations/$(id)).data;
    }

    
function validTransitionEvent(id) {
  let before = declarationBefore(id);
  let after = declarationAfter(id);
  let event = request.resource.data.event;

  return (
    request.resource.data.previousStatus == before.status &&
    request.resource.data.newStatus == after.status &&
    request.resource.data.version == after.version &&
    (
      (
        owner(before) &&
        (
          (event == 'validate' &&
           before.status == 'BORRADOR' &&
           after.status == 'VALIDADA') ||

          (event == 'submit' &&
           before.status == 'VALIDADA' &&
           after.status == 'PENDIENTE_FIRMA_DECLARANTE') ||

          (event == 'signOwner' &&
           before.status == 'PENDIENTE_FIRMA_DECLARANTE' &&
           after.status == 'FIRMADA_POR_DECLARANTE') ||

          (event == 'route' &&
           before.status == 'FIRMADA_POR_DECLARANTE' &&
           after.status == 'PENDIENTE_FIRMA_SUPERIOR') ||

          (event == 'newVersion' &&
           before.status == 'DEVUELTA' &&
           after.status == 'BORRADOR' &&
           after.version == before.version + 1) ||

          (event == 'annul' &&
           before.status in ['BORRADOR', 'VALIDADA'] &&
           after.status == 'ANULADA')
        )
      ) ||

      (
        superior(before) &&
        (
          (event == 'signSuperior' &&
           before.status == 'PENDIENTE_FIRMA_SUPERIOR' &&
           after.status == 'FIRMADA_POR_SUPERIOR') ||

          (event == 'return' &&
           before.status == 'PENDIENTE_FIRMA_SUPERIOR' &&
           after.status == 'DEVUELTA' &&
           after.returnNote is string &&
           after.returnNote.size() > 0)
        )
      ) ||

      (
        staff() &&
        (
          (event == 'sendHr' &&
           before.status == 'FIRMADA_POR_SUPERIOR' &&
           after.status == 'ENVIADA_A_RRHH') ||

          (event == 'receive' &&
           before.status == 'ENVIADA_A_RRHH' &&
           after.status == 'RECIBIDA_RRHH') ||

          (event == 'finish' &&
           before.status == 'RECIBIDA_RRHH' &&
           after.status == 'FINALIZADA')
        )
      )
    )
  );
}


    // USUARIOS
    match /users/{uid} {
  allow read: if signed()
    && (request.auth.uid == uid || staff());

  allow create: if signed()
    && request.auth.uid == uid
    && request.resource.data.role == 'declarante'
    && validInitialProfile(request.resource.data);

  allow update: if signed()
    && validProfileChanges()
    && (
      (
        request.auth.uid == uid
        && request.resource.data.role == resource.data.role
      )
      || role() == 'admin'
    );

  allow delete: if role() == 'admin';
}

    // PERIODOS ACADEMICOS
    match /periods/{id} {
      allow read: if signed();
      allow write: if role() == 'admin';
    }

    // DECLARACIONES
    match /declarations/{id} {
      allow read: if signed() && canRead(resource.data);

      // Crear contenido solo mediante saveDeclarationValidated.
      allow create: if false;

      allow update: if signed() && (
        (
          request.resource.data.version == resource.data.version &&
          request.resource.data.diff(resource.data).affectedKeys().hasOnly([
            'status', 'version', 'updatedAt', 'returnNote'
          ]) &&
          (
            (
              owner(resource.data) && (
                false /* VALIDADA solo mediante el servidor */ ||
                (resource.data.status == 'VALIDADA' &&
                 request.resource.data.status == 'PENDIENTE_FIRMA_DECLARANTE') ||
                
(resource.data.status == 'PENDIENTE_FIRMA_DECLARANTE' &&
 request.resource.data.status == 'FIRMADA_POR_DECLARANTE' &&
 existsAfter(
   /databases/$(database)/documents/declarations/$(id)/versions/$(resource.data.version)/signatures/owner
 ) &&
 !exists(
   /databases/$(database)/documents/declarations/$(id)/versions/$(resource.data.version)/signatures/owner
 )) ||

                (resource.data.status == 'FIRMADA_POR_DECLARANTE' &&
                 request.resource.data.status == 'PENDIENTE_FIRMA_SUPERIOR') ||
                false /* Nueva version solo mediante el servidor */ ||
                (resource.data.status in ['BORRADOR', 'VALIDADA'] &&
                 request.resource.data.status == 'ANULADA')
              )
            ) ||
            
            (
              superior(resource.data) &&
              resource.data.status == 'PENDIENTE_FIRMA_SUPERIOR' &&
              (
                (
                  request.resource.data.status == 'FIRMADA_POR_SUPERIOR' &&
                  !exists(
                    /databases/$(database)/documents/declarations/$(id)/versions/$(resource.data.version)/signatures/superior
                  ) &&
                  existsAfter(
                    /databases/$(database)/documents/declarations/$(id)/versions/$(resource.data.version)/signatures/superior
                  )
                ) ||
                (
                  request.resource.data.status == 'DEVUELTA' &&
                  request.resource.data.returnNote is string &&
                  request.resource.data.returnNote.size() > 0
                )
              )
            ) ||

            (
              staff() && (
                (resource.data.status == 'FIRMADA_POR_SUPERIOR' &&
                 request.resource.data.status == 'ENVIADA_A_RRHH') ||
                (resource.data.status == 'ENVIADA_A_RRHH' &&
                 request.resource.data.status == 'RECIBIDA_RRHH') ||
                (resource.data.status == 'RECIBIDA_RRHH' &&
                 request.resource.data.status == 'FINALIZADA')
              )
            )
          )
        )
      );

      allow delete: if false;

      // VERSIONES
      match /versions/{version} {
        allow read: if signed() && canRead(declarationBefore(id));

        // getAfter permite comprobar la declaracion creada en el mismo batch.
        allow create: if false; // Solo funciones de servidor.

        allow update: if false; // Solo funciones de servidor.

        allow delete: if false;

// Registro del PDF definitivo de esta versión.
match /artifacts/{artifactId} {
  allow read: if signed()
    && artifactId == 'finalPdf'
    && canRead(declarationBefore(id));

  // Solo el backend administra este registro.
  allow write: if false;
}

match /signatures/{signatureId} {
  allow read: if signed() && canRead(declarationBefore(id));

  allow create: if signed() &&
    request.resource.data.userId == request.auth.uid &&
    request.resource.data.version == int(version) &&
    (
      (
        signatureId == 'owner' &&
        owner(declarationAfter(id)) &&
        declarationBefore(id).status == 'PENDIENTE_FIRMA_DECLARANTE' &&
        declarationAfter(id).status == 'FIRMADA_POR_DECLARANTE'
      ) ||
      (
        signatureId == 'superior' &&
        superior(declarationAfter(id)) &&
        declarationBefore(id).status == 'PENDIENTE_FIRMA_SUPERIOR' &&
        declarationAfter(id).status == 'FIRMADA_POR_SUPERIOR'
      )
    );

  allow update, delete: if false;
}
      }


      // HISTORIAL DE EVENTOS
      match /events/{eventId} {
        allow read: if signed() && canRead(declarationBefore(id));

        // getAfter permite el evento de creacion en el mismo batch.
       



allow create: if signed()
          && request.resource.data.userId == request.auth.uid
          && !(request.resource.data.event in ['CREADA', 'MODIFICADA', 'validate', 'newVersion'])
          && validTransitionEvent(id);

        allow update, delete: if false;
      }
    }
  }
}


