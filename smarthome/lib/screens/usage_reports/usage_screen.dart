import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/device_model.dart';
import '../../models/floor_model.dart';
import '../../models/usage_log_model.dart';
import '../../services/firestore_service.dart';

class UsageScreen extends StatelessWidget {
  UsageScreen({super.key});

  final FirestoreService _service = FirestoreService();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FloorModel>>(
      stream: _service.floorsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final floors = snapshot.data ?? [];
        if (floors.isEmpty) {
          return const Center(child: Text('No floors available yet.'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: floors.length,
          itemBuilder: (context, index) {
            final floor = floors[index];
            return Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.apartment)),
                title: Text(floor.name),
                subtitle: const Text('Open device usage directory'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => FloorDeviceDirectoryScreen(floor: floor),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}

class FloorDeviceDirectoryScreen extends StatelessWidget {
  const FloorDeviceDirectoryScreen({super.key, required this.floor});

  final FloorModel floor;

  @override
  Widget build(BuildContext context) {
    final service = FirestoreService();

    return Scaffold(
      appBar: AppBar(title: Text('${floor.name} Devices')),
      body: StreamBuilder<List<DeviceModel>>(
        stream: service.devicesStream(floor.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final devices = snapshot.data ?? [];
          if (devices.isEmpty) {
            return const Center(child: Text('No devices found on this floor.'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: devices.length,
            itemBuilder: (context, index) {
              final device = devices[index];
              return Card(
                child: ListTile(
                  leading: Icon(_iconForType(device.type)),
                  title: Text(device.name),
                  subtitle: Text(_deviceSubtitle(device)),
                  trailing: const Icon(Icons.analytics_outlined),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => DeviceAnalyticsScreen(
                          floor: floor,
                          deviceId: device.id,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  IconData _iconForType(DeviceType type) {
    switch (type) {
      case DeviceType.multiSwitchUnit:
        return Icons.electrical_services;
      case DeviceType.safetyAppliance:
        return Icons.iron;
      case DeviceType.scheduledLight:
        return Icons.lightbulb;
      case DeviceType.securityCamera:
        return Icons.camera_alt;
      case DeviceType.electricalOutlet:
        return Icons.power;
    }
  }

  String _deviceSubtitle(DeviceModel device) {
    final statusLabel = _statusLabel(device);
    if (statusLabel.isEmpty) {
      return '${device.wattage} W';
    }
    return '${device.wattage} W • $statusLabel';
  }

  String _statusLabel(DeviceModel device) {
    if (device.type == DeviceType.multiSwitchUnit && device.status == DeviceStatus.off) {
      return '';
    }

    final status = device.status;
    switch (status) {
      case DeviceStatus.on:
        return 'ON';
      case DeviceStatus.error:
        return 'ERROR';
      case DeviceStatus.disconnected:
        return 'DISCONNECTED';
      case DeviceStatus.off:
        return 'OFF';
    }
  }
}

class DeviceAnalyticsScreen extends StatefulWidget {
  const DeviceAnalyticsScreen({super.key, required this.floor, required this.deviceId});

  final FloorModel floor;
  final String deviceId;

  @override
  State<DeviceAnalyticsScreen> createState() => _DeviceAnalyticsScreenState();
}

class _DeviceAnalyticsScreenState extends State<DeviceAnalyticsScreen> {
  final FirestoreService _service = FirestoreService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Device Analytics')),
      body: StreamBuilder<DeviceModel?>(
        stream: _service.deviceStream(widget.floor.id, widget.deviceId),
        builder: (context, deviceSnapshot) {
          if (deviceSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final device = deviceSnapshot.data;
          if (device == null) {
            return const Center(child: Text('Device not found.'));
          }

          return StreamBuilder<List<UsageLogModel>>(
            stream: _service.usageLogsForAnalyticsStream(widget.floor.id, widget.deviceId),
            builder: (context, logsSnapshot) {
              if (logsSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final logs = logsSnapshot.data ?? <UsageLogModel>[];

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(device.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text('Wattage: ${device.wattage} W'),
                          const SizedBox(height: 12),
                          _LiveActiveTimerText(device: device),
                          const SizedBox(height: 8),
                          const Text(
                            'Usage metrics auto-update every 1 minute',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _MinuteTickerBuilder(
                    interval: const Duration(minutes: 1),
                    builder: (context, now) {
                      final liveDuration = _currentActiveDuration(device, now);
                      final loggedSeconds = _totalLoggedSeconds(logs);
                      final totalActiveSeconds = loggedSeconds + liveDuration.inSeconds;
                      final totalActiveHours = totalActiveSeconds / 3600.0;
                      final energyKwh = (device.wattage * totalActiveHours) / 1000.0;
                      final dailyData = _dailyStats(logs, liveDuration, now);
                      final weeklyData = _weeklyStats(logs, liveDuration, now);

                      return Column(
                        children: [
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Energy Used: ${energyKwh.toStringAsFixed(3)} kWh',
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Daily Usage (Hours)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 12),
                                  _UsageBarChart(values: dailyData),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Weekly Usage (Hours/Day)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 12),
                                  _UsageBarChart(values: weeklyData),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Duration _currentActiveDuration(DeviceModel device, DateTime now) {
    if (device.status != DeviceStatus.on) {
      return Duration.zero;
    }

    final start = device.turnedOnAt ?? device.lastUpdated;
    if (start == null) {
      return Duration.zero;
    }

    final elapsed = now.difference(start);
    if (elapsed.isNegative) {
      return Duration.zero;
    }
    return elapsed;
  }

  int _totalLoggedSeconds(List<UsageLogModel> logs) {
    return logs.fold(0, (sum, item) {
      if (item.durationSeconds <= 0) return sum;
      return sum + item.durationSeconds;
    });
  }

  Map<String, double> _dailyStats(List<UsageLogModel> logs, Duration liveDuration, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    var todaySeconds = 0;
    var yesterdaySeconds = 0;

    for (final log in logs) {
      if (log.durationSeconds <= 0) continue;
      final day = DateTime(log.timestamp.year, log.timestamp.month, log.timestamp.day);
      if (day == today) {
        todaySeconds += log.durationSeconds;
      } else if (day == yesterday) {
        yesterdaySeconds += log.durationSeconds;
      }
    }

    todaySeconds += liveDuration.inSeconds;

    return {
      'Yesterday': yesterdaySeconds / 3600.0,
      'Today': todaySeconds / 3600.0,
    };
  }

  Map<String, double> _weeklyStats(List<UsageLogModel> logs, Duration liveDuration, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final starts = List<DateTime>.generate(7, (index) => today.subtract(Duration(days: 6 - index)));
    final secondsByDay = <DateTime, int>{for (final day in starts) day: 0};

    for (final log in logs) {
      if (log.durationSeconds <= 0) continue;
      final day = DateTime(log.timestamp.year, log.timestamp.month, log.timestamp.day);
      if (secondsByDay.containsKey(day)) {
        secondsByDay[day] = (secondsByDay[day] ?? 0) + log.durationSeconds;
      }
    }

    secondsByDay[today] = (secondsByDay[today] ?? 0) + liveDuration.inSeconds;

    final result = <String, double>{};
    for (final day in starts) {
      result[_weekdayShort(day.weekday)] = (secondsByDay[day] ?? 0) / 3600.0;
    }
    return result;
  }

  String _weekdayShort(int weekday) {
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return labels[(weekday - 1).clamp(0, 6)];
  }

}

class _LiveActiveTimerText extends StatefulWidget {
  const _LiveActiveTimerText({required this.device});

  final DeviceModel device;

  @override
  State<_LiveActiveTimerText> createState() => _LiveActiveTimerTextState();
}

class _LiveActiveTimerTextState extends State<_LiveActiveTimerText> {
  late final Stream<DateTime> _clockStream;

  @override
  void initState() {
    super.initState();
    _clockStream = Stream<DateTime>.periodic(
      const Duration(seconds: 1),
      (_) => DateTime.now(),
    ).asBroadcastStream();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DateTime>(
      stream: _clockStream,
      initialData: DateTime.now(),
      builder: (context, snapshot) {
        final now = snapshot.data ?? DateTime.now();
        final liveDuration = _liveDuration(widget.device, now);
        return Text(
          'Active Timer: ${_formatHhMmSs(liveDuration)}',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        );
      },
    );
  }

  Duration _liveDuration(DeviceModel device, DateTime now) {
    if (device.status != DeviceStatus.on) {
      return Duration.zero;
    }

    final start = device.turnedOnAt ?? device.lastUpdated;
    if (start == null) {
      return Duration.zero;
    }

    final elapsed = now.difference(start);
    if (elapsed.isNegative) {
      return Duration.zero;
    }
    return elapsed;
  }

  String _formatHhMmSs(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }
}

class _MinuteTickerBuilder extends StatefulWidget {
  const _MinuteTickerBuilder({
    required this.interval,
    required this.builder,
  });

  final Duration interval;
  final Widget Function(BuildContext context, DateTime now) builder;

  @override
  State<_MinuteTickerBuilder> createState() => _MinuteTickerBuilderState();
}

class _MinuteTickerBuilderState extends State<_MinuteTickerBuilder> {
  late final Stream<DateTime> _stream;

  @override
  void initState() {
    super.initState();
    _stream = Stream<DateTime>.periodic(widget.interval, (_) => DateTime.now()).asBroadcastStream();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DateTime>(
      stream: _stream,
      initialData: DateTime.now(),
      builder: (context, snapshot) {
        final now = snapshot.data ?? DateTime.now();
        return widget.builder(context, now);
      },
    );
  }
}

class _UsageBarChart extends StatelessWidget {
  const _UsageBarChart({required this.values});

  final Map<String, double> values;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return const Text('No usage data yet.');
    }

    final maxValue = math.max(1.0, values.values.fold(0.0, (max, item) => item > max ? item : max));
    final entries = values.entries.toList();

    return SizedBox(
      height: 170,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: entries.map((entry) {
          final fraction = (entry.value / maxValue).clamp(0.0, 1.0);
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('${entry.value.toStringAsFixed(2)}h', style: const TextStyle(fontSize: 11)),
                  const SizedBox(height: 6),
                  Container(
                    height: 110 * fraction,
                    width: 24,
                    decoration: BoxDecoration(
                      color: Colors.teal,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(entry.key, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
