import 'package:flutter/material.dart';

import '../../models/device_model.dart';
import '../../models/floor_model.dart';
import '../../services/firestore_service.dart';

class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  final FirestoreService _service = FirestoreService();

  Future<List<DeviceModel>> _loadCamerasForFloor(String floorId) async {
    final devices = await _service
        .devicesStream(floorId)
        .first
        .timeout(const Duration(seconds: 5), onTimeout: () => <DeviceModel>[]);
    return devices.where((device) => device.type == DeviceType.securityCamera).toList();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FloorModel>>(
      stream: _service.floorsStream(),
      builder: (context, floorsSnapshot) {
        if (floorsSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final floors = floorsSnapshot.data ?? const <FloorModel>[];
        if (floors.isEmpty) {
          return const Center(
            child: Text('No floors available yet. Add a floor to see security cameras here.'),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Camera Snapshots',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Live status for all CCTV devices',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54),
            ),
            const SizedBox(height: 16),
            ...floors.map((floor) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.black12),
                    boxShadow: const [
                      BoxShadow(
                        blurRadius: 10,
                        offset: Offset(0, 3),
                        color: Color(0x11000000),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          floor.name,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        FutureBuilder<List<DeviceModel>>(
                          future: _loadCamerasForFloor(floor.id),
                          builder: (context, devicesSnapshot) {
                            if (devicesSnapshot.connectionState == ConnectionState.waiting) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 24),
                                child: Center(child: CircularProgressIndicator()),
                              );
                            }

                            if (devicesSnapshot.hasError) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Text('Could not load cameras right now.'),
                              );
                            }

                            final cameras = devicesSnapshot.data ?? const <DeviceModel>[];

                            if (cameras.isEmpty) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Text('No security cameras in ${floor.name}.'),
                              );
                            }

                            return Column(
                              children: cameras
                                  .map(
                                    (camera) => Padding(
                                      padding: const EdgeInsets.only(bottom: 12),
                                      child: _CameraCard(camera: camera),
                                    ),
                                  )
                                  .toList(),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

class _CameraCard extends StatelessWidget {
  const _CameraCard({required this.camera});

  final DeviceModel camera;

  @override
  Widget build(BuildContext context) {
    final isOnline = camera.status == DeviceStatus.on;
    final previewSize = MediaQuery.of(context).size.width * 0.5;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              children: [
                Icon(
                  Icons.videocam,
                  size: 18,
                  color: isOnline ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    camera.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Center(
              child: SizedBox.square(
                dimension: previewSize,
                child: StreamBuilder<DateTime>(
                  stream: Stream<DateTime>.periodic(
                    const Duration(seconds: 1),
                    (_) => DateTime.now(),
                  ),
                  initialData: DateTime.now(),
                  builder: (context, timeSnapshot) {
                    final now = timeSnapshot.data ?? DateTime.now();
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF202020), width: 2),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x44000000),
                            blurRadius: 12,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (isOnline)
                              _onlinePreview(camera)
                            else
                              _offlinePreview(),
                            Positioned.fill(
                              child: IgnorePointer(
                                child: CustomPaint(
                                  painter: _ScanlinePainter(),
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.black.withValues(alpha: 0.12),
                                      const Color(0xFF00D084).withValues(alpha: 0.06),
                                      Colors.black.withValues(alpha: 0.16),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 8,
                              left: 8,
                              child: _CctvTag(
                                text: isOnline ? 'LIVE' : 'NO SIGNAL',
                                color: isOnline ? const Color(0xFFD62828) : const Color(0xFF4B5563),
                              ),
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: _StatusPill(isOnline: isOnline),
                            ),
                            Positioned(
                              left: 8,
                              bottom: 8,
                              child: _CctvTag(
                                text: _timestamp(now),
                                color: const Color(0xFF111827),
                              ),
                            ),
                            Positioned(
                              right: 8,
                              bottom: 8,
                              child: _CctvTag(
                                text: _channelLabel(camera.id),
                                color: const Color(0xFF111827),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              isOnline ? 'Online - live snapshot' : 'Offline - black preview',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }

  Widget _offlinePreview() {
    return Container(
      color: Colors.black,
      child: const Center(
        child: Icon(
          Icons.videocam_off,
          color: Colors.white54,
          size: 56,
        ),
      ),
    );
  }

  Widget _onlinePreview(DeviceModel camera) {
    if (camera.lastSnapshotUrl.isNotEmpty) {
      return Image.network(
        camera.lastSnapshotUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _generatedSnapshot(camera),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _generatedSnapshot(camera, loading: true);
        },
      );
    }

    return _generatedSnapshot(camera);
  }

  Widget _generatedSnapshot(DeviceModel camera, {bool loading = false}) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF0F766E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              loading ? Icons.hourglass_top : Icons.camera_alt,
              color: Colors.white.withValues(alpha: 0.85),
              size: 42,
            ),
            const SizedBox(height: 8),
            Text(
              camera.name,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Snapshot live',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
            ),
          ],
        ),
      ),
    );
  }

  String _timestamp(DateTime now) {
    return '${now.year}-${_twoDigits(now.month)}-${_twoDigits(now.day)} ${_twoDigits(now.hour)}:${_twoDigits(now.minute)}:${_twoDigits(now.second)}';
  }

  String _twoDigits(int value) => value.toString().padLeft(2, '0');

  String _channelLabel(String id) {
    final channelNumber = (id.hashCode.abs() % 16) + 1;
    return 'CH ${channelNumber.toString().padLeft(2, '0')}';
  }
}

class _CctvTag extends StatelessWidget {
  const _CctvTag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 11,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _ScanlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.08)
      ..strokeWidth = 1;

    const step = 4.0;
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.isOnline});

  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isOnline ? Colors.green.shade600 : Colors.grey.shade800,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isOnline ? 'Online' : 'Offline',
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      ),
    );
  }
}