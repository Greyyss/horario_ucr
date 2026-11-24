'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { enforceAssignments } = require('../assignment-policy');
const clone = value => structuredClone(value);
function scenario() {
  const profile = { name:'María Pérez Mora',identification:'123456789',phone:'88887777',email:'maria@example.com',superiorId:'sup' };
  const source = {superiorId:'sup',periodId:'2027-I',unit:'Sede del Sur',workplace:'Universidad de Costa Rica',position:'Interino Bachiller',expectedHours:15,startDate:'2027-01-04',endDate:'2027-03-06',blocks:[
    {day:2,start:'08:00',end:'12:00',courseCode:'IF0013',activityType:'CONTACTO'},
    {day:4,start:'08:00',end:'12:00',courseCode:'IF0013',activityType:'CONTACTO'},
  ]};
  const payload = {ownerName:profile.name,identification:profile.identification,phone:profile.phone,email:profile.email,unit:source.unit,periodId:source.periodId,superiorId:source.superiorId,
    appointments:[{...clone(source),assignmentId:'assignment1'}],externalJobs:[]};
  const sources = new Map([['assignment1',source]]);
  const db={collection:()=>({doc:()=>({collection:()=>({doc:id=>({id})})})})};
  const tx={get:async ref=>({exists:sources.has(ref.id),data:()=>sources.get(ref.id)})};
  const deny=(code,message)=>{throw Object.assign(Error(message),{code});};
  const args={db,tx,uid:'owner',payload,current:null,profile,declarationId:'d1',deny};
  return {...args,source,sources,run:()=>enforceAssignments(args),args};
}
const rejects = (f,code) => assert.rejects(f.run(), error=>error.code===code);
function complete(f) {
  f.payload.appointments[0].blocks.push(
    {day:1,start:'08:00',end:'10:00',courseCode:'IF0013',activityType:'CONSULTA'},
    {day:3,start:'07:00',end:'12:00',courseCode:'IF0013',activityType:'PREPARACION'});
}
test('Recibe asignación aunque el perfil no tenga período y recupera fracción antigua',async()=>{
 const f=scenario();const result=await f.run();assert.equal(result.payload.appointments[0].workloadFraction,'3/8');assert.equal(result.bindings.length,1);
});
test('Permite guardar borrador con ocho horas de contacto de quince',async()=>{await scenario().run();});
test('Permite completar 8 contacto + 2 consulta + 5 preparación',async()=>{const f=scenario();complete(f);f.args.complete=true;await f.run();});
test('Impide completar jornada pendiente',async()=>{const f=scenario();f.args.complete=true;await rejects(f,'failed-precondition');});
for(const [field,value] of [['position','Catedrático'],['expectedHours',20],['startDate','2027-02-01'],['endDate','2027-04-01'],['workplace','Otra universidad'],['workloadFraction','1/2']])
 test(`Bloquea modificación de ${field}`,async()=>{const f=scenario();f.payload.appointments[0][field]=value;await rejects(f,'permission-denied');});
test('Bloquea cambiar horas de contacto',async()=>{const f=scenario();f.payload.appointments[0].blocks[0].end='11:00';await rejects(f,'permission-denied');});
test('Bloquea quitar contacto',async()=>{const f=scenario();f.payload.appointments[0].blocks.pop();await rejects(f,'permission-denied');});
test('Bloquea agregar contacto',async()=>{const f=scenario();f.payload.appointments[0].blocks.push({...f.source.blocks[0],day:6});await rejects(f,'permission-denied');});
test('Bloquea inventar un curso para consulta',async()=>{const f=scenario();complete(f);f.payload.appointments[0].blocks[2].courseCode='IF9999';await rejects(f,'permission-denied');});
test('Bloquea actividad distinta de consulta o preparación',async()=>{const f=scenario();complete(f);f.payload.appointments[0].blocks[2].activityType='OTRO';await rejects(f,'permission-denied');});
test('Bloquea exceso de jornada',async()=>{const f=scenario();complete(f);f.payload.appointments[0].blocks.push({day:5,start:'08:00',end:'09:00',courseCode:'IF0013',activityType:'CONSULTA'});await rejects(f,'failed-precondition');});
test('Bloquea dos usos de la misma asignación en una declaración',async()=>{const f=scenario();f.payload.appointments.push(clone(f.payload.appointments[0]));await rejects(f,'invalid-argument');});
test('Bloquea asignación que ya pertenece a otro borrador',async()=>{const f=scenario();f.source.declarationId='another';await rejects(f,'already-exists');});
test('Permite reabrir la asignación vinculada al mismo borrador',async()=>{const f=scenario();f.source.declarationId='d1';f.args.current=clone(f.payload);await f.run();});
test('Bloquea referencia inexistente o de otro usuario',async()=>{const f=scenario();f.payload.appointments[0].assignmentId='other';await rejects(f,'not-found');});
test('Bloquea período o superior alterados',async()=>{const f=scenario();f.payload.periodId='2027-II';await rejects(f,'permission-denied');});
test('No permite crear nombramiento interno sin asignación del superior',async()=>{const f=scenario();delete f.payload.appointments[0].assignmentId;await rejects(f,'failed-precondition');});
test('No permite quitar referencia al reabrir',async()=>{const f=scenario();f.args.current=clone(f.payload);delete f.payload.appointments[0].assignmentId;await rejects(f,'failed-precondition');});
test('Bloquea editar datos personales desde el horario',async()=>{const f=scenario();f.payload.email='otro@example.com';await rejects(f,'permission-denied');});
test('Permite otra institución, pero sin reutilizar referencia interna',async()=>{const f=scenario();f.payload.externalJobs=[{...f.payload.appointments[0]}];await rejects(f,'invalid-argument');});
