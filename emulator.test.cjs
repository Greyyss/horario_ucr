'use strict';
const { isDeepStrictEqual } = require('node:util');
const { ScheduleValidationError, validateDeclarationData, fields } = require('./schedule-validation');

// El SDK Admin omite reglas: cada operacion aplica permisos, estado y validacion
// aqui, dentro de la misma transaccion que escribe documento/version/historial.
function createDeclarationHandlers({ db, FieldValue, HttpsError }) {
  const deny = (code,message) => { throw new HttpsError(code,message); };
  function uidOf(request) {
    if (!request.auth?.uid) deny('unauthenticated','Debés iniciar sesión.');
    return request.auth.uid;
  }
  function idOf(value) {
    if (typeof value !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(value)) deny('invalid-argument','Identificador inválido.');
    return value;
  }
  function versionOf(value) {
    if (!Number.isSafeInteger(value) || value < 1) deny('invalid-argument','Versión inválida.');
    return value;
  }
  function validate(data,complete=false) {
    try { return validateDeclarationData(data,{complete}); }
    catch(e) { if(e instanceof ScheduleValidationError) deny('invalid-argument',e.message); throw e; }
  }
  function checkOwner(current,uid,version,status) {
    if (!current) deny('not-found','La declaración no existe.');
    if (current.ownerId !== uid) deny('permission-denied','No podés modificar esta declaración.');
    if (current.status !== status || current.version !== version) deny('failed-precondition','La declaración cambió o no está en el estado requerido. Volvé a abrirla.');
  }
  function event(tx,ref,uid,type,version,from,to,extra={}) {
    const eventRef = ref.collection('events').doc();
    tx.set(eventRef,{event:type,userId:uid,dateTime:FieldValue.serverTimestamp(),version,previousStatus:from,newStatus:to,observation:'',...extra});
    return eventRef;
  }
  async function save(request) {
    const uid = uidOf(request), payload = request.data;
    if (!payload || typeof payload !== 'object' || Array.isArray(payload)) deny('invalid-argument','Datos inválidos.');
    const allowed = ['id','version','periodId','superiorId',...fields];
    if (Object.keys(payload).some(k=>!allowed.includes(k))) deny('invalid-argument','Se recibieron campos no permitidos.');
    const isNew = payload.id === '';
    const ref = isNew ? db.collection('declarations').doc() : db.collection('declarations').doc(idOf(payload.id));
    const version = versionOf(payload.version);
    if (isNew && version !== 1) deny('invalid-argument','Una declaración nueva comienza en versión 1.');
    idOf(payload.periodId); idOf(payload.superiorId);
    validate(payload);
    const editable = Object.fromEntries(fields.map(k=>[k,payload[k]]));
    return db.runTransaction(async tx => {
      const versionRef = ref.collection('versions').doc(String(version));
      const [snapshot,versionSnapshot,period] = await Promise.all([tx.get(ref),tx.get(versionRef),tx.get(db.collection('periods').doc(payload.periodId))]);
      if (!isNew) {
        const current = snapshot.data();
        checkOwner(current,uid,version,'BORRADOR');
        if (current.periodId !== payload.periodId || current.superiorId !== payload.superiorId) deny('failed-precondition','No se puede cambiar el período ni el superior de un borrador existente.');
        if (fields.every(k=>isDeepStrictEqual(current[k],editable[k]))) return {id:ref.id,saved:false};
      } else if (snapshot.exists) deny('already-exists','La declaración ya existe.');
      if (!period.exists || period.data().enabled !== true) deny('failed-precondition','El período no está habilitado.');
      const stamp = FieldValue.serverTimestamp();
      if (isNew) {
        const data = {...editable,ownerId:uid,periodId:payload.periodId,superiorId:payload.superiorId,status:'BORRADOR',version:1,updatedAt:stamp};
        tx.create(ref,data);
        tx.create(versionRef,{...data,createdAt:stamp});
        event(tx,ref,uid,'CREADA',1,'BORRADOR','BORRADOR');
      } else {
        const eventRef=event(tx,ref,uid,'MODIFICADA',version,'BORRADOR','BORRADOR');
        const patch={...editable,updatedAt:stamp,lastEditEventId:eventRef.id};
        tx.update(ref,patch);
        if (versionSnapshot.exists) {
          const v=versionSnapshot.data();
          if(v.ownerId!==uid || v.periodId!==payload.periodId || v.superiorId!==payload.superiorId || v.version!==version) deny('failed-precondition','La versión guardada no coincide con la declaración.');
          tx.update(versionRef,patch);
        } else tx.create(versionRef,{...snapshot.data(),...patch,createdAt:stamp});
      }
      return {id:ref.id,saved:true};
    });
  }
  async function validateStored(request) {
    const uid=uidOf(request), id=idOf(request.data?.id), version=versionOf(request.data?.version);
    const ref=db.collection('declarations').doc(id);
    return db.runTransaction(async tx => {
      const [snapshot,versionSnapshot]=await Promise.all([tx.get(ref),tx.get(ref.collection('versions').doc(String(version)))]);
      const current=snapshot.data();
      checkOwner(current,uid,version,'BORRADOR');
      const totals=validate(current,true);
      const v=versionSnapshot.data();
      if (!v || v.ownerId!==uid || v.version!==version || v.periodId!==current.periodId || v.superiorId!==current.superiorId || fields.some(k=>!isDeepStrictEqual(v[k],current[k]))) deny('failed-precondition','La versión no coincide con la declaración. Abrí el borrador, corregí los datos y guardalo.');
      tx.update(ref,{status:'VALIDADA',updatedAt:FieldValue.serverTimestamp()});
      event(tx,ref,uid,'validate',version,'BORRADOR','VALIDADA');
      return {id,status:'VALIDADA',...totals};
    });
  }
  async function newVersion(request) {
    const uid=uidOf(request), id=idOf(request.data?.id), version=versionOf(request.data?.version);
    if (!Number.isSafeInteger(version+1)) deny('invalid-argument','Versión fuera de rango.');
    const ref=db.collection('declarations').doc(id);
    return db.runTransaction(async tx => {
      const versionRef=ref.collection('versions').doc(String(version+1));
      const [snapshot,next]=await Promise.all([tx.get(ref),tx.get(versionRef)]);
      const current=snapshot.data();
      checkOwner(current,uid,version,'DEVUELTA');
      if(next.exists) deny('already-exists','La nueva versión ya existe.');
      // Copia canonica de un documento existente, incluso si es un borrador
      // antiguo que necesita correcciones antes de poder validarse otra vez.
      const patch={status:'BORRADOR',version:version+1,updatedAt:FieldValue.serverTimestamp()};
      tx.update(ref,patch);
      tx.create(versionRef,{...current,...patch,createdAt:FieldValue.serverTimestamp()});
      event(tx,ref,uid,'newVersion',version+1,'DEVUELTA','BORRADOR');
      return {id,version:version+1};
    });
  }
  return { save, validateStored, newVersion };
}
module.exports={createDeclarationHandlers};
