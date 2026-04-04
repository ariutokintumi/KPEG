class IndoorObject {
  final int? id;
  final String objectId; // "obj_red_couch_01"
  final String name;
  final String category; // furniture, decoration, electronics, clothing, other
  final int photoCount;
  final String? thumbnailPath;
  final DateTime createdAt;

  IndoorObject({
    this.id,
    required this.objectId,
    required this.name,
    required this.category,
    this.photoCount = 0,
    this.thumbnailPath,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  static const categories = [
    'furniture',
    'decoration',
    'electronics',
    'clothing',
    'other',
  ];

  static String generateObjectId(String name) {
    final safeName = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
    final ts = DateTime.now().millisecondsSinceEpoch % 100000;
    return 'obj_${safeName}_$ts';
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null && id! > 0) 'id': id,
      'object_id': objectId,
      'name': name,
      'category': category,
      'photo_count': photoCount,
      'thumbnail_path': thumbnailPath,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory IndoorObject.fromMap(Map<String, dynamic> map) {
    return IndoorObject(
      id: map['id'] as int,
      objectId: map['object_id'] as String,
      name: map['name'] as String,
      category: map['category'] as String,
      photoCount: (map['photo_count'] as int?) ?? 0,
      thumbnailPath: map['thumbnail_path'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  factory IndoorObject.fromApiJson(Map<String, dynamic> json) {
    return IndoorObject(
      objectId: json['object_id'] as String,
      name: json['name'] as String,
      category: (json['category'] as String?) ?? 'other',
    );
  }
}
