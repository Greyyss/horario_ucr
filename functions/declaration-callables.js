'use strict';
const {onCall,HttpsError}=require('firebase-functions/v2/https');
const {getFirestore,FieldValue}=require('firebase-admin/firestore');
const {createDeclarationHandlers}=require('./declaration-handlers');
// Se carga desde index.js DESPUES de initializeApp().
const handlers=createDeclarationHandlers({db:getFirestore(),FieldValue,HttpsError});
const options={region:'us-east1',timeoutSeconds:60,maxInstances:2};
exports.saveDeclarationValidated=onCall(options,handlers.save);
exports.validateDeclarationSchedule=onCall(options,handlers.validateStored);
exports.newDeclarationVersion=onCall(options,handlers.newVersion);
