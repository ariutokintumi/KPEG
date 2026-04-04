class Person {
  final int? id;
  final String name;
  final String? referencePhotoPath;
  final int selfieCount;
  final DateTime createdAt;

  Person({
    this.id,
    required this.name,
    this.referencePhotoPath,
    this.selfieCount = 0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Unknown person — always available in the face picker
  static final Person unknown = Person(
    id: -1,
    name: 'Unknown',
    selfieCount: 0,
  );

  Map<String, dynamic> toMap() {
    return {
      if (id != null && id! > 0) 'id': id,
      'name': name,
      'reference_photo_path': referencePhotoPath,
      'selfie_count': selfieCount,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Person.fromMap(Map<String, dynamic> map) {
    return Person(
      id: map['id'] as int,
      name: map['name'] as String,
      referencePhotoPath: map['reference_photo_path'] as String?,
      selfieCount: (map['selfie_count'] as int?) ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Person copyWith({
    int? id,
    String? name,
    String? referencePhotoPath,
    int? selfieCount,
  }) {
    return Person(
      id: id ?? this.id,
      name: name ?? this.name,
      referencePhotoPath: referencePhotoPath ?? this.referencePhotoPath,
      selfieCount: selfieCount ?? this.selfieCount,
      createdAt: createdAt,
    );
  }

  bool get isUnknown => id == -1;

  /// user_id for metadata JSON
  String get userId {
    if (isUnknown) return 'unknown';
    final safeName = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
    return 'usr_${safeName}_${id ?? 0}';
  }
}
