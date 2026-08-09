import 'package:flutter/material.dart';
import '../../models/device_model.dart';
import '../../models/floor_model.dart';
import '../../services/firestore_service.dart';
import '../devices/device_control_sheet.dart';

class FloorDetailScreen extends StatefulWidget {
  const FloorDetailScreen({super.key, required this.floor});

  final FloorModel floor;

  @override
  State<FloorDetailScreen> createState() => _FloorDetailScreenState();
}

class _FloorDetailScreenState extends State<FloorDetailScreen> {
  final FirestoreService _service = FirestoreService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.floor.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => _showAddDeviceDialog(context),
            tooltip: 'Add device',
          ),
        ],
      ),
      body: StreamBuilder<List<DeviceModel>>(
        stream: _service.devicesStream(widget.floor.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final devices = snapshot.data ?? [];

          if (devices.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.devices_other_outlined, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('No devices on this floor yet', style: TextStyle(fontSize: 16, color: Colors.grey)),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => _showAddDeviceDialog(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add first device'),
                  ),
                ],
              ),
            );
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  Positioned.fill(
                    child: Image.network(
                      widget.floor.planImageUrl.isNotEmpty
                          ? widget.floor.planImageUrl
                          : 'https://images.unsplash.com/photo-1505693416388-ac5ce068fe85?auto=format&fit=crop&w=800&q=80',
                      fit: BoxFit.cover,
                    ),
                  ),
                  ...devices.map((device) {
                    final tileWidth = 100.0;
                    final maxLeft = (constraints.maxWidth - tileWidth).clamp(0.0, double.infinity);
                    final maxTop = (constraints.maxHeight - 120.0).clamp(0.0, double.infinity);
                    final left = (constraints.maxWidth * (device.xPercent / 100.0)).clamp(0.0, maxLeft).toDouble();
                    final top = (constraints.maxHeight * (device.yPercent / 100.0)).clamp(0.0, maxTop).toDouble();

                    return Positioned(
                      left: left,
                      top: top,
                      child: SizedBox(
                        width: tileWidth,
                        child: PositionedDeviceTile(
                          device: device,
                          floor: widget.floor,
                          onDelete: () => _deleteDevice(device),
                          onSettings: () => _showDeviceSettings(context, device),
                        ),
                      ),
                    );
                  }),
                ],
              );
            },
          );
        },
      ),
    );
  }

  void _showAddDeviceDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AddDeviceDialog(
        floor: widget.floor,
        onDeviceAdded: () {
          Navigator.pop(context);
          setState(() {});
        },
      ),
    );
  }

  void _showDeviceSettings(BuildContext context, DeviceModel device) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DeviceSettingsSheet(device: device, floor: widget.floor),
    );
  }

  Future<void> _deleteDevice(DeviceModel device) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete device?'),
        content: Text('Remove "${device.name}" from this floor?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _service.deleteDevice(floorId: widget.floor.id, deviceId: device.id);
    }
  }
}

class PositionedDeviceTile extends StatelessWidget {
  const PositionedDeviceTile({
    super.key,
    required this.device,
    required this.floor,
    required this.onDelete,
    required this.onSettings,
  });

  final DeviceModel device;
  final FloorModel floor;
  final VoidCallback onDelete;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onDelete,
      onTap: () => _showDeviceSheet(context),
      onSecondaryTap: onSettings,
      child: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _statusColor(device.status), width: 2),
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_deviceIcon(device.type), size: 32, color: _statusColor(device.status)),
            const SizedBox(height: 4),
            Text(device.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            if (_deviceStatusLabel(device).isNotEmpty)
              Text(_deviceStatusLabel(device), style: const TextStyle(fontSize: 9, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  void _showDeviceSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DeviceControlSheet(floor: floor, device: device),
    );
  }

  IconData _deviceIcon(DeviceType type) {
    switch (type) {
      case DeviceType.securityCamera:
        return Icons.camera_alt;
      case DeviceType.multiSwitchUnit:
        return Icons.electrical_services;
      case DeviceType.safetyAppliance:
        return Icons.iron;
      case DeviceType.scheduledLight:
        return Icons.lightbulb;
      default:
        return Icons.power;
    }
  }

  Color _statusColor(DeviceStatus status) {
    switch (status) {
      case DeviceStatus.on:
        return Colors.green;
      case DeviceStatus.error:
        return Colors.orange;
      case DeviceStatus.disconnected:
        return Colors.grey;
      default:
        return Colors.grey.shade700;
    }
  }

  String _deviceStatusLabel(DeviceModel device) {
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
      default:
        return 'OFF';
    }
  }
}

class AddDeviceDialog extends StatefulWidget {
  const AddDeviceDialog({super.key, required this.floor, required this.onDeviceAdded});

  final FloorModel floor;
  final VoidCallback onDeviceAdded;

  @override
  State<AddDeviceDialog> createState() => _AddDeviceDialogState();
}

class _AddDeviceDialogState extends State<AddDeviceDialog> {
  final FirestoreService _service = FirestoreService();
  final _nameController = TextEditingController();
  final _wattageController = TextEditingController(text: '60');
  final _maxOnDurationController = TextEditingController(text: '1800');
  final _switchCountController = TextEditingController(text: '2');
  String _selectedType = 'electrical_outlet';
  double _xPercent = 50;
  double _yPercent = 50;
  int _switchCount = 2;
  late List<TextEditingController> _switchLabelControllers;
  TimeOfDay _startTime = const TimeOfDay(hour: 18, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 6, minute: 0);
  bool _adding = false;

  final deviceTypes = [
    {'label': 'Electrical Outlet', 'value': 'electrical_outlet', 'icon': Icons.power},
    {'label': 'Multi-Switch Unit', 'value': 'multi_switch_unit', 'icon': Icons.electrical_services},
    {'label': 'Safety Appliance (Iron)', 'value': 'safety_appliance', 'icon': Icons.iron},
    {'label': 'Scheduled Light', 'value': 'scheduled_light', 'icon': Icons.lightbulb},
    {'label': 'Security Camera', 'value': 'security_camera', 'icon': Icons.camera_alt},
  ];

  @override
  void initState() {
    super.initState();
    _switchLabelControllers = List.generate(
      _switchCount,
      (index) => TextEditingController(text: 'Switch ${index + 1}'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Device to Floor'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Device name', hintText: 'e.g. Living Room Light'),
              enabled: !_adding,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _wattageController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Wattage (W)',
                hintText: 'e.g. 60',
              ),
              enabled: !_adding,
            ),
            const SizedBox(height: 16),
            const Text('Device type:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...deviceTypes.map((type) {
              final icon = type['icon'] as IconData;
              return RadioListTile<String>(
                value: type['value'] as String,
                groupValue: _selectedType,
                onChanged: _adding
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() => _selectedType = value);
                      },
                title: Row(
                  children: [
                    Icon(icon, size: 24),
                    const SizedBox(width: 12),
                    Text(type['label'] as String),
                  ],
                ),
              );
            }),
            const SizedBox(height: 16),
            _buildConditionalFields(),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            const Text('Position on Floor Plan', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('x_percent: ${_xPercent.toStringAsFixed(1)}%'),
                      Slider(
                        value: _xPercent,
                        min: 0,
                        max: 100,
                        divisions: 100,
                        label: '${_xPercent.toStringAsFixed(0)}%',
                        onChanged: _adding ? null : (value) => setState(() => _xPercent = value),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('y_percent: ${_yPercent.toStringAsFixed(1)}%'),
                      Slider(
                        value: _yPercent,
                        min: 0,
                        max: 100,
                        divisions: 100,
                        label: '${_yPercent.toStringAsFixed(0)}%',
                        onChanged: _adding ? null : (value) => setState(() => _yPercent = value),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _adding ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _adding ? null : _addDevice,
          child: _adding ? const CircularProgressIndicator(strokeWidth: 2) : const Text('Add Device'),
        ),
      ],
    );
  }

  Future<void> _addDevice() async {
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a device name')),
      );
      return;
    }

    if (_selectedType == 'multi_switch_unit' && _switchCount < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Number of switches must be at least 1')),
      );
      return;
    }

    final parsedMaxDuration = int.tryParse(_maxOnDurationController.text.trim()) ?? 0;
    if (_selectedType == 'safety_appliance' && parsedMaxDuration <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid max on duration (seconds)')),
      );
      return;
    }

    final parsedWattage = int.tryParse(_wattageController.text.trim()) ?? 0;
    if (parsedWattage <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid wattage in Watts')),
      );
      return;
    }

    setState(() => _adding = true);
    try {
      final gridWidth = widget.floor.gridWidth > 0 ? widget.floor.gridWidth : 4;
      final gridHeight = widget.floor.gridHeight > 0 ? widget.floor.gridHeight : 4;
      final derivedGridX = ((_xPercent / 100.0) * gridWidth).round().clamp(0, gridWidth);
      final derivedGridY = ((_yPercent / 100.0) * gridHeight).round().clamp(0, gridHeight);

      await _service.addDevice(
        floorId: widget.floor.id,
        name: _nameController.text.trim(),
        type: _selectedType,
        wattage: parsedWattage,
        gridX: derivedGridX,
        gridY: derivedGridY,
        xPercent: _xPercent,
        yPercent: _yPercent,
        switchCount: _selectedType == 'multi_switch_unit' ? _switchCount : 0,
        switchLabels: _switchLabelControllers.map((item) => item.text.trim()).toList(),
        maxOnDurationSeconds: _selectedType == 'safety_appliance' ? parsedMaxDuration : 0,
        scheduleStart: _selectedType == 'scheduled_light' ? _timeToString(_startTime) : null,
        scheduleEnd: _selectedType == 'scheduled_light' ? _timeToString(_endTime) : null,
      );
      if (mounted) widget.onDeviceAdded();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add device: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Widget _buildConditionalFields() {
    if (_selectedType == 'multi_switch_unit') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Number of Switches', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 12),
              SizedBox(
                width: 72,
                child: TextField(
                  enabled: !_adding,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(isDense: true),
                  onChanged: (value) {
                    final parsed = int.tryParse(value) ?? 0;
                    final normalized = parsed.clamp(0, 12);
                    if (normalized != _switchCount) {
                      _resizeSwitchLabelControllers(normalized);
                    }
                  },
                  controller: _switchCountController,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text('Switch Labels', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...List.generate(_switchLabelControllers.length, (index) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                controller: _switchLabelControllers[index],
                enabled: !_adding,
                decoration: InputDecoration(
                  labelText: 'Switch ${index + 1} Label',
                ),
              ),
            );
          }),
        ],
      );
    }

    if (_selectedType == 'safety_appliance') {
      return TextField(
        controller: _maxOnDurationController,
        enabled: !_adding,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'Max On Duration',
          hintText: 'Seconds (e.g. 1800)',
        ),
      );
    }

    if (_selectedType == 'scheduled_light') {
      return Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Start Time'),
            subtitle: Text(_timeToString(_startTime)),
            trailing: const Icon(Icons.access_time),
            onTap: _adding
                ? null
                : () async {
                    final time = await showTimePicker(context: context, initialTime: _startTime);
                    if (time != null) setState(() => _startTime = time);
                  },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('End Time'),
            subtitle: Text(_timeToString(_endTime)),
            trailing: const Icon(Icons.access_time),
            onTap: _adding
                ? null
                : () async {
                    final time = await showTimePicker(context: context, initialTime: _endTime);
                    if (time != null) setState(() => _endTime = time);
                  },
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  void _resizeSwitchLabelControllers(int nextCount) {
    final old = _switchLabelControllers;
    final next = List<TextEditingController>.generate(nextCount, (index) {
      if (index < old.length) {
        return old[index];
      }
      return TextEditingController(text: 'Switch ${index + 1}');
    });

    for (var i = nextCount; i < old.length; i++) {
      old[i].dispose();
    }

    setState(() {
      _switchCount = nextCount;
      _switchLabelControllers = next;
      _switchCountController.text = nextCount.toString();
    });
  }

  String _timeToString(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _wattageController.dispose();
    _maxOnDurationController.dispose();
    _switchCountController.dispose();
    for (final controller in _switchLabelControllers) {
      controller.dispose();
    }
    super.dispose();
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
                const Text('Schedule', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                ListTile(
                  title: const Text('Turn ON at'),
                  subtitle: Text(_timeToString(_scheduleStart)),
                  trailing: const Icon(Icons.access_time),
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
                  subtitle: Text(_timeToString(_scheduleEnd)),
                  trailing: const Icon(Icons.access_time),
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
              const Text('Position on Floor', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
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
                child: ElevatedButton(
                  onPressed: _saving ? null : _saveSettings,
                  child: _saving ? const CircularProgressIndicator(strokeWidth: 2) : const Text('Save Settings'),
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
      if (mounted) Navigator.pop(context);
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

