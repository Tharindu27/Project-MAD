import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/device_model.dart';
import '../models/floor_model.dart';
import '../models/usage_log_model.dart';

class FirestoreService {
  FirestoreService({FirebaseFirestore? firestore}) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  Timer? _safetyWatchdogTimer;
  bool _safetySweepRunning = false;

  void startSafetyWatchdog({Duration interval = const Duration(seconds: 5)}) {
    if (_safetyWatchdogTimer != null) return;

    _safetyWatchdogTimer = Timer.periodic(interval, (_) {
      enforceSafetyCutoffsNow();
    });

    enforceSafetyCutoffsNow();
  }

  void stopSafetyWatchdog() {
    _safetyWatchdogTimer?.cancel();
    _safetyWatchdogTimer = null;
  }

  Future<void> enforceSafetyCutoffsNow() async {
    if (_safetySweepRunning) return;
    _safetySweepRunning = true;

    try {
      final houseRef = await _firstHouseRef();
      if (houseRef == null) return;

      final floorsSnapshot = await houseRef.collection('floors').get();
      for (final floorDoc in floorsSnapshot.docs) {
        final devicesSnapshot = await floorDoc.reference.collection('devices').where('status', isEqualTo: 'ON').get();
        for (final deviceDoc in devicesSnapshot.docs) {
          final data = deviceDoc.data();
          final type = (data['type'] ?? '').toString();
          final wattage = int.tryParse((data['wattage'] ?? '0').toString()) ?? 0;
          final maxOnDurationSeconds = int.tryParse((data['maxOnDurationSeconds'] ?? '0').toString()) ?? 0;
          final isSafetyType = type == 'safety_appliance' || type == 'scheduled_appliance';
          final isHighPower = wattage >= 1000;

          if (maxOnDurationSeconds <= 0 || (!isSafetyType && !isHighPower)) {
            continue;
          }

          final turnedOnAtRaw = data['turnedOnAt'];
          if (turnedOnAtRaw == null) {
            continue;
          }

          final turnedOnAt = turnedOnAtRaw is Timestamp
              ? turnedOnAtRaw.toDate()
              : DateTime.tryParse(turnedOnAtRaw.toString());
          if (turnedOnAt == null) {
            continue;
          }

          final elapsed = DateTime.now().difference(turnedOnAt).inSeconds;
          if (elapsed <= maxOnDurationSeconds) {
            continue;
          }

          await deviceDoc.reference.update({
            'status': 'OFF',
            'turnedOnAt': null,
            'lastUpdatedBy': 'app-watchdog',
            'lastUpdated': FieldValue.serverTimestamp(),
          });

          await deviceDoc.reference.collection('usageLogs').add({
            'houseId': houseRef.id,
            'action': 'AUTO_OFF',
            'timestamp': FieldValue.serverTimestamp(),
            'durationSeconds': elapsed,
            'triggeredBy': 'app-watchdog',
          });

          await _firestore.collection('alerts').add({
            'houseId': houseRef.id,
            'floorId': floorDoc.id,
            'deviceId': deviceDoc.id,
            'floorName': floorDoc.data()['name']?.toString() ?? 'Unknown Floor',
            'deviceName': data['name']?.toString() ?? 'Unknown Device',
            'message': 'Safety Cutoff Triggered: [${floorDoc.data()['name']?.toString() ?? 'Unknown Floor'}] [${data['name']?.toString() ?? 'Unknown Device'}] was turned OFF automatically due to exceeding max_on_duration.',
            'createdAt': FieldValue.serverTimestamp(),
            'acknowledged': false,
            'severity': 'critical',
            'type': 'SAFETY_CUTOFF',
            'source': 'app-watchdog',
          });
        }
      }
    } finally {
      _safetySweepRunning = false;
    }
  }

  Stream<List<FloorModel>> floorsStream() {
    return Stream.fromFuture(_firstHouseRef()).asyncExpand((houseRef) {
      if (houseRef == null) {
        return Stream.value(<FloorModel>[]);
      }

      return houseRef.collection('floors').snapshots().map(
            (snapshot) => snapshot.docs.map((doc) => FloorModel.fromMap(doc.id, doc.data())).toList(),
          );
    }).asBroadcastStream();
  }

  Stream<List<DeviceModel>> devicesStream(String floorId) {
    return Stream.fromFuture(_firstHouseRef()).asyncExpand((houseRef) {
      if (houseRef == null) {
        return Stream.value(<DeviceModel>[]);
      }

      return houseRef.collection('floors').doc(floorId).collection('devices').snapshots().map(
            (snapshot) => snapshot.docs.map((doc) => DeviceModel.fromMap(doc.id, doc.data())).toList(),
          );
    }).asBroadcastStream();
  }

  Stream<DeviceModel?> deviceStream(String floorId, String deviceId) {
    return Stream.fromFuture(_firstHouseRef()).asyncExpand((houseRef) {
      if (houseRef == null) {
        return Stream.value(null);
      }

      return houseRef.collection('floors').doc(floorId).collection('devices').doc(deviceId).snapshots().map(
            (doc) => doc.exists ? DeviceModel.fromMap(doc.id, doc.data()!) : null,
          );
    }).asBroadcastStream();
  }

  Future<void> addFloor({required String name, required String planImageUrl}) async {
    final houseRef = await _userHouseRef(createIfMissing: true);
    if (houseRef == null) return;

    await houseRef.collection('floors').add({
      'name': name,
      'planImageUrl': planImageUrl,
      'gridWidth': 4,
      'gridHeight': 4,
    });
  }

  Future<void> updateFloor({
    required String floorId,
    required String name,
    required String planImageUrl,
  }) async {
    final houseRef = await _userHouseRef(createIfMissing: false);
    if (houseRef == null) return;
    await houseRef.collection('floors').doc(floorId).update({
      'name': name,
      'planImageUrl': planImageUrl,
    });
  }

  Future<void> addDevice({
    required String floorId,
    required String name,
    required String type,
    required int wattage,
    required int gridX,
    required int gridY,
    required double xPercent,
    required double yPercent,
    int switchCount = 0,
    List<String> switchLabels = const [],
    int maxOnDurationSeconds = 0,
    String? scheduleStart,
    String? scheduleEnd,
  }) async {
    final houseRef = await _userHouseRef(createIfMissing: false);
    if (houseRef == null) return;

    final normalizedSwitchCount = switchCount < 0 ? 0 : switchCount;
    final generatedSwitches = List.generate(normalizedSwitchCount, (index) {
      final label = index < switchLabels.length && switchLabels[index].trim().isNotEmpty
          ? switchLabels[index].trim()
          : 'Switch ${index + 1}';
      return {
        'id': 's${index + 1}',
        'label': label,
        'status': false,
      };
    });

    await houseRef.collection('floors').doc(floorId).collection('devices').add({
      'name': name,
      'type': type,
      'wattage': wattage,
      'gridX': gridX,
      'gridY': gridY,
      'x_percent': xPercent,
      'y_percent': yPercent,
      'status': 'OFF',
      'lastUpdated': FieldValue.serverTimestamp(),
      'lastUpdatedBy': 'system',
      'switches': type == 'multi_switch_unit'
          ? generatedSwitches
          : [],
      'maxOnDurationSeconds': type == 'safety_appliance' ? maxOnDurationSeconds : 0,
      'turnedOnAt': null,
      'scheduleStart': type == 'scheduled_light' ? scheduleStart : null,
      'scheduleEnd': type == 'scheduled_light' ? scheduleEnd : null,
      'mockStreamUrl': type == 'security_camera' ? 'https://www.w3schools.com/html/mov_bbb.mp4' : '',
      'lastSnapshotUrl': type == 'security_camera' ? 'https://images.unsplash.com/photo-1512918728675-ed5a9ecdebfd?auto=format&fit=crop&w=400&q=80' : '',
    });
  }

  Future<void> deleteDevice({required String floorId, required String deviceId}) async {
    final houseRef = await _userHouseRef(createIfMissing: false);
    if (houseRef == null) return;

    await houseRef.collection('floors').doc(floorId).collection('devices').doc(deviceId).delete();
  }

  Future<void> deleteFloor(String floorId) async {
    final houseRef = await _userHouseRef(createIfMissing: false);
    if (houseRef == null) return;

    await houseRef.collection('floors').doc(floorId).delete();
  }

  Future<void> updateDeviceSettings({
    required String floorId,
    required String deviceId,
    required int gridX,
    required int gridY,
    double? xPercent,
    double? yPercent,
    required String scheduleStart,
    required String scheduleEnd,
  }) async {
    final houseRef = await _userHouseRef(createIfMissing: false);
    if (houseRef == null) return;

    final resolvedX = xPercent ?? (gridX * 25.0);
    final resolvedY = yPercent ?? (gridY * 25.0);

    await houseRef.collection('floors').doc(floorId).collection('devices').doc(deviceId).update({
      'gridX': gridX,
      'gridY': gridY,
      'x_percent': resolvedX,
      'y_percent': resolvedY,
      'scheduleStart': scheduleStart,
      'scheduleEnd': scheduleEnd,
      'lastUpdated': FieldValue.serverTimestamp(),
      'lastUpdatedBy': 'app',
    });
  }

  Future<void> updateDeviceConfiguration({
    required String floorId,
    required String deviceId,
    required String name,
    required String type,
    int? wattage,
    required int gridX,
    required int gridY,
    required double xPercent,
    required double yPercent,
    List<Map<String, dynamic>>? switches,
    int? maxOnDurationSeconds,
    String? scheduleStart,
    String? scheduleEnd,
  }) async {
    final houseRef = await _userHouseRef(createIfMissing: false);
    if (houseRef == null) return;

    await houseRef.collection('floors').doc(floorId).collection('devices').doc(deviceId).update({
      'name': name,
      if (wattage != null) 'wattage': wattage,
      'gridX': gridX,
      'gridY': gridY,
      'x_percent': xPercent.clamp(0.0, 100.0).toDouble(),
      'y_percent': yPercent.clamp(0.0, 100.0).toDouble(),
      'switches': type == 'multi_switch_unit' ? (switches ?? []) : FieldValue.delete(),
      'maxOnDurationSeconds': type == 'safety_appliance' ? (maxOnDurationSeconds ?? 1800) : FieldValue.delete(),
      'scheduleStart': type == 'scheduled_light' ? scheduleStart : FieldValue.delete(),
      'scheduleEnd': type == 'scheduled_light' ? scheduleEnd : FieldValue.delete(),
      'lastUpdated': FieldValue.serverTimestamp(),
      'lastUpdatedBy': 'app',
    });
  }

  Future<void> updateDeviceStatus({required String floorId, required String deviceId, required String status, required String updatedBy}) async {
    final houseRef = await _userHouseRef(createIfMissing: false);
    if (houseRef == null) return;

    final deviceRef = houseRef.collection('floors').doc(floorId).collection('devices').doc(deviceId);
    final deviceSnapshot = await deviceRef.get();
    final current = deviceSnapshot.data() ?? <String, dynamic>{};
    final previousStatus = current['status']?.toString().toUpperCase() ?? 'OFF';
    final turnedOnAtRaw = current['turnedOnAt'];
    final now = DateTime.now();

    if (status.toUpperCase() == 'ON') {
      await deviceRef.update({
        'status': status,
        'turnedOnAt': FieldValue.serverTimestamp(),
        'lastUpdatedBy': updatedBy,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      return;
    }

    int durationSeconds = 0;
    if (previousStatus == 'ON' && turnedOnAtRaw is Timestamp) {
      final started = turnedOnAtRaw.toDate();
      durationSeconds = now.difference(started).inSeconds;
      if (durationSeconds < 0) durationSeconds = 0;
    }

    await deviceRef.update({
      'status': status,
      'turnedOnAt': null,
      'lastUpdatedBy': updatedBy,
      'lastUpdated': FieldValue.serverTimestamp(),
    });

    await addUsageLog(
      floorId: floorId,
      deviceId: deviceId,
      action: durationSeconds > 0 ? 'OFF' : 'STATUS_${status.toUpperCase()}',
      durationSeconds: durationSeconds,
      triggeredBy: updatedBy,
    );
  }

  Future<void> updateSwitchStatus({required String floorId, required String deviceId, required String switchId, required bool value}) async {
    final houseRef = await _userHouseRef(createIfMissing: false);
    if (houseRef == null) return;
    final ref = houseRef.collection('floors').doc(floorId).collection('devices').doc(deviceId);
    final doc = await ref.get();
    final switches = List<Map<String, dynamic>>.from((doc.data()?['switches'] as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map))); 
    for (final item in switches) {
      if (item['id'] == switchId) {
        item['status'] = value;
      }
    }
    await ref.update({
      'switches': switches,
      'lastUpdatedBy': 'app',
      'lastUpdated': FieldValue.serverTimestamp(),
    });
  }

  Future<void> addUsageLog({required String floorId, required String deviceId, required String action, required int durationSeconds, required String triggeredBy}) async {
    final houseRef = await _userHouseRef(createIfMissing: false);
    if (houseRef == null) return;
    final ref = houseRef.collection('floors').doc(floorId).collection('devices').doc(deviceId).collection('usageLogs');
    await ref.add({
      'houseId': houseRef.id,
      'action': action,
      'timestamp': FieldValue.serverTimestamp(),
      'durationSeconds': durationSeconds,
      'triggeredBy': triggeredBy,
    });
  }

  Stream<List<UsageLogModel>> usageLogsStream(String floorId, String deviceId) {
    return Stream.fromFuture(_firstHouseRef()).asyncExpand((houseRef) {
      if (houseRef == null) {
        return Stream.value(<UsageLogModel>[]);
      }

      return houseRef
          .collection('floors')
          .doc(floorId)
          .collection('devices')
          .doc(deviceId)
          .collection('usageLogs')
          .orderBy('timestamp', descending: true)
          .limit(10)
          .snapshots()
          .map((snapshot) => snapshot.docs.map((doc) => UsageLogModel.fromMap(doc.id, doc.data())).toList());
    }).asBroadcastStream();
  }

  Stream<List<UsageLogModel>> usageLogsForAnalyticsStream(String floorId, String deviceId, {int limit = 500}) {
    return Stream.fromFuture(_firstHouseRef()).asyncExpand((houseRef) {
      if (houseRef == null) {
        return Stream.value(<UsageLogModel>[]);
      }

      return houseRef
          .collection('floors')
          .doc(floorId)
          .collection('devices')
          .doc(deviceId)
          .collection('usageLogs')
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .snapshots()
          .map((snapshot) => snapshot.docs.map((doc) => UsageLogModel.fromMap(doc.id, doc.data())).toList());
    }).asBroadcastStream();
  }

  Stream<List<UsageLogModel>> recentUsageLogsStream() {
    return Stream.fromFuture(_firstHouseRef()).asyncExpand((houseRef) {
      if (houseRef == null) {
        return Stream.value(<UsageLogModel>[]);
      }

      return _firestore
          .collectionGroup('usageLogs')
          .where('houseId', isEqualTo: houseRef.id)
          .orderBy('timestamp', descending: true)
          .limit(10)
          .snapshots()
          .map((snapshot) => snapshot.docs.map((doc) => UsageLogModel.fromMap(doc.id, doc.data())).toList());
    }).asBroadcastStream();
  }

  Stream<List<Map<String, dynamic>>> safetyCutoffAlertsStream({int limit = 20}) {
    return Stream.fromFuture(_firstHouseRef()).asyncExpand((houseRef) {
      if (houseRef == null) {
        return Stream.value(<Map<String, dynamic>>[]);
      }

      return _firestore
          .collection('alerts')
          .where('houseId', isEqualTo: houseRef.id)
          .where('type', isEqualTo: 'SAFETY_CUTOFF')
          .where('acknowledged', isEqualTo: false)
          .limit(limit)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map(
                  (doc) => <String, dynamic>{
                    'id': doc.id,
                    ...doc.data(),
                  },
                )
                .toList(),
          );
    }).asBroadcastStream();
  }

  Future<void> acknowledgeSafetyAlert(String alertId) async {
    await _firestore.collection('alerts').doc(alertId).update({
      'acknowledged': true,
      'acknowledgedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<DocumentReference<Map<String, dynamic>>?> _firstHouseRef() async {
    return _userHouseRef(createIfMissing: false);
  }

  String? get _currentUserUid => FirebaseAuth.instance.currentUser?.uid;

  Future<DocumentReference<Map<String, dynamic>>?> _userHouseRef({
    required bool createIfMissing,
  }) async {
    final uid = _currentUserUid;
    if (uid == null) return null;

    final ownedHouses = await _firestore
        .collection('houses')
        .where('owners', arrayContains: uid)
        .limit(1)
        .get();
    if (ownedHouses.docs.isNotEmpty) {
      return ownedHouses.docs.first.reference;
    }

    if (!createIfMissing) return null;

    return _firestore.collection('houses').add({
      'name': 'My Smart House',
      'owners': [uid],
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
