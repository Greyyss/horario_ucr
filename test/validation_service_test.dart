import 'package:flutter_test/flutter_test.dart';
import 'package:horario_ucr_integrador/models/declaration.dart';
import 'package:horario_ucr_integrador/services/validation_service.dart';
void main(){
 Appointment job(List<TimeBlock> b,{double expected=4})=>Appointment(workplace:'UCR',position:'Docente',startDate:'2026-08-01',endDate:'2026-12-01',expectedHours:expected,blocks:b);
 test('Horario válido',(){final r=ValidationService.validate([job([const TimeBlock(day:1,start:'08:00',end:'12:00')])],[]);expect(r.valid,true);});
 test('Detecta traslape',(){final r=ValidationService.validate([job([const TimeBlock(day:1,start:'08:00',end:'11:00'),const TimeBlock(day:1,start:'10:00',end:'12:00')],expected:5)],[]);expect(r.errors.any((e)=>e.contains('traslape')),true);});
 test('Rechaza almuerzo',(){final r=ValidationService.validate([job([const TimeBlock(day:1,start:'11:00',end:'15:00')])],[]);expect(r.valid,false);});
 test('Detecta hora final inválida',(){final r=ValidationService.validate([job([const TimeBlock(day:1,start:'15:00',end:'10:00')])],[]);expect(r.valid,false);});
}
