'use strict';
const fs=require('node:fs');
const path=require('node:path');
const assert=require('node:assert/strict');
const {initializeTestEnvironment,assertFails,assertSucceeds}=require('@firebase/rules-unit-testing');
const {setLogLevel}=require('firebase/firestore');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore,FieldValue}=require('firebase-admin/firestore');
const {HttpsError}=require('firebase-functions/v2/https');
const {createDeclarationHandlers}=require('../functions/declaration-handlers');
const projectId='demo-declaraucr-backend';
const results=[];
const report=path.join(__dirname,'../test-results/backend-results.json');
function write(){fs.writeFileSync(report,JSON.stringify({projectId,passed:results.filter(x=>x.pass).length,failed:results.filter(x=>!x.pass).length,results},null,2));}
const timeout=setTimeout(()=>{results.push({name:'Tiempo limite',pass:false,error:'El emulador no respondio en 180 segundos.'});write();process.exit(1);},180000);
const job=(extra={})=>({workplace:'UCR',position:'Docente',startDate:'2026-08-01',endDate:'2026-12-01',expectedHours:4,blocks:[{day:1,start:'08:00',end:'12:00'}],...extra});
const payload=(extra={})=>({id:'',version:1,periodId:'2026-II',superiorId:'superior',ownerName:'María José Pérez',identification:'123456789',phone:'88887777',email:'maria@example.com',unit:'Escuela de Informática',observations:'',appointments:[job()],externalJobs:[],...extra});
async function main(){
  if(process.env.FIRESTORE_EMULATOR_HOST!=='127.0.0.1:8186')throw Error('Solo se permite el emulador local 127.0.0.1:8186.');
  setLogLevel('silent');
  const app=initializeApp({projectId},'backend-tests');
  const db=getFirestore(app);
  const h=createDeclarationHandlers({db,FieldValue,HttpsError});
  const env=await initializeTestEnvironment({projectId,firestore:{host:'127.0.0.1',port:8186,rules:fs.readFileSync(path.join(__dirname,'backend.firestore.rules'),'utf8')}});
  const owner=env.authenticatedContext('owner').firestore();
  const other=env.authenticatedContext('other').firestore();
  const superior=env.authenticatedContext('superior').firestore();
  const hr=env.authenticatedContext('hr').firestore();
  const call=(method,data,uid='owner')=>h[method]({auth:uid?{uid}:null,data});
  const denies=(promise,code)=>assert.rejects(promise,e=>e instanceof HttpsError && e.code===code);
  async function check(name,fn){try{await fn();results.push({name,pass:true});console.log('PASS '+name);}catch(e){results.push({name,pass:false,error:e.message});console.error('FAIL '+name+': '+e.message);}write();}
  async function move(client,id,uid,event,from,to,signature){
    const ref=client.doc('declarations/'+id),b=client.batch();
    b.update(ref,{status:to,updatedAt:new Date(),...(event==='return'?{returnNote:'Corregir'}:{})});
    b.set(ref.collection('events').doc(event),{event,userId:uid,dateTime:new Date(),version:1,previousStatus:from,newStatus:to,observation:event==='return'?'Corregir':''});
    if(signature)b.set(ref.collection('versions').doc('1').collection('signatures').doc(signature),{userId:uid,version:1,dateTime:new Date()});
    return b.commit();
  }
  try{
    await env.clearFirestore();
    for(const [uid,role] of [['owner','declarante'],['other','declarante'],['superior','superior'],['hr','rrhh'],['admin','admin']])await db.doc('users/'+uid).set({role});
    await db.doc('periods/2026-II').set({enabled:true});
    await check('Servidor rechaza sesion ausente',()=>denies(call('save',payload(),null),'unauthenticated'));
    await check('Servidor rechaza ownerId enviado por cliente',()=>denies(call('save',payload({ownerId:'other'})),'invalid-argument'));
    await check('Servidor rechaza estado enviado por cliente',()=>denies(call('save',payload({status:'FINALIZADA'})),'invalid-argument'));
    for(const [name,patch] of [
      ['telefono con letras',{phone:'abcdefgh'}],
      ['fecha inexistente',{appointments:[job({startDate:'2026-04-31'})]}],
      ['jornada cero',{appointments:[job({expectedHours:0})]}],
      ['jornada externa negativa',{externalJobs:[job({expectedHours:-2})]}],
      ['dia invalido',{appointments:[job({blocks:[{day:7,start:'08:00',end:'12:00'}]})]}],
      ['ultimo nombramiento invalido',{appointments:[job(),job({position:''})]}],
      ['sin nombramientos',{appointments:[]}]
    ]) await check('Servidor rechaza '+name,()=>denies(call('save',payload(patch)),'invalid-argument'));
    await check('Rechazos no crean documentos ni historial',async()=>assert.equal((await db.collection('declarations').get()).size,0));
    let id;
    await check('Servidor crea padre, version y evento',async()=>{
      const r=await call('save',payload());id=r.id;
      const d=(await db.doc('declarations/'+id).get()).data();
      assert.equal(d.ownerId,'owner');assert.equal(d.status,'BORRADOR');
      assert((await db.doc(`declarations/${id}/versions/1`).get()).exists);
      assert.equal((await db.collection(`declarations/${id}/events`).get()).size,1);
    });
    await check('Servidor detecta guardado sin cambios',async()=>assert.equal((await call('save',payload({id}))).saved,false));
    await check('Servidor impide editar declaracion ajena',()=>denies(call('save',payload({id,phone:'88886666'}),'other'),'permission-denied'));
    await check('Servidor impide cambiar periodo',()=>denies(call('save',payload({id,periodId:'otro'})),'failed-precondition'));
    await check('Servidor impide cambiar superior',()=>denies(call('save',payload({id,superiorId:'other'})),'failed-precondition'));
    await check('Servidor conserva version frente a editor desactualizado',()=>denies(call('save',payload({id,version:2})),'failed-precondition'));
    await db.doc('declarations/'+id).update({returnNote:'Conservar devolucion'});
    await check('Servidor edita sin borrar devolucion ni createdAt',async()=>{
      const ref=db.doc(`declarations/${id}/versions/1`),before=(await ref.get()).data().createdAt;
      await call('save',payload({id,phone:'88886666'}));
      const d=(await db.doc('declarations/'+id).get()).data(),v=(await ref.get()).data();
      assert.equal(d.returnNote,'Conservar devolucion');assert.equal(v.createdAt.toMillis(),before.toMillis());assert.equal(v.phone,'88886666');
      assert.equal((await db.collection(`declarations/${id}/events`).get()).size,2);
    });
    await check('Reglas bloquean crear directamente desde SDK',()=>assertFails(owner.doc('declarations/direct').set({...payload(),ownerId:'owner',status:'BORRADOR'})));
    await check('Reglas bloquean editar contenido directamente',()=>assertFails(owner.doc('declarations/'+id).update({phone:'88885555'})));
    await check('Reglas bloquean adulterar version directamente',()=>assertFails(owner.doc(`declarations/${id}/versions/1`).update({appointments:[job({expectedHours:0})]})));
    await check('Reglas bloquean crear version directamente',()=>assertFails(owner.doc(`declarations/${id}/versions/2`).set({version:2,ownerId:'owner'})));
    await check('Reglas bloquean falsificar MODIFICADA',()=>assertFails(owner.doc(`declarations/${id}/events/fake`).set({event:'MODIFICADA',userId:'owner'})));
    await check('Reglas bloquean pasar a VALIDADA directamente',()=>assertFails(owner.doc('declarations/'+id).update({status:'VALIDADA'})));
    await check('Otro declarante no puede leer',()=>assertFails(other.doc('declarations/'+id).get()));
    await check('Superior asignado conserva lectura',()=>assertSucceeds(superior.doc('declarations/'+id).get()));
    await check('RRHH conserva lectura',()=>assertSucceeds(hr.doc('declarations/'+id).get()));
    await check('No se puede validar declaracion ajena',()=>denies(call('validateStored',{id,version:1},'other'),'permission-denied'));
    await check('Validacion servidor usa documento almacenado',async()=>{const r=await call('validateStored',{id,version:1,appointments:[job({expectedHours:0})]});assert.equal(r.status,'VALIDADA');});
    for(const [client,uid,event,from,to,sig] of [
      [owner,'owner','submit','VALIDADA','PENDIENTE_FIRMA_DECLARANTE'],
      [owner,'owner','signOwner','PENDIENTE_FIRMA_DECLARANTE','FIRMADA_POR_DECLARANTE','owner'],
      [owner,'owner','route','FIRMADA_POR_DECLARANTE','PENDIENTE_FIRMA_SUPERIOR'],
      [superior,'superior','signSuperior','PENDIENTE_FIRMA_SUPERIOR','FIRMADA_POR_SUPERIOR','superior'],
      [hr,'hr','sendHr','FIRMADA_POR_SUPERIOR','ENVIADA_A_RRHH'],
      [hr,'hr','receive','ENVIADA_A_RRHH','RECIBIDA_RRHH'],
      [hr,'hr','finish','RECIBIDA_RRHH','FINALIZADA']
    ])await check('Flujo conserva '+event,()=>assertSucceeds(move(client,id,uid,event,from,to,sig)));
    await check('Servidor no edita declaracion finalizada',()=>denies(call('save',payload({id,phone:'88884444'})),'failed-precondition'));
    for(const [name,jobs] of [
      ['almuerzo',[job({blocks:[{day:1,start:'11:00',end:'15:00'}]})]],
      ['traslape',[job({expectedHours:5,blocks:[{day:1,start:'08:00',end:'11:00'},{day:1,start:'10:00',end:'12:00'}]})]],
      ['total distinto',[job({expectedHours:5})]],
      ['maximo diario',[job({expectedHours:11,blocks:[{day:1,start:'06:00',end:'12:00'},{day:1,start:'13:00',end:'18:00'}]})]]
    ])await check('Borrador permite corregir '+name+' pero validar lo rechaza',async()=>{
      const r=await call('save',payload({appointments:jobs}));
      await denies(call('validateStored',{id:r.id,version:1}),'invalid-argument');
      assert.equal((await db.doc('declarations/'+r.id).get()).data().status,'BORRADOR');
      assert.equal((await db.collection(`declarations/${r.id}/events`).get()).size,1);
    });
    await check('Reglas bloquean falsificar nueva version',()=>assertFails(owner.doc('declarations/'+id).update({status:'BORRADOR',version:2})));
    await check('PDF artifact sigue reservado al servidor',()=>assertFails(hr.doc(`declarations/${id}/versions/1/artifacts/finalPdf`).set({url:'falso'})));
    await check('Devolucion y nueva version conservan el flujo',async()=>{
      const r=await call('save',payload());
      await call('validateStored',{id:r.id,version:1});
      await move(owner,r.id,'owner','submit','VALIDADA','PENDIENTE_FIRMA_DECLARANTE');
      await move(owner,r.id,'owner','signOwner','PENDIENTE_FIRMA_DECLARANTE','FIRMADA_POR_DECLARANTE','owner');
      await move(owner,r.id,'owner','route','FIRMADA_POR_DECLARANTE','PENDIENTE_FIRMA_SUPERIOR');
      await move(superior,r.id,'superior','return','PENDIENTE_FIRMA_SUPERIOR','DEVUELTA');
      await denies(call('newVersion',{id:r.id,version:1},'other'),'permission-denied');
      await call('newVersion',{id:r.id,version:1});
      const d=(await db.doc('declarations/'+r.id).get()).data();assert.equal(d.version,2);assert.equal(d.returnNote,'Corregir');
      await call('save',payload({id:r.id,version:2,phone:'88883333'}));
      await call('validateStored',{id:r.id,version:2});
    });
  }finally{await env.cleanup();await db.terminate();await deleteApp(app);write();clearTimeout(timeout);}
  console.log(`Resultado: ${results.filter(x=>x.pass).length} aprobadas, ${results.filter(x=>!x.pass).length} fallidas.`);
  if(results.some(x=>!x.pass))process.exitCode=1;
}
main().catch(e=>{console.error(e);results.push({name:'Error del ejecutor',pass:false,error:e.message});write();clearTimeout(timeout);process.exitCode=1;});

