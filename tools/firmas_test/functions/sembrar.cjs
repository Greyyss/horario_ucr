'use strict';

const {
  initializeApp,
} = require('firebase-admin/app');

const {
  getAuth,
} = require('firebase-admin/auth');

const {
  getFirestore,
  Timestamp,
} = require('firebase-admin/firestore');

process.env.FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099';
process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';

initializeApp({
  projectId: 'demo-declara-firmas',
});

const db = getFirestore();
const auth = getAuth();

const PASSWORD = 'PruebasFirmas2026!';

async function main() {
  const people = [
    {
      uid: 'declarante-test',
      email: 'declarante@pruebas.local',
      name: 'Declarante de Prueba',
      role: 'declarante',
      identification: '100000001',
      superiorId: 'superior-test',
      superiorName: 'Superior de Prueba',
    },
    {
      uid: 'superior-test',
      email: 'superior@pruebas.local',
      name: 'Superior de Prueba',
      role: 'superior',
      identification: '200000002',
    },
    {
      uid: 'rrhh-test',
      email: 'rrhh@pruebas.local',
      name: 'Recursos Humanos de Prueba',
      role: 'rrhh',
      identification: '300000003',
    },
  ];

  for (const person of people) {
    try {
      await auth.getUser(person.uid);
    } catch (error) {
      if (error.code !== 'auth/user-not-found') throw error;

      await auth.createUser({
        uid: person.uid,
        email: person.email,
        password: PASSWORD,
        displayName: person.name,
        emailVerified: true,
      });
    }

    await db.collection('users').doc(person.uid).set({
      ...person,
      phone: '88888888',
      unit: 'Sede del Sur',
    }, { merge: true });
  }

  await db.collection('periods').doc('2026-III').set({
    enabled: true,
  });

  const ref = db.collection('declarations').doc('firma-local-001');

  if (!(await ref.get()).exists) {
    const declaration = {
      ownerId: 'declarante-test',
      ownerName: 'Declarante de Prueba',
      identification: '100000001',
      phone: '88888888',
      email: 'declarante@pruebas.local',
      unit: 'Sede del Sur',
      superiorId: 'superior-test',
      periodId: '2026-III',
      version: 1,
      status: 'VALIDADA',
      observations: 'Declaración ficticia para probar firmas.',
      appointments: [{
        workplace: 'Universidad de Costa Rica',
        position: 'Interino Bachiller',
        startDate: '2026-11-01',
        endDate: '2026-12-31',
        expectedHours: 5,
        workloadFraction: '1/8',
        blocks: [
          {
            day: 1,
            start: '08:00',
            end: '10:00',
            courseCode: 'IF0001',
            activityType: 'CONTACTO',
          },
          {
            day: 2,
            start: '08:00',
            end: '09:00',
            courseCode: 'IF0001',
            activityType: 'CONSULTA',
          },
          {
            day: 3,
            start: '08:00',
            end: '10:00',
            courseCode: 'IF0001',
            activityType: 'PREPARACION',
          },
        ],
      }],
      externalJobs: [],
      updatedAt: Timestamp.now(),
      createdAt: Timestamp.now(),
    };

    await ref.set(declaration);

    await ref.collection('versions').doc('1').set(declaration);
  }

  console.log('Usuarios y declaración local preparados.');
  console.log('Contraseña de prueba: ' + PASSWORD);

  await db.terminate();
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});