class FloorModel {
  FloorModel({
    required this.id,
    required this.name,
    required this.planImageUrl,
    required this.gridWidth,
    required this.gridHeight,
  });

  final String id;
  final String name;
  final String planImageUrl;
  final int gridWidth;
  final int gridHeight;

  factory FloorModel.fromMap(String id, Map<String, dynamic> data) {
    return FloorModel(
      id: id,
      name: data['name']?.toString() ?? 'Floor',
      planImageUrl: data['planImageUrl']?.toString() ?? '',
      gridWidth: int.tryParse(data['gridWidth']?.toString() ?? '0') ?? 0,
      gridHeight: int.tryParse(data['gridHeight']?.toString() ?? '0') ?? 0,
    );
  }
}
