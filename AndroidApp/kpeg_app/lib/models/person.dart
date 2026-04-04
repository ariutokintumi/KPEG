class Person {
  final int? id;
  final String name;
  final String? referencePhotoPath;
  final DateTime createdAt;

  Person({
    this.id,
    required this.name,
    this.referencePhotoPath,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'reference_photo_path': referencePhotoPath,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Person.fromMap(Map<String, dynamic> map) {
    return Person(
      id: map['id'] as int,
      name: map['name'] as String,
      referencePhotoPath: map['reference_photo_path'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Person copyWith({
    int? id,
    String? name,
    String? referencePhotoPath,
  }) {
    return Person(
      id: id ?? this.id,
      name: name ?? this.name,
      referencePhotoPath: referencePhotoPath ?? this.referencePhotoPath,
      createdAt: createdAt,
    );
  }

  /// Genera user_id para el metadata JSON: "usr_nombre_id"
  String get userId {
    final safeName = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
    return 'usr_${safeName}_${id ?? 0}';
  }
}
