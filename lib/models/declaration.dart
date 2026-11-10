import 'package:cloud_firestore/cloud_firestore.dart';

class TimeBlock {
  final int day;
  final String start;
  final String end;
  final String? courseCode;
  final String? activityType;
  final String? activityName;

  const TimeBlock({
    required this.day,
    required this.start,
    required this.end,
    this.courseCode,
    this.activityType,
    this.activityName,
  });

  Map<String, dynamic> toMap() => {
        'day': day,
        'start': start,
        'end': end,
        if (courseCode != null) 'courseCode': courseCode,
        if (activityType != null) 'activityType': activityType,
        if (activityName != null) 'activityName': activityName,
      };

  factory TimeBlock.fromMap(Map<String, dynamic> map) => TimeBlock(
        day: (map['day'] as num).toInt(),
        start: map['start'] ?? '',
        end: map['end'] ?? '',
        courseCode: map['courseCode'] as String?,
        activityType: map['activityType'] as String?,
        activityName: map['activityName'] as String?,
      );
}

class Appointment {
  final String workplace;
  final String position;
  final String startDate;
  final String endDate;
  final double expectedHours;
  final List<TimeBlock> blocks;

  // Null conserva los registros antiguos y los trabajos externos por horas.
  final String? workloadFraction;

  const Appointment({
    required this.workplace,
    required this.position,
    required this.startDate,
    required this.endDate,
    required this.expectedHours,
    required this.blocks,
    this.workloadFraction,
  });

  Map<String, dynamic> toMap() => {
        'workplace': workplace,
        'position': position,
        'startDate': startDate,
        'endDate': endDate,
        'expectedHours': expectedHours,
        if (workloadFraction != null) 'workloadFraction': workloadFraction,
        'blocks': blocks.map((block) => block.toMap()).toList(),
      };

  factory Appointment.fromMap(Map<String, dynamic> map) => Appointment(
        workplace: map['workplace'] ?? '',
        position: map['position'] ?? '',
        startDate: map['startDate'] ?? '',
        endDate: map['endDate'] ?? '',
        expectedHours: (map['expectedHours'] as num? ?? 0).toDouble(),
        workloadFraction: map['workloadFraction'] as String?,
        blocks: (map['blocks'] as List? ?? [])
            .map((block) => TimeBlock.fromMap(Map<String, dynamic>.from(block)))
            .toList(),
      );
}

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

  // Motivo de devolución, independiente del resumen de horarios.
  final String returnNote;
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
    this.returnNote = '',
    required this.version,
    required this.appointments,
    required this.externalJobs,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
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
        'returnNote': returnNote,
        'version': version,
        'appointments': appointments.map((a) => a.toMap()).toList(),
        'externalJobs': externalJobs.map((a) => a.toMap()).toList(),
        'updatedAt': Timestamp.fromDate(updatedAt),
      };

  factory Declaration.fromDoc(DocumentSnapshot<Map<String, dynamic>> document) {
    final map = document.data()!;
    List<Appointment> appointments(dynamic value) => (value as List? ?? [])
        .map((job) => Appointment.fromMap(Map<String, dynamic>.from(job)))
        .toList();
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
      returnNote: map['returnNote'] ?? '',
      version: (map['version'] as num? ?? 1).toInt(),
      appointments: appointments(map['appointments']),
      externalJobs: appointments(map['externalJobs']),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
