import 'package:flutter/material.dart';
import '../../models/floor_model.dart';
import '../../services/firestore_service.dart';

class FloorsScreen extends StatelessWidget {
  FloorsScreen({super.key});

  final FirestoreService _service = FirestoreService();
  static const List<Map<String, String>> _backgroundOptions = [
    {
      'name': 'Minimal Loft',
      'url': 'https://images.unsplash.com/photo-1484101403633-562f891dc89a?auto=format&fit=crop&w=1200&q=80',
    },
    {
      'name': 'Warm Kitchen',
      'url': 'https://images.unsplash.com/photo-1556912173-3bb406ef7e77?auto=format&fit=crop&w=1200&q=80',
    },
    {
      'name': 'Open Hall',
      'url': 'https://images.unsplash.com/photo-1505691938895-1758d7feb511?auto=format&fit=crop&w=1200&q=80',
    },
    {
      'name': 'Studio Layout',
      'url': 'https://images.unsplash.com/photo-1502672260266-1c1ef2d93688?auto=format&fit=crop&w=1200&q=80',
    },
  ];

  Future<_FloorFormResult?> _showFloorFormDialog(
    BuildContext context, {
    FloorModel? initialFloor,
  }) async {
    final controller = TextEditingController(text: initialFloor?.name ?? '');
    var selectedUrl = initialFloor?.planImageUrl.isNotEmpty == true
        ? initialFloor!.planImageUrl
        : _backgroundOptions.first['url']!;

    return showDialog<_FloorFormResult>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(initialFloor == null ? 'Add Floor' : 'Edit Floor'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      labelText: 'Floor Name',
                      hintText: 'e.g. Ground Floor',
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Choose Background', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: 420,
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _backgroundOptions.map((option) {
                        final url = option['url']!;
                        final isSelected = selectedUrl == url;
                        return InkWell(
                          onTap: () => setDialogState(() => selectedUrl = url),
                          borderRadius: BorderRadius.circular(12),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 120,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected ? Colors.teal : Colors.grey.shade300,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ClipRRect(
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                                  child: Image.network(
                                    url,
                                    height: 72,
                                    width: 120,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Text(
                                    option['name']!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  final name = controller.text.trim();
                  if (name.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Floor name is required')),
                    );
                    return;
                  }
                  Navigator.pop(context, _FloorFormResult(name: name, planImageUrl: selectedUrl));
                },
                child: Text(initialFloor == null ? 'Create' : 'Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _editFloor(BuildContext context, FloorModel floor) async {
    final result = await _showFloorFormDialog(context, initialFloor: floor);
    if (result == null) return;

    await _service.updateFloor(
      floorId: floor.id,
      name: result.name,
      planImageUrl: result.planImageUrl,
    );
  }

  Future<void> _deleteFloor(BuildContext context, FloorModel floor) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Floor?'),
        content: Text('Remove "${floor.name}" and all its devices?'),
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
      await _service.deleteFloor(floor.id);
    }
  }

  Widget _buildFloorLeadingImage(FloorModel floor) {
    return CircleAvatar(
      radius: 22,
      backgroundImage: floor.planImageUrl.isNotEmpty ? NetworkImage(floor.planImageUrl) : null,
      child: floor.planImageUrl.isEmpty ? const Icon(Icons.home_work_outlined) : null,
    );
  }

  void _openFloor(BuildContext context, FloorModel floor) {
    Navigator.of(context).pushNamed('/floor', arguments: floor);
  }

  void _onFloorAction(BuildContext context, String value, FloorModel floor) {
    if (value == 'enter') {
      _openFloor(context, floor);
      return;
    }
    if (value == 'edit') {
      _editFloor(context, floor);
      return;
    }
    if (value == 'delete') {
      _deleteFloor(context, floor);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Smart Home Floors')),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await _showFloorFormDialog(context);
          if (result == null) return;
          await _service.addFloor(name: result.name, planImageUrl: result.planImageUrl);
        },
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<List<FloorModel>>(
        stream: _service.floorsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No floors available yet.'));
          }
          final floors = snapshot.data!;
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: floors.length,
            itemBuilder: (context, index) {
              final floor = floors[index];
              return Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _openFloor(context, floor),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: _buildFloorLeadingImage(floor),
                          title: Text(floor.name),
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) => _onFloorAction(context, value, floor),
                            itemBuilder: (context) => const [
                              PopupMenuItem<String>(
                                value: 'enter',
                                child: Row(children: [Icon(Icons.meeting_room, size: 18), SizedBox(width: 8), Text('Enter')]),
                              ),
                              PopupMenuItem<String>(
                                value: 'edit',
                                child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('Edit')]),
                              ),
                              PopupMenuItem<String>(
                                value: 'delete',
                                child: Row(children: [Icon(Icons.delete, size: 18, color: Colors.red), SizedBox(width: 8), Text('Delete', style: TextStyle(color: Colors.red))]),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
            );
        },
      ),
    );
  }
}

class _FloorFormResult {
  const _FloorFormResult({required this.name, required this.planImageUrl});

  final String name;
  final String planImageUrl;
}
