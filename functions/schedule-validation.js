'use strict';

class ScheduleValidationError extends Error {
  constructor(message) { super(message); this.name = 'ScheduleValidationError'; }
}
const fail = message => { throw new ScheduleValidationError(message); };
const isMap = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const letters = 'A-Za-zÁÉÍÓÚÜÑáéíóúüñÀÈÌÒÙàèìòùÂÊÎÔÛâêîôûÄËÏÖäëïöÇç';
const namePattern = new RegExp(`^[${letters}]+(?:[-'’][${letters}]+)*(?: [${letters}]+(?:[-'’][${letters}]+)*)+$`);
const fields = ['ownerName','identification','phone','email','unit','observations','appointments','externalJobs'];

function text(value, label) {
  if (typeof value !== 'string' || !value.trim()) fail(`${label}: el campo es obligatorio.`);
  return value;
}
function dateValue(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
  const [year,month,day] = value.split('-').map(Number);
  if (year < 1 || month < 1 || month > 12 || day < 1 || day > 31) return null;
  const leap = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
  if (day > [31,leap?29:28,31,30,31,30,31,31,30,31,30,31][month-1]) return null;
  return year*10000 + month*100 + day;
}
function minutes(value) {
  if (typeof value !== 'string' || !/^\d{1,2}:\d{1,2}$/.test(value)) fail('Formato de hora inválido.');
  const [hour,minute] = value.split(':').map(Number);
  if (hour > 23 || minute > 59) fail('Formato de hora inválido.');
  return hour*60 + minute;
}
function personal(data) {
  if (!isMap(data)) fail('Datos personales inválidos.');
  const n = data.ownerName;
  if (typeof n !== 'string' || n.length < 5 || n.length > 100 || !namePattern.test(n)) fail('Nombre completo inválido.');
  if (typeof data.identification !== 'string' || !/^[0-9]{9}$/.test(data.identification)) fail('La cédula debe tener nueve dígitos.');
  if (typeof data.phone !== 'string' || !/^[0-9]{8}$/.test(data.phone)) fail('El teléfono debe tener ocho dígitos.');
  if (typeof data.email !== 'string' || data.email.length > 254 || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(data.email)) fail('Correo inválido.');
  const u = data.unit;
  if (typeof u !== 'string' || u !== u.trim() || u.length < 2 || u.length > 150 || /[\r\n\t]/.test(u)) fail('Unidad inválida.');
  if (typeof data.observations !== 'string' || data.observations.length > 2000) fail('Observaciones inválidas.');
}

// Al guardar borradores se exige estructura valida. Las comprobaciones globales
// de horarios se aplican al pasar a VALIDADA, igual que en el proceso de Flutter.
function validateDeclarationData(data, { complete = false } = {}) {
  personal(data);
  if (!Array.isArray(data.appointments) || !data.appointments.length) fail('Debe registrar un nombramiento institucional.');
  if (!Array.isArray(data.externalJobs)) fail('La lista de trabajos externos es inválida.');
  const byDay = new Map();
  let internal = 0, external = 0, expected = 0;
  for (const [jobs,outside] of [[data.appointments,false],[data.externalJobs,true]]) {
    for (const job of jobs) {
      if (!isMap(job)) fail('Nombramiento inválido.');
      text(job.workplace,'Institución'); text(job.position,'Puesto');
      if (typeof job.expectedHours !== 'number' || !Number.isFinite(job.expectedHours) || job.expectedHours <= 0) fail('La jornada debe ser finita y mayor que cero.');
      const start = dateValue(job.startDate), end = dateValue(job.endDate);
      const noEnd = typeof job.endDate === 'string' && job.endDate.trim().toLowerCase() === 'no aplica';
      if (start === null || (!noEnd && (end === null || end < start))) fail('Vigencia inválida.');
      if (!Array.isArray(job.blocks) || !job.blocks.length) fail('Agregue un horario al nombramiento.');
      if (!outside) expected += job.expectedHours;
      for (const block of job.blocks) {
        if (!isMap(block) || !Number.isInteger(block.day) || block.day < 1 || block.day > 6) fail('Día de horario inválido.');
        const a = minutes(block.start), b = minutes(block.end);
        if (b <= a) fail('La hora final debe ser posterior a la inicial.');
        if (complete && a < 780 && b > 720) fail('Horario excluido de 12:00 a 13:00.');
        if (outside) external += (b-a)/60; else internal += (b-a)/60;
        if (!byDay.has(block.day)) byDay.set(block.day, []);
        byDay.get(block.day).push({start:a,end:b});
      }
    }
  }
  if (![internal,external,expected].every(Number.isFinite)) fail('Totales de jornada fuera de rango.');
  if (complete) {
    for (const blocks of byDay.values()) {
      blocks.sort((a,b)=>a.start-b.start);
      let total = 0, start, end;
      for (const b of blocks) {
        if (end === undefined) { start=b.start; end=b.end; }
        else if (b.start < end) fail('Existen traslapes entre horarios.');
        else { total += end-start; start=b.start; end=b.end; }
      }
      if (end !== undefined) total += end-start;
      if (total > 600) fail('Se excede el máximo diario de diez horas.');
    }
    if (Math.abs(internal-expected) > 0.001) fail('Las horas institucionales no coinciden con la jornada esperada.');
  }
  return { institutionalHours:internal, externalHours:external, expectedHours:expected };
}
module.exports = { ScheduleValidationError, validateDeclarationData, fields, dateValue, minutes };
