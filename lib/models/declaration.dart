import 'package:cloud_firestore/cloud_firestore.dart';

// ============================================================
// BLOQUES DE HORARIO
// ============================================================

class TimeBlock {
  final int day;
  final String start;
  final String end;

  const TimeBlock({
    required this.day,
    required this.start,
    required this.end,
  });

  // Convertir el bloque de horario a un mapa.

  Map<String, dynamic> toMap() {
    return {
      'day': day,
      'start': start,
      'end': end,
    };
  }

  // Crear un bloque de horario desde un mapa.

  factory TimeBlock.fromMap(Map<String, dynamic> map) {
    return TimeBlock(
      day: (map['day'] as num).toInt(),
      start: map['start'] ?? '',
      end: map['end'] ?? '',
    );
  }
}

// ============================================================
// NOMBRAMIENTOS Y TRABAJOS EXTERNOS
// ============================================================

class Appointment {
  final String workplace;
  final String position;
  final String startDate;
  final String endDate;

  final double expectedHours;

  final List<TimeBlock> blocks;

  const Appointment({
    required this.workplace,
    required this.position,
    required this.startDate,
    required this.endDate,
    required this.expectedHours,
    required this.blocks,
  });

  // Convertir el nombramiento a un mapa.

  Map<String, dynamic> toMap() {
    return {
      'workplace': workplace,
      'position': position,
      'startDate': startDate,
      'endDate': endDate,
      'expectedHours': expectedHours,
      'blocks': blocks.map((block) {
        return block.toMap();
      }).toList(),
    };
  }

  // Crear un nombramiento desde un mapa.

  factory Appointment.fromMap(Map<String, dynamic> map) {
    return Appointment(
      workplace: map['workplace'] ?? '',
      position: map['position'] ?? '',
      startDate: map['startDate'] ?? '',
      endDate: map['endDate'] ?? '',
      expectedHours: (map['expectedHours'] as num? ?? 0).toDouble(),
      blocks: (map['blocks'] as List? ?? []).map((block) {
        return TimeBlock.fromMap(
          Map<String, dynamic>.from(block),
        );
      }).toList(),
    );
  }
}

// ============================================================
// DECLARACIONES DE HORARIO
// ============================================================

class Declaration {
  final String id;
  final String ownerId;
  final String ownerName;
  final String identification;
  final String phone;
  final String email;
  final String unit;
  final String periodId;
  final String superiorId;
  final String status;
  final String observations;

  final int version;

  final List<Appointment> appointments;
  final List<Appointment> externalJobs;

  final DateTime updatedAt;

  Declaration({
    required this.id,
    required this.ownerId,
    required this.ownerName,
    required this.identification,
    required this.phone,
    required this.email,
    required this.unit,
    required this.periodId,
    required this.superiorId,
    required this.status,
    required this.observations,
    required this.version,
    required this.appointments,
    required this.externalJobs,
    required this.updatedAt,
  });

  // ==========================================================
  // CONVERTIR DECLARACION A MAPA PARA FIRESTORE
  // ==========================================================

  Map<String, dynamic> toMap() {
    return {
      'ownerId': ownerId,
      'ownerName': ownerName,
      'identification': identification,
      'phone': phone,
      'email': email,
      'unit': unit,
      'periodId': periodId,
      'superiorId': superiorId,
      'status': status,
      'observations': observations,
      'version': version,
      'appointments': appointments.map((appointment) {
        return appointment.toMap();
      }).toList(),
      'externalJobs': externalJobs.map((job) {
        return job.toMap();
      }).toList(),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  // ==========================================================
  // CREAR DECLARACION DESDE FIRESTORE
  // ==========================================================

  factory Declaration.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final map = document.data()!;

    return Declaration(
      id: document.id,
      ownerId: map['ownerId'] ?? '',
      ownerName: map['ownerName'] ?? '',
      identification: map['identification'] ?? '',
      phone: map['phone'] ?? '',
      email: map['email'] ?? '',
      unit: map['unit'] ?? '',
      periodId: map['periodId'] ?? '',
      superiorId: map['superiorId'] ?? '',
      status: map['status'] ?? 'BORRADOR',
      observations: map['observations'] ?? '',
      version: (map['version'] as num? ?? 1).toInt(),
      appointments: (map['appointments'] as List? ?? []).map((appointment) {
        return Appointment.fromMap(
          Map<String, dynamic>.from(appointment),
        );
      }).toList(),
      externalJobs: (map['externalJobs'] as List? ?? []).map((job) {
        return Appointment.fromMap(
          Map<String, dynamic>.from(job),
        );
      }).toList(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
