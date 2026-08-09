import 'package:flutter/material.dart';
import '../../models/device_model.dart';
import '../../models/floor_model.dart';
import '../../services/firestore_service.dart';

class DeviceControlSheet extends StatefulWidget {
  const DeviceControlSheet({super.key, required this.floor, required this.device});

  final FloorModel floor;
  final DeviceModel device;

  @override
  State<DeviceControlSheet> createState() => _DeviceControlSheetState();
}

class _DeviceControlSheetState extends State<DeviceControlSheet> {
  final FirestoreService _service = FirestoreService();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(widget.device.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.settings),
                  onPressed: () {
                    Navigator.pop(context);
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => DeviceSettingsSheet(device: widget.device, floor: widget.floor),
                    );
                  },
                  tooltip: 'Device settings',
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (widget.device.type == DeviceType.electricalOutlet) ...[
              SwitchListTile(
                title: const Text('Power'),
                value: widget.device.status == DeviceStatus.on,
                onChanged: (value) async {
                  await _service.updateDeviceStatus(
                    floorId: widget.floor.id,
                    deviceId: widget.device.id,
                    status: value ? 'ON' : 'OFF',
                    updatedBy: 'app',
                  );
                  if (mounted) Navigator.of(context).pop();
                },
              ),
            ] else if (widget.device.type == DeviceType.multiSwitchUnit) ...[
              ...widget.device.switches.map((switchItem) => SwitchListTile(
                title: Text(switchItem.label),
                value: switchItem.status,
                onChanged: (value) async {
                  await _service.updateSwitchStatus(
                    floorId: widget.floor.id,
                    deviceId: widget.device.id,
                    switchId: switchItem.id,
                    value: value,
                  );
                },
              )),
            ] else if (widget.device.type == DeviceType.safetyAppliance ||
                widget.device.type == DeviceType.scheduledLight) ...[
              ListTile(
                title: Text(widget.device.type == DeviceType.safetyAppliance ? 'Safety appliance' : 'Scheduled light'),
                subtitle: widget.device.type == DeviceType.safetyAppliance
                    ? Text('Max duration: ${widget.device.maxOnDurationSeconds}s')
                    : const Text('Uses ON/OFF schedule'),
              ),
              SwitchListTile(
                title: const Text('Turn on (manual override)'),
                value: widget.device.status == DeviceStatus.on,
                onChanged: (value) async {
                  await _service.updateDeviceStatus(
                    floorId: widget.floor.id,
                    deviceId: widget.device.id,
                    status: value ? 'ON' : 'OFF',
                    updatedBy: 'app',
                  );
                  if (value) {
                    await _service.addUsageLog(
                      floorId: widget.floor.id,
                      deviceId: widget.device.id,
                      action: 'ON',
                      durationSeconds: 0,
                      triggeredBy: 'app',
                    );
                  }
                },
              ),
              if (widget.device.scheduleStart != null && widget.device.scheduleEnd != null)
                ListTile(
                  title: const Text('Schedule'),
                  subtitle: Text('${widget.device.scheduleStart} → ${widget.device.scheduleEnd}'),
                  trailing: const Icon(Icons.alarm),
                ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => DeviceSettingsSheet(device: widget.device, floor: widget.floor),
                  );
                },
                icon: const Icon(Icons.edit),
                label: const Text('Edit Schedule & Position'),
              ),
            ] else ...[
              SwitchListTile(
                title: const Text('Camera Power'),
                subtitle: Text(widget.device.status == DeviceStatus.on ? 'Online' : 'Offline'),
                value: widget.device.status == DeviceStatus.on,
                onChanged: (value) async {
                  await _service.updateDeviceStatus(
                    floorId: widget.floor.id,
                    deviceId: widget.device.id,
                    status: value ? 'ON' : 'OFF',
                    updatedBy: 'app',
                  );
                  if (mounted) Navigator.of(context).pop();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class DeviceSettingsSheet extends StatefulWidget {
  const DeviceSettingsSheet({super.key, required this.device, required this.floor});

  final DeviceModel device;
  final FloorModel floor;

  @override
  State<DeviceSettingsSheet> createState() => _DeviceSettingsSheetState();
}

class _DeviceSettingsSheetState extends State<DeviceSettingsSheet> {
  final _nameController = TextEditingController();
  final _maxOnDurationController = TextEditingController();
  late List<TextEditingController> _switchLabelControllers;
  late double _xPercent;
  late double _yPercent;
  late TimeOfDay _scheduleStart;
  late TimeOfDay _scheduleEnd;
  final FirestoreService _service = FirestoreService();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.device.name;
    _maxOnDurationController.text = widget.device.maxOnDurationSeconds.toString();
    _switchLabelControllers = widget.device.switches
        .map((switchItem) => TextEditingController(text: switchItem.label))
        .toList();
    _xPercent = widget.device.xPercent;
    _yPercent = widget.device.yPercent;
    _scheduleStart = _parseTime(widget.device.scheduleStart ?? '18:00');
    _scheduleEnd = _parseTime(widget.device.scheduleEnd ?? '06:00');
  }

  TimeOfDay _parseTime(String timeStr) {
    try {
      final parts = timeStr.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    } catch (e) {
      return const TimeOfDay(hour: 18, minute: 0);
    }
  }

  String _timeToString(TimeOfDay time) => '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Device Settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Device Name'),
              ),
              const SizedBox(height: 16),
              if (widget.device.type == DeviceType.multiSwitchUnit) ...[
                const Text('Switch Labels', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...List.generate(_switchLabelControllers.length, (index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextField(
                      controller: _switchLabelControllers[index],
                      decoration: InputDecoration(labelText: 'Switch ${index + 1} Label'),
                    ),
                  );
                }),
                const SizedBox(height: 12),
              ],
              if (widget.device.type == DeviceType.safetyAppliance) ...[
                TextField(
                  controller: _maxOnDurationController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Max On Duration',
                    hintText: 'Seconds',
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (widget.device.type == DeviceType.scheduledLight) ...[
                const Text('⏰ Schedule', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orange)),
                const SizedBox(height: 12),
                ListTile(
                  title: const Text('Turn ON at'),
                  subtitle: Text(_timeToString(_scheduleStart), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  trailing: const Icon(Icons.access_time, color: Colors.orange),
                  onTap: () async {
                    final time = await showTimePicker(
                      context: context,
                      initialTime: _scheduleStart,
                    );
                    if (time != null) setState(() => _scheduleStart = time);
                  },
                ),
                ListTile(
                  title: const Text('Turn OFF at'),
                  subtitle: Text(_timeToString(_scheduleEnd), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  trailing: const Icon(Icons.access_time, color: Colors.orange),
                  onTap: () async {
                    final time = await showTimePicker(
                      context: context,
                      initialTime: _scheduleEnd,
                    );
                    if (time != null) setState(() => _scheduleEnd = time);
                  },
                ),
                const SizedBox(height: 12),
              ],
              const Text('📍 Position on Floor', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.teal)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('x_percent: ${_xPercent.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        Slider(
                          value: _xPercent,
                          min: 0,
                          max: 100,
                          divisions: 100,
                          label: '${_xPercent.toStringAsFixed(0)}%',
                          onChanged: (v) => setState(() => _xPercent = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('y_percent: ${_yPercent.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        Slider(
                          value: _yPercent,
                          min: 0,
                          max: 100,
                          divisions: 100,
                          label: '${_yPercent.toStringAsFixed(0)}%',
                          onChanged: (v) => setState(() => _yPercent = v),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _saveSettings,
                  icon: const Icon(Icons.save),
                  label: _saving ? const Text('Saving...') : const Text('Save All Changes'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveSettings() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Device name is required')),
      );
      return;
    }

    final parsedDuration = int.tryParse(_maxOnDurationController.text.trim()) ?? 0;
    if (widget.device.type == DeviceType.safetyAppliance && parsedDuration <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid max on duration in seconds')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final gridWidth = widget.floor.gridWidth > 0 ? widget.floor.gridWidth : 4;
      final gridHeight = widget.floor.gridHeight > 0 ? widget.floor.gridHeight : 4;
      final derivedGridX = ((_xPercent / 100.0) * gridWidth).round().clamp(0, gridWidth);
      final derivedGridY = ((_yPercent / 100.0) * gridHeight).round().clamp(0, gridHeight);

      final switches = List<Map<String, dynamic>>.generate(widget.device.switches.length, (index) {
        final existing = widget.device.switches[index];
        return {
          'id': existing.id,
          'label': _switchLabelControllers[index].text.trim().isEmpty
              ? 'Switch ${index + 1}'
              : _switchLabelControllers[index].text.trim(),
          'status': existing.status,
        };
      });

      await _service.updateDeviceConfiguration(
        floorId: widget.floor.id,
        deviceId: widget.device.id,
        name: _nameController.text.trim(),
        type: _typeValue(widget.device.type),
        gridX: derivedGridX,
        gridY: derivedGridY,
        xPercent: _xPercent,
        yPercent: _yPercent,
        switches: widget.device.type == DeviceType.multiSwitchUnit ? switches : null,
        maxOnDurationSeconds: widget.device.type == DeviceType.safetyAppliance ? parsedDuration : null,
        scheduleStart: widget.device.type == DeviceType.scheduledLight ? _timeToString(_scheduleStart) : null,
        scheduleEnd: widget.device.type == DeviceType.scheduledLight ? _timeToString(_scheduleEnd) : null,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✓ Settings saved'), duration: Duration(seconds: 1)),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _typeValue(DeviceType type) {
    switch (type) {
      case DeviceType.multiSwitchUnit:
        return 'multi_switch_unit';
      case DeviceType.safetyAppliance:
        return 'safety_appliance';
      case DeviceType.scheduledLight:
        return 'scheduled_light';
      case DeviceType.securityCamera:
        return 'security_camera';
      case DeviceType.electricalOutlet:
        return 'electrical_outlet';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _maxOnDurationController.dispose();
    for (final controller in _switchLabelControllers) {
      controller.dispose();
    }
    super.dispose();
  }
}
