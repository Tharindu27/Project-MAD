import 'package:cloud_firestore/cloud_firestore.dart' as firestore;

class UsageLogModel {
  UsageLogModel({
    required this.id,
    required this.action,
    required this.timestamp,
    required this.durationSeconds,
    required this.triggeredBy,
  });

  final String id;
  final String action;
  final DateTime timestamp;
  final int durationSeconds;
  final String triggeredBy;

  factory UsageLogModel.fromMap(String id, Map<String, dynamic> data) {
    return UsageLogModel(
      id: id,
      action: data['action']?.toString() ?? 'OFF',
      timestamp: data['timestamp'] != null ? (data['timestamp'] as firestore.Timestamp).toDate() : DateTime.now(),
      durationSeconds: int.tryParse(data['durationSeconds']?.toString() ?? '0') ?? 0,
      triggeredBy: data['triggeredBy']?.toString() ?? 'system',
    );
  }
}
