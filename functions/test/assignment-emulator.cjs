'use strict';
if (!process.env.FIRESTORE_EMULATOR_HOST) throw Error('Esta prueba requiere el emulador; no se ejecuta en Firebase real.');
const assert = require('node:assert/strict');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { HttpsError } = require('firebase-functions/v2/https');
initializeApp({projectId:'demo-assigned-declarations'});
const { publicarNombramiento } = require('../publicar-nombramiento');
const { createDeclarationHandlers } = require('../declaration-handlers');
const db = getFirestore();
const handlers = createDeclarationHandlers({db,FieldValue,HttpsError});
let count = 0;
async function check(name, action) {await action(); count++;console.log('PASS '+name);}
const request = data => ({auth:{uid:'owner'},data});
(async()=>{
  await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/demo-assigned-declarations/databases/(default)/documents`,{method:'DELETE'});
  const profile={role:'declarante',name:'María Pérez Mora',identification:'123456789',phone:'88887777',email:'maria@example.com',unit:'Sede del Sur',superiorId:'sup',superiorName:'Superior de prueba'};
  await db.doc('users/owner').set(profile);
  await db.doc('users/sup').set({role:'superior',name:'Superior de prueba',unit:'Sede del Sur'});
  await db.doc('periods/2027-I').set({enabled:true,name:'I ciclo 2027'});
  const blocks=[{day:2,start:'08:00',end:'12:00',courseCode:'IF0013'}, {day:4,start:'08:00',end:'12:00',courseCode:'IF0013'}];
  const input={uid:'owner',periodId:'2027-I',operationId:'operation1',appointment:{position:'Interino Bachiller',expectedHours:15,startDate:'2027-01-04',endDate:'2027-03-06',blocks}};
  let assignmentId;
  await check('Superior publica sin guardar período en el perfil del declarante',async()=>{
    const result=await publicarNombramiento.run({auth:{uid:'sup'},data:input});assignmentId=result.id;
    assert.equal((await db.doc('users/owner').get()).get('periodId'),undefined);
    assert.equal((await db.collection('users/owner/pendingAppointments').get()).size,1);
  });
  const source=(await db.doc(`users/owner/pendingAppointments/${assignmentId}`).get()).data();
  await check('Publicación conserva fracción y emite notificación',async()=>{
    assert.equal(source.workloadFraction,'3/8');
    assert((await db.doc(`users/owner/notifications/${assignmentId}`).get()).exists);
  });
  let payload={id:'',version:1,ownerName:profile.name,identification:profile.identification,phone:profile.phone,email:profile.email,unit:profile.unit,
    observations:'',periodId:source.periodId,superiorId:source.superiorId,appointments:[{
      assignmentId,workplace:source.workplace,position:source.position,expectedHours:source.expectedHours,
      startDate:source.startDate,endDate:source.endDate,workloadFraction:source.workloadFraction,blocks:source.blocks,
    }],externalJobs:[]};
  let declarationId;
  await check('Declarante guarda contacto original como borrador incompleto',async()=>{
    const result=await handlers.save(request(payload)); declarationId=result.id;payload.id=declarationId;
    assert.equal((await db.doc(`users/owner/pendingAppointments/${assignmentId}`).get()).get('declarationId'),declarationId);
  });
  await check('No se puede consumir la misma asignación en otra declaración',async()=>{
    await assert.rejects(handlers.save(request({...payload,id:''})),e=>e.code==='already-exists');
  });
  await check('No se puede modificar contacto ni desde una llamada manipulada',async()=>{
    const changed=structuredClone(payload);changed.appointments[0].blocks[0].end='11:00';
    await assert.rejects(handlers.save(request(changed)),e=>e.code==='permission-denied');
  });
  await check('No completa mientras falten consulta/preparación',async()=>{
    await assert.rejects(handlers.validateStored(request({id:declarationId,version:1})),e=>e.code==='failed-precondition');
  });
  payload.appointments[0].blocks.push(
    {day:1,start:'08:00',end:'10:00',courseCode:'IF0013',activityType:'CONSULTA'},
    {day:3,start:'07:00',end:'12:00',courseCode:'IF0013',activityType:'PREPARACION'});
  await check('Guarda 8 contacto, 2 consulta y 5 preparación sin duplicar asignación',async()=>{
    await handlers.save(request(payload));
    const current=(await db.doc(`declarations/${declarationId}`).get()).data();
    assert.equal(current.appointments.length,1);assert.equal(current.appointments[0].assignmentId,assignmentId);
  });
  await check('Reabrir y guardar sin cambios no duplica el borrador',async()=>{
    assert.equal((await handlers.save(request(payload))).saved,false);
    assert.equal((await db.collection('declarations').get()).size,1);
  });
  await check('Valida jornada completa y conserva versión',async()=>{
    const result=await handlers.validateStored(request({id:declarationId,version:1}));
    assert.equal(result.status,'VALIDADA');assert.equal(result.institutionalHours,15);
    const version=(await db.doc(`declarations/${declarationId}/versions/1`).get()).data();
    assert.equal(version.appointments[0].blocks.length,4);
  });
  console.log(`${count} comprobaciones de integración aprobadas.`);
})().catch(error=>{console.error(error);process.exitCode=1;}).finally(()=>db.terminate());
