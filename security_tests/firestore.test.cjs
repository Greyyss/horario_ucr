
const fs = require('node:fs');

const {
  initializeTestEnvironment,
  assertFails,
} = require('@firebase/rules-unit-testing');

async function main() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'declarahorario-ucr-cff7a',
    firestore: {
      host: '127.0.0.1',
      port: 8080,
      rules: fs.readFileSync('firestore.rules', 'utf8'),
    },
  
  });

  try {
    // Limpiar los datos anteriores del emulador.
    await testEnv.clearFirestore();

    console.log('Emulador limpio. Iniciando pruebas.');

    // PRUEBA 1: usuario sin iniciar sesión.

    const guestDb = testEnv.unauthenticatedContext().firestore();

    await assertFails(
      guestDb.collection('declarations').doc('prueba-seguridad').get()
    );

    console.log('PRUEBA 1 APROBADA: acceso sin sesión bloqueado.');

    // Preparar datos ficticios en el emulador.
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const adminDb = context.firestore();

      await adminDb.collection('users').doc('usuario-b').set({
        role: 'declarante',
      });

      await adminDb.collection('declarations').doc('declaracion-ajena').set({
        ownerId: 'usuario-b',
        superiorId: 'superior-1',
        status: 'BORRADOR',
        version: 1,
        periodId: '2026-II',
      });
    });

    // PRUEBA 2: usuario A intenta leer declaración de B.
    const userADb = testEnv.authenticatedContext('usuario-a').firestore();

    await assertFails(
      userADb.collection('declarations').doc('declaracion-ajena').get()
    );

    console.log(
      'PRUEBA 2 APROBADA: un declarante no puede leer declaraciones ajenas.'
    );
   
    // PRUEBA 3: usuario A intenta modificar
    // una declaración que pertenece al usuario B.

    await assertFails(
      userADb
        .collection('declarations')
        .doc('declaracion-ajena')
        .update({
          observations: 'Modificación no autorizada',
        })
    );

    console.log(
      'PRUEBA 3 APROBADA: un declarante no puede modificar declaraciones ajenas.'
    );

    
    // PRUEBA 4: impedir modificaciones
    // en una versión que ya fue firmada.

    await testEnv.withSecurityRulesDisabled(async (context) => {
      const adminDb = context.firestore();

      await adminDb.collection('declarations').doc('declaracion-firmada').set({
        ownerId: 'usuario-a',
        superiorId: 'superior-1',
        status: 'FIRMADA_POR_DECLARANTE',
        version: 1,
        periodId: '2026-II',
      });

      await adminDb
        .collection('declarations')
        .doc('declaracion-firmada')
        .collection('versions')
        .doc('1')
        .set({
          ownerId: 'usuario-a',
          superiorId: 'superior-1',
          periodId: '2026-II',
          status: 'BORRADOR',
          version: 1,
          observations: 'Datos originales',
        });
    });

    await assertFails(
      userADb
        .collection('declarations')
        .doc('declaracion-firmada')
        .collection('versions')
        .doc('1')
        .update({
          observations: 'Intento de modificar versión firmada',
        })
    );

    console.log(
      'PRUEBA 4 APROBADA: las versiones firmadas no pueden modificarse.'
    );

    // PRUEBA 5: impedir que un usuario no autorizado
    // registre la firma del superior.

    await testEnv.withSecurityRulesDisabled(async (context) => {
      const adminDb = context.firestore();

      await adminDb.collection('users').doc('usuario-a').set({
        role: 'declarante',
      });

      await adminDb
        .collection('declarations')
        .doc('declaracion-firma')
        .set({
          ownerId: 'usuario-a',
          superiorId: 'superior-1',
          status: 'PENDIENTE_FIRMA_SUPERIOR',
          version: 1,
          periodId: '2026-II',
        });
    });

    await assertFails(
      userADb
        .collection('declarations')
        .doc('declaracion-firma')
        .collection('versions')
        .doc('1')
        .collection('signatures')
        .doc('superior')
        .set({
          userId: 'usuario-a',
          name: 'Usuario de prueba',
          version: 1,
          signatureId: 'superior',
          type: 'SUPERIOR',
        })
    );

    console.log(
      'PRUEBA 5 APROBADA: un usuario no autorizado no puede firmar como superior.'
    );

    
    // PRUEBA 6: permitir que el propietario
    // lea su propia declaración.

    const { assertSucceeds } = require(
      '@firebase/rules-unit-testing'
    );

    await assertSucceeds(
      userADb
        .collection('declarations')
        .doc('declaracion-firmada')
        .get()
    );

    console.log(
      'PRUEBA 6 APROBADA: el propietario puede leer su declaración.'
    );

    
    // PRUEBA 7: permitir que un declarante
    // cree una declaración propia en borrador.

    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore()
        .collection('periods')
        .doc('2026-II')
        .set({
          enabled: true,
        });
    });

    await assertSucceeds(
      userADb
        .collection('declarations')
        .doc('declaracion-nueva')
        .set({
          ownerId: 'usuario-a',
          ownerName: 'Usuario de prueba',
          identification: '000000000',
          phone: '00000000',
          email: 'prueba@example.com',
          unit: 'Unidad de prueba',
          periodId: '2026-II',
          superiorId: 'superior-1',
          status: 'BORRADOR',
          observations: '',
          version: 1,
          appointments: [],
          externalJobs: [],
          updatedAt: new Date(),
        })
    );

    console.log(
      'PRUEBA 7 APROBADA: el declarante puede crear su propio borrador.'
    );
    
    // PRUEBA 8: guardar una declaración,
    // su versión y un evento en un mismo lote.

    const completeDeclaration = {
      ownerId: 'usuario-a',
      ownerName: 'Usuario de prueba',
      identification: '000000000',
      phone: '00000000',
      email: 'prueba@example.com',
      unit: 'Unidad de prueba',
      periodId: '2026-II',
      superiorId: 'superior-1',
      status: 'BORRADOR',
      observations: '',
      version: 1,
      appointments: [],
      externalJobs: [],
      updatedAt: new Date(),
    };

    const completeRef = userADb
      .collection('declarations')
      .doc('declaracion-completa');

    const batch = userADb.batch();

    batch.set(completeRef, completeDeclaration);

    batch.set(
      completeRef.collection('versions').doc('1'),
      {
        ...completeDeclaration,
        createdAt: new Date(),
      }
    );

    batch.set(
      completeRef.collection('events').doc('evento-creacion'),
      {
        event: 'CREADA',
        userId: 'usuario-a',
        dateTime: new Date(),
        version: 1,
        previousStatus: 'BORRADOR',
        newStatus: 'BORRADOR',
        observation: '',
      }
    );

    
    try {
      await assertSucceeds(batch.commit());

      console.log(
        'PRUEBA 8 APROBADA: guardado completo.'
      );
    } catch (error) {
      console.error(
        'PRUEBA 8 FALLIDA: el lote fue rechazado.'
      );
      console.error(
        'Código del error:',
        error.code
      );
      throw error;
    }


    // PRUEBA 9: impedir eventos falsificados.

    await assertFails(
      userADb
        .collection('declarations')
        .doc('declaracion-completa')
        .collection('events')
        .doc('evento-falso')
        .set({
          event: 'FINALIZADA',
          userId: 'usuario-a',
          dateTime: new Date(),
          version: 1,
          previousStatus: 'BORRADOR',
          newStatus: 'FINALIZADA',
          observation: '',
        })
    );

    console.log(
      'PRUEBA 9 APROBADA: no se pueden inventar eventos de auditoría.'
    );

    
    // PRUEBA 10: impedir una firma del declarante
    // cuando la declaración todavía está en BORRADOR.

    await testEnv.withSecurityRulesDisabled(async (context) => {
      const adminDb = context.firestore();

      await adminDb
        .collection('declarations')
        .doc('declaracion-firma-anticipada')
        .set({
          ownerId: 'usuario-a',
          superiorId: 'superior-1',
          periodId: '2026-II',
          status: 'BORRADOR',
          version: 1,
        });

      await adminDb
        .collection('declarations')
        .doc('declaracion-firma-anticipada')
        .collection('versions')
        .doc('1')
        .set({
          ownerId: 'usuario-a',
          superiorId: 'superior-1',
          periodId: '2026-II',
          status: 'BORRADOR',
          version: 1,
        });
    });

    await assertFails(
      userADb
        .collection('declarations')
        .doc('declaracion-firma-anticipada')
        .collection('versions')
        .doc('1')
        .collection('signatures')
        .doc('owner')
        .set({
          userId: 'usuario-a',
          name: 'Usuario de prueba',
          dateTime: new Date(),
          version: 1,
          signatureId: 'firma-falsa',
          hash: 'hash-falso',
          type: 'owner',
        })
    );

    console.log(
      'PRUEBA 10 APROBADA: no se puede firmar una declaración en BORRADOR.'
    );

   
    // PRUEBA 11: permitir validar una declaración
    // cuando está en estado BORRADOR.

    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore()
        .collection('declarations')
        .doc('declaracion-validacion')
        .set({
          ...completeDeclaration,
          status: 'BORRADOR',
          version: 1,
        });
    });

    await assertSucceeds(
      userADb
        .collection('declarations')
        .doc('declaracion-validacion')
        .update({
          status: 'VALIDADA',
          updatedAt: new Date(),
        })
    );

    console.log(
      'PRUEBA 11 APROBADA: el declarante puede validar su borrador.'
    );
 
    // PRUEBA 12: crear una nueva versión
    // después de una devolución.

    await testEnv.withSecurityRulesDisabled(async (context) => {
      const adminDb = context.firestore();

      await adminDb
        .collection('declarations')
        .doc('declaracion-devuelta')
        .set({
          ...completeDeclaration,
          status: 'DEVUELTA',
          version: 1,
          returnNote: 'Corregir los horarios.',
        });
    });

    const returnedRef = userADb
      .collection('declarations')
      .doc('declaracion-devuelta');

    const newVersionBatch = userADb.batch();

    newVersionBatch.update(returnedRef, {
      status: 'BORRADOR',
      version: 2,
      updatedAt: new Date(),
    });

    newVersionBatch.set(
      returnedRef.collection('versions').doc('2'),
      {
        ...completeDeclaration,
        status: 'BORRADOR',
        version: 2,
        createdAt: new Date(),
      }
    );

    await assertSucceeds(newVersionBatch.commit());

    console.log(
      'PRUEBA 12 APROBADA: se puede crear una nueva versión después de una devolución.'
    );

    
    // PRUEBA 13: firma legítima del declarante.
    // Cambiar estado, guardar firma y registrar evento.

    await testEnv.withSecurityRulesDisabled(async (context) => {
      const adminDb = context.firestore();

      await adminDb
        .collection('declarations')
        .doc('declaracion-firma-legitima')
        .set({
          ...completeDeclaration,
          status: 'PENDIENTE_FIRMA_DECLARANTE',
          version: 1,
        });

      await adminDb
        .collection('declarations')
        .doc('declaracion-firma-legitima')
        .collection('versions')
        .doc('1')
        .set({
          ...completeDeclaration,
          status: 'PENDIENTE_FIRMA_DECLARANTE',
          version: 1,
        });
    });

    const signingRef = userADb
      .collection('declarations')
      .doc('declaracion-firma-legitima');

    const signingBatch = userADb.batch();

    signingBatch.update(signingRef, {
      status: 'FIRMADA_POR_DECLARANTE',
      updatedAt: new Date(),
    });

    signingBatch.set(
      signingRef
        .collection('versions')
        .doc('1')
        .collection('signatures')
        .doc('owner'),
      {
        userId: 'usuario-a',
        name: 'Usuario de prueba',
        dateTime: new Date(),
        version: 1,
        signatureId: 'owner',
        hash: 'hash-de-prueba',
        type: 'DECLARANTE',
      }
    );

    signingBatch.set(
      signingRef.collection('events').doc('evento-firma-legitima'),
      {
        event: 'signOwner',
        userId: 'usuario-a',
        dateTime: new Date(),
        version: 1,
        previousStatus: 'PENDIENTE_FIRMA_DECLARANTE',
        newStatus: 'FIRMADA_POR_DECLARANTE',
        observation: '',
      }
    );

    await assertSucceeds(signingBatch.commit());

    console.log(
      'PRUEBA 13 APROBADA: firma, estado y evento guardados juntos.'
    );

    
    // PRUEBA 14: impedir inventar un evento de firma
    // cuando no existe una nueva transición.

    await assertFails(
      userADb
        .collection('declarations')
        .doc('declaracion-firma-legitima')
        .collection('events')
        .doc('evento-firma-falso')
        .set({
          event: 'signOwner',
          userId: 'usuario-a',
          dateTime: new Date(),
          version: 1,
          previousStatus: 'PENDIENTE_FIRMA_DECLARANTE',
          newStatus: 'FIRMADA_POR_DECLARANTE',
          observation: '',
        })
    );

    console.log(
      'PRUEBA 14 APROBADA: no se pueden inventar eventos de firma.'
    );

    
    // PRUEBA 15: firma legítima del superior.

    await testEnv.withSecurityRulesDisabled(async (context) => {
      const adminDb = context.firestore();

      await adminDb.collection('users').doc('superior-1').set({
        role: 'superior',
      });

      await adminDb
        .collection('declarations')
        .doc('declaracion-firma-superior')
        .set({
          ...completeDeclaration,
          status: 'PENDIENTE_FIRMA_SUPERIOR',
          version: 1,
        });

      await adminDb
        .collection('declarations')
        .doc('declaracion-firma-superior')
        .collection('versions')
        .doc('1')
        .set({
          ...completeDeclaration,
          status: 'PENDIENTE_FIRMA_SUPERIOR',
          version: 1,
        });
    });

    const superiorDb = testEnv
      .authenticatedContext('superior-1')
      .firestore();

    const superiorRef = superiorDb
      .collection('declarations')
      .doc('declaracion-firma-superior');

    const superiorBatch = superiorDb.batch();

    superiorBatch.update(superiorRef, {
      status: 'FIRMADA_POR_SUPERIOR',
      updatedAt: new Date(),
    });

    superiorBatch.set(
      superiorRef
        .collection('versions')
        .doc('1')
        .collection('signatures')
        .doc('superior'),
      {
        userId: 'superior-1',
        name: 'Superior de prueba',
        dateTime: new Date(),
        version: 1,
        signatureId: 'superior',
        hash: 'hash-de-prueba',
        type: 'SUPERIOR',
      }
    );

    superiorBatch.set(
      superiorRef.collection('events').doc('evento-firma-superior'),
      {
        event: 'signSuperior',
        userId: 'superior-1',
        dateTime: new Date(),
        version: 1,
        previousStatus: 'PENDIENTE_FIRMA_SUPERIOR',
        newStatus: 'FIRMADA_POR_SUPERIOR',
        observation: '',
      }
    );

    await assertSucceeds(superiorBatch.commit());

    console.log(
      'PRUEBA 15 APROBADA: el superior puede firmar y registrar su evento.'
    );

    
    // PRUEBA 16: impedir eventos falsos
    // de firma del superior.

    await assertFails(
      superiorDb
        .collection('declarations')
        .doc('declaracion-firma-superior')
        .collection('events')
        .doc('evento-superior-falso')
        .set({
          event: 'signSuperior',
          userId: 'superior-1',
          dateTime: new Date(),
          version: 1,
          previousStatus: 'PENDIENTE_FIRMA_SUPERIOR',
          newStatus: 'FIRMADA_POR_SUPERIOR',
          observation: '',
        })
    );

    console.log(
      'PRUEBA 16 APROBADA: el superior no puede inventar eventos de firma.'
    );

    
    // PRUEBA 17: impedir eventos CREADA duplicados.

    await assertFails(
      userADb
        .collection('declarations')
        .doc('declaracion-completa')
        .collection('events')
        .doc('evento-creacion-duplicado')
        .set({
          event: 'CREADA',
          userId: 'usuario-a',
          dateTime: new Date(),
          version: 1,
          previousStatus: 'BORRADOR',
          newStatus: 'BORRADOR',
          observation: '',
        })
    );

    console.log(
      'PRUEBA 17 APROBADA: no se permiten eventos CREADA duplicados.'
    );

    
    // PRUEBA 18: impedir marcar como firmada
    // una declaración sin guardar la firma.

    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore()
        .collection('declarations')
        .doc('declaracion-sin-firma')
        .set({
          ...completeDeclaration,
          status: 'PENDIENTE_FIRMA_DECLARANTE',
          version: 1,
        });
    });

    const unsignedRef = userADb
      .collection('declarations')
      .doc('declaracion-sin-firma');

    await assertFails(
      unsignedRef.update({
        status: 'FIRMADA_POR_DECLARANTE',
        updatedAt: new Date(),
      })
    );

    console.log(
      'PRUEBA 18 APROBADA: no se permite cambiar el estado sin guardar la firma.'
    );

    // ==========================================
    // PRUEBAS 19 A 24 - SEGURIDAD FIRESTORE
    // ==========================================

    const pendingResults = [];

    async function checkSecurityTest(number, description, testFunction) {
      try {
        await testFunction();

        console.log(
          `PRUEBA ${number} APROBADA: ${description}`
        );

        pendingResults.push({
          number: number,
          result: 'APROBADA',
        });
      } catch (error) {
        console.error(
          `PRUEBA ${number} FALLIDA: ${description}`
        );

        console.error(
          'Error:',
          error.message
        );

        pendingResults.push({
          number: number,
          result: 'FALLIDA',
        });
      }
    }

    // Crear documentos de prueba sin aplicar reglas.
    // Se usan identificadores diferentes para evitar
    // interferencias entre las pruebas.

    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();

      await db.collection('users').doc('superior-1').set({
        role: 'superior',
      });

      const declarations = [
        {
          id: 'test-19-superior',
          status: 'PENDIENTE_FIRMA_SUPERIOR',
        },
        {
          id: 'test-20-devolucion',
          status: 'PENDIENTE_FIRMA_SUPERIOR',
        },
        {
          id: 'test-21-sin-observacion',
          status: 'PENDIENTE_FIRMA_SUPERIOR',
        },
        {
          id: 'test-22-envio',
          status: 'FIRMADA_POR_SUPERIOR',
        },
        {
          id: 'test-23-recepcion',
          status: 'ENVIADA_A_RRHH',
        },
        {
          id: 'test-24-firma',
          status: 'FIRMADA_POR_DECLARANTE',
        },
      ];

      for (const item of declarations) {
        const ref = db
          .collection('declarations')
          .doc(item.id);

        const data = {
          ...completeDeclaration,
          status: item.status,
          version: 1,
        };

        await ref.set(data);

        await ref
          .collection('versions')
          .doc('1')
          .set(data);
      }

      // Crear una firma existente para la prueba 24.
      await db
        .collection('declarations')
        .doc('test-24-firma')
        .collection('versions')
        .doc('1')
        .collection('signatures')
        .doc('owner')
        .set({
          userId: 'usuario-a',
          name: 'Usuario de prueba',
          dateTime: new Date(),
          version: 1,
          signatureId: 'owner',
          hash: 'hash-original',
          type: 'DECLARANTE',
        });

      // Crear un usuario de Recursos Humanos.
      await db.collection('users').doc('rrhh-1').set({
        role: 'rrhh',
      });
    });

    const superiorTestDb = testEnv
      .authenticatedContext('superior-1')
      .firestore();

    const hrTestDb = testEnv
      .authenticatedContext('rrhh-1')
      .firestore();

    // ==========================================
    // PRUEBA 19
    // No permitir firma del superior sin documento.
    // ==========================================

    await checkSecurityTest(
      19,
      'El superior no puede firmar sin guardar la firma.',
      async () => {
        const ref = superiorTestDb
          .collection('declarations')
          .doc('test-19-superior');

        await assertFails(
          ref.update({
            status: 'FIRMADA_POR_SUPERIOR',
            updatedAt: new Date(),
          })
        );
      }
    );

    // ==========================================
    // PRUEBA 20
    // Permitir devolución legítima con evento.
    // ==========================================

    await checkSecurityTest(
      20,
      'El superior puede devolver una declaración.',
      async () => {
        const ref = superiorTestDb
          .collection('declarations')
          .doc('test-20-devolucion');

        const batch = superiorTestDb.batch();

        batch.update(ref, {
          status: 'DEVUELTA',
          returnNote: 'Corregir el horario declarado.',
          updatedAt: new Date(),
        });

        batch.set(
          ref.collection('events').doc('evento-devolucion'),
          {
            event: 'return',
            userId: 'superior-1',
            dateTime: new Date(),
            version: 1,
            previousStatus: 'PENDIENTE_FIRMA_SUPERIOR',
            newStatus: 'DEVUELTA',
            observation: 'Corregir el horario declarado.',
          }
        );

        await assertSucceeds(batch.commit());
      }
    );

    // ==========================================
    // PRUEBA 21
    // No permitir devolución sin observación.
    // ==========================================

    await checkSecurityTest(
      21,
      'No se permiten devoluciones sin observación.',
      async () => {
        const ref = superiorTestDb
          .collection('declarations')
          .doc('test-21-sin-observacion');

        await assertFails(
          ref.update({
            status: 'DEVUELTA',
            returnNote: '',
            updatedAt: new Date(),
          })
        );
      }
    );

    // ==========================================
    // PRUEBA 22
    // Enviar declaración a Recursos Humanos.
    // ==========================================

    await checkSecurityTest(
      22,
      'Recursos Humanos puede registrar el envío.',
      async () => {
        const ref = hrTestDb
          .collection('declarations')
          .doc('test-22-envio');

        const batch = hrTestDb.batch();

        batch.update(ref, {
          status: 'ENVIADA_A_RRHH',
          updatedAt: new Date(),
        });

        batch.set(
          ref.collection('events').doc('evento-envio'),
          {
            event: 'sendHr',
            userId: 'rrhh-1',
            dateTime: new Date(),
            version: 1,
            previousStatus: 'FIRMADA_POR_SUPERIOR',
            newStatus: 'ENVIADA_A_RRHH',
            observation: '',
          }
        );

        await assertSucceeds(batch.commit());
      }
    );

    // ==========================================
    // PRUEBA 23
    // Recepción y finalización en RR. HH.
    // ==========================================

    await checkSecurityTest(
      23,
      'Recursos Humanos puede recibir y finalizar.',
      async () => {
        const ref = hrTestDb
          .collection('declarations')
          .doc('test-23-recepcion');

        const receptionBatch = hrTestDb.batch();

        receptionBatch.update(ref, {
          status: 'RECIBIDA_RRHH',
          updatedAt: new Date(),
        });

        receptionBatch.set(
          ref.collection('events').doc('evento-recepcion'),
          {
            event: 'receive',
            userId: 'rrhh-1',
            dateTime: new Date(),
            version: 1,
            previousStatus: 'ENVIADA_A_RRHH',
            newStatus: 'RECIBIDA_RRHH',
            observation: '',
          }
        );

        await assertSucceeds(receptionBatch.commit());

        const finishBatch = hrTestDb.batch();

        finishBatch.update(ref, {
          status: 'FINALIZADA',
          updatedAt: new Date(),
        });

        finishBatch.set(
          ref.collection('events').doc('evento-finalizacion'),
          {
            event: 'finish',
            userId: 'rrhh-1',
            dateTime: new Date(),
            version: 1,
            previousStatus: 'RECIBIDA_RRHH',
            newStatus: 'FINALIZADA',
            observation: '',
          }
        );

        await assertSucceeds(finishBatch.commit());
      }
    );

    // ==========================================
    // PRUEBA 24
    // No permitir modificar una firma existente.
    // ==========================================

    await checkSecurityTest(
      24,
      'Las firmas existentes son inmutables.',
      async () => {
        const ref = userADb
          .collection('declarations')
          .doc('test-24-firma')
          .collection('versions')
          .doc('1')
          .collection('signatures')
          .doc('owner');

        await assertFails(
          ref.update({
            hash: 'hash-modificado',
          })
        );

        await assertFails(ref.delete());
      }
    );

    // ==========================================
    // RESUMEN
    // ==========================================

    console.log('\n=================================');
    console.log('RESUMEN DE PRUEBAS 19 A 24');
    console.log('=================================');

    for (const item of pendingResults) {
      console.log(
        `Prueba ${item.number}: ${item.result}`
      );
    }

    const failedCount = pendingResults.filter(
      (item) => item.result === 'FALLIDA'
    ).length;

    console.log(
      `Total aprobadas: ${6 - failedCount} de 6`
    );

    if (failedCount > 0) {
      process.exitCode = 1;
    }

    // ==========================================
    // PRUEBA 25
    // Modificar un borrador y registrar auditoría.
    // ==========================================

    const editRef = userADb
      .collection('declarations')
      .doc('declaracion-completa');

    const editBatch = userADb.batch();
    const editEventId = 'evento-modificacion';

    // Modificar el borrador.
    
editBatch.update(editRef, {
  observations: 'Horario actualizado por el declarante.',
  updatedAt: new Date(),
  lastEditEventId: editEventId,
});


    // Actualizar la versión del borrador.
    editBatch.update(
      editRef.collection('versions').doc('1'),
      {
        observations: 'Horario actualizado por el declarante.',
        updatedAt: new Date(),
      }
    );

    // Registrar el evento de auditoría.
    editBatch.set(
      editRef.collection('events').doc(editEventId),
      {
        
        event: 'MODIFICADA',
        userId: 'usuario-a',
        dateTime: new Date(),
        version: 1,
        previousStatus: 'BORRADOR',
        newStatus: 'BORRADOR',
        observation: '',
      }
    );

    try {
      await assertSucceeds(editBatch.commit());

      console.log(
        'PRUEBA 25 APROBADA: el declarante puede modificar un borrador y registrar el evento.'
      );
    } catch (error) {
      console.error(
        'PRUEBA 25 FALLIDA: no se pudo guardar la modificación con su evento.'
      );

      console.error('Código:', error.code);
      console.error('Mensaje:', error.message);

      // No detener las pruebas anteriores.
    }

    // ==========================================
    // PRUEBA 26
    // Impedir eventos MODIFICADA falsos.
    // ==========================================

    await assertFails(
      userADb
        .collection('declarations')
        .doc('declaracion-completa')
        .collection('events')
        .doc('evento-modificacion-falso')
        .set({
          event: 'MODIFICADA',
          userId: 'usuario-a',
          dateTime: new Date(),
          version: 1,
          previousStatus: 'BORRADOR',
          newStatus: 'BORRADOR',
          observation: '',
        })
    );

    console.log(
      'PRUEBA 26 APROBADA: no se permiten eventos MODIFICADA sin cambios.'
    );

    // ==========================================
    // PRUEBA 27
    // Impedir modificaciones sin auditoría.
    // ==========================================

    const noAuditRef = userADb
      .collection('declarations')
      .doc('declaracion-completa');

    await assertFails(
      noAuditRef.update({
        observations: 'Cambio sin evento de auditoría.',
        updatedAt: new Date(),
      })
    );

    console.log(
      'PRUEBA 27 APROBADA: no se permiten modificaciones sin auditoría.'
    );



 
  } finally {
    await testEnv.cleanup();
  }
}

main().catch((error) => {
  console.error('PRUEBA FALLIDA:', error);
  process.exitCode = 1;
});
