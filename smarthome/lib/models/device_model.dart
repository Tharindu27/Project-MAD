import 'package:cloud_firestore/cloud_firestore.dart' as firestore;

enum DeviceType { electricalOutlet, multiSwitchUnit, safetyAppliance, scheduledLight, securityCamera }

enum DeviceStatus { on, off, error, disconnected }

class SwitchOption {
  SwitchOption({required this.id, required this.label, required this.status});

  final String id;
  final String label;
  final bool status;

  factory SwitchOption.fromMap(Map<String, dynamic> data) {
    return SwitchOption(
      id: data['id']?.toString() ?? '',
      label: data['label']?.toString() ?? 'Switch',
      status: data['status'] == true,
    );
  }
}

class DeviceModel {
  DeviceModel({
    required this.id,
    required this.name,
    required this.type,
    required this.xPercent,
    required this.yPercent,
    required this.gridX,
    required this.gridY,
    required this.status,
    required this.wattage,
    required this.lastUpdatedBy,
    required this.lastUpdated,
    this.switches = const [],
    this.maxOnDurationSeconds = 1800,
    this.turnedOnAt,
    this.scheduleStart,
    this.scheduleEnd,
    this.mockStreamUrl = '',
    this.lastSnapshotUrl = '',
  });

  final String id;
  final String name;
  final DeviceType type;
  final double xPercent;
  final double yPercent;
  final int gridX;
  final int gridY;
  final DeviceStatus status;
  final int wattage;
  final String lastUpdatedBy;
  final DateTime? lastUpdated;
  final List<SwitchOption> switches;
  final int maxOnDurationSeconds;
  final DateTime? turnedOnAt;
  final String? scheduleStart;
  final String? scheduleEnd;
  final String mockStreamUrl;
  final String lastSnapshotUrl;

  factory DeviceModel.fromMap(String id, Map<String, dynamic> data) {
    final typeValue = data['type']?.toString() ?? 'electrical_outlet';
    final statusValue = data['status']?.toString() ?? 'OFF';
    final rawSwitches = data['switches'] as List<dynamic>? ?? const [];
    final parsedGridX = int.tryParse(data['gridX']?.toString() ?? '0') ?? 0;
    final parsedGridY = int.tryParse(data['gridY']?.toString() ?? '0') ?? 0;
    final parsedXPercent = double.tryParse(data['x_percent']?.toString() ?? '') ??
        (double.tryParse(data['xPercent']?.toString() ?? '') ?? (parsedGridX * 25.0));
    final parsedYPercent = double.tryParse(data['y_percent']?.toString() ?? '') ??
        (double.tryParse(data['yPercent']?.toString() ?? '') ?? (parsedGridY * 25.0));

    return DeviceModel(
      id: id,
      name: data['name']?.toString() ?? 'Device',
      type: _parseType(typeValue),
      xPercent: parsedXPercent.clamp(0.0, 100.0).toDouble(),
      yPercent: parsedYPercent.clamp(0.0, 100.0).toDouble(),
      gridX: parsedGridX,
      gridY: parsedGridY,
      status: _parseStatus(statusValue),
      wattage: int.tryParse(data['wattage']?.toString() ?? '60') ?? 60,
      lastUpdatedBy: data['lastUpdatedBy']?.toString() ?? 'app',
      lastUpdated: data['lastUpdated'] != null
          ? (data['lastUpdated'] as firestore.Timestamp).toDate()
          : null,
      switches: rawSwitches.map((item) => SwitchOption.fromMap(item as Map<String, dynamic>)).toList(),
      maxOnDurationSeconds: int.tryParse(data['maxOnDurationSeconds']?.toString() ?? '1800') ?? 1800,
      turnedOnAt: data['turnedOnAt'] != null ? (data['turnedOnAt'] as firestore.Timestamp).toDate() : null,
      scheduleStart: data['scheduleStart']?.toString(),
      scheduleEnd: data['scheduleEnd']?.toString(),
      mockStreamUrl: data['mockStreamUrl']?.toString() ?? '',
      lastSnapshotUrl: data['lastSnapshotUrl']?.toString() ?? '',
    );
  }

  static DeviceType _parseType(String value) {
    switch (value) {
      case 'electrical_outlet':
      case 'outlet':
        return DeviceType.electricalOutlet;
      case 'multi_switch_unit':
      case 'multi_switch':
        return DeviceType.multiSwitchUnit;
      case 'safety_appliance':
      case 'scheduled_appliance':
        return DeviceType.safetyAppliance;
      case 'scheduled_light':
        return DeviceType.scheduledLight;
      case 'security_camera':
      case 'camera':
        return DeviceType.securityCamera;
      default:
        return DeviceType.electricalOutlet;
    }
  }

  static DeviceStatus _parseStatus(String value) {
    switch (value.toUpperCase()) {
      case 'ON':
        return DeviceStatus.on;
      case 'ERROR':
        return DeviceStatus.error;
      case 'DISCONNECTED':
        return DeviceStatus.disconnected;
      default:
        return DeviceStatus.off;
    }
  }
}

