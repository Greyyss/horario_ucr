const {test}=require('node:test');
const assert=require('node:assert/strict');
const {validateDeclarationData,ScheduleValidationError}=require('../functions/schedule-validation');
function block(day=1,start='08:00',end='12:00'){return {day,start,end};}
function job(extra={}){return {workplace:'UCR',position:'Docente',startDate:'2026-08-01',endDate:'2026-12-01',expectedHours:4,blocks:[block()],...extra};}
function data(extra={}){return {ownerName:'María José Pérez',identification:'123456789',phone:'88887777',email:'maria@example.com',unit:'Escuela de Informática',observations:'',appointments:[job()],externalJobs:[],...extra};}
const deny=(d,complete=false)=>assert.throws(()=>validateDeclarationData(d,{complete}),ScheduleValidationError);
test('datos validos completos',()=>assert.deepEqual(validateDeclarationData(data(),{complete:true}),{institutionalHours:4,externalHours:0,expectedHours:4}));
for(const [field,value] of [['ownerName','Juan123 Pérez'],['identification','12345678A'],['phone','abcdefgh'],['phone',88887777],['email','correo@'],['unit',''],['observations','x'.repeat(2001)],['appointments',[]],['appointments',{}],['externalJobs',{}]]) test('datos invalidos '+field+' '+typeof value,()=>deny(data({[field]:value})));
for(const outside of [false,true]) {
  for(const [field,value] of [['workplace',''],['position',' '],['expectedHours',0],['expectedHours',-1],['expectedHours',NaN],['expectedHours',Infinity],['expectedHours','4'],['startDate','2026-02-29'],['startDate','2026-04-31'],['startDate','2025-13-01'],['endDate','2026-11-31'],['endDate','2026-01-01'],['blocks',[]]]) {
    test((outside?'externo':'institucional')+' rechaza '+field+' '+String(value),()=>deny(data(outside?{externalJobs:[job({blocks:[block(2)],[field]:value})]}:{appointments:[job({[field]:value})]})));
  }
}
for(const b of [block(0),block(7),block(1.5),block('1'),block(1,'24:00'),block(1,'08:60'),block(1,'texto'),block(1,'10:00','08:00'),block(1,'08:00','08:00')]) test('bloque invalido '+JSON.stringify(b),()=>deny(data({appointments:[job({blocks:[b]})]})));
test('valida todas las entradas, no solo la primera',()=>deny(data({appointments:[job(),job({blocks:[block(2)]}),job({position:''})]})));
test('valida todos los bloques, no solo el primero',()=>deny(data({appointments:[job({blocks:[block(),block(2),block(7)]})]})));
test('fecha bisiesta real',()=>validateDeclarationData(data({appointments:[job({startDate:'2024-02-29'})]})));
test('No aplica permitido',()=>validateDeclarationData(data({appointments:[job({endDate:'  NO APLICA  '})]})));
test('fechas iguales permitidas',()=>validateDeclarationData(data({appointments:[job({endDate:'2026-08-01'})]})));
test('borrador permite almuerzo para corregir antes de validar',()=>validateDeclarationData(data({appointments:[job({blocks:[block(1,'11:00','15:00')]})]})));
test('validar rechaza almuerzo',()=>deny(data({appointments:[job({blocks:[block(1,'11:00','15:00')]})]}),true));
test('validar permite iniciar a las 13',()=>validateDeclarationData(data({appointments:[job({expectedHours:2,blocks:[block(1,'13:00','15:00')]})]}),{complete:true}));
test('validar rechaza traslape interno',()=>deny(data({appointments:[job({expectedHours:5,blocks:[block(1,'08:00','11:00'),block(1,'10:00','12:00')]})]}),true));
test('validar rechaza bloque anidado',()=>deny(data({appointments:[job({expectedHours:5,blocks:[block(),block(1,'09:00','10:00')]})]}),true));
test('validar rechaza traslape externo',()=>deny(data({externalJobs:[job({expectedHours:1,blocks:[block(1,'09:00','10:00')]})]}),true));
test('validar rechaza traslape entre externos',()=>deny(data({externalJobs:[job({blocks:[block(2)]}),job({expectedHours:1,blocks:[block(2,'09:00','10:00')]})]}),true));
test('bloques contiguos permitidos',()=>validateDeclarationData(data({appointments:[job({blocks:[block(1,'08:00','10:00'),block(1,'10:00','12:00')]})]}),{complete:true}));
test('mismas horas dias distintos permitidas',()=>validateDeclarationData(data({appointments:[job({expectedHours:8,blocks:[block(),block(2)]})]}),{complete:true}));
test('10 horas permitidas',()=>validateDeclarationData(data({appointments:[job({expectedHours:10,blocks:[block(1,'06:00','12:00'),block(1,'13:00','17:00')]})]}),{complete:true}));
test('10 horas y 1 minuto rechazados',()=>deny(data({appointments:[job({expectedHours:10+1/60,blocks:[block(1,'06:00','12:00'),block(1,'13:00','17:01')]})]}),true));
test('maximo diario incluye externos',()=>deny(data({appointments:[job({expectedHours:6,blocks:[block(1,'06:00','12:00')]})],externalJobs:[job({expectedHours:5,blocks:[block(1,'13:00','18:00')]})]}),true));
test('faltante de horas rechazado',()=>deny(data({appointments:[job({expectedHours:5})]}),true));
test('exceso de horas rechazado',()=>deny(data({appointments:[job({expectedHours:3})]}),true));
test('externas no completan jornada UCR',()=>deny(data({appointments:[job({expectedHours:6})],externalJobs:[job({expectedHours:2,blocks:[block(2,'08:00','10:00')]})]}),true));
test('totales fraccionarios y externos separados',()=>assert.deepEqual(validateDeclarationData(data({appointments:[job({expectedHours:1.5,blocks:[block(1,'08:00','09:30')]})],externalJobs:[job({expectedHours:2.25,blocks:[block(2,'08:00','10:15')]})]}),{complete:true}),{institutionalHours:1.5,externalHours:2.25,expectedHours:1.5}));

