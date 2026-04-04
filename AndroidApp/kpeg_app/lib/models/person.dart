class Person {
  final int? id;
  final String visibleUserId; // "usr_maria_01" — stored on server
  final String name;
  final int selfieCount;
  final String? thumbnailPath; // Local face crop thumbnail
  final DateTime createdAt;

  Person({
    this.id,
    required this.visibleUserId,
    required this.name,
    this.selfieCount = 0,
    this.thumbnailPath,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Unknown person — always available in the face picker
  static final Person unknown = Person(
    id: -1,
    visibleUserId: 'unknown',
    name: 'Unknown',
  );

  /// Generate a user_id from a name (for registration)
  static String generateUserId(String name) {
    final safeName = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
    final ts = DateTime.now().millisecondsSinceEpoch % 100000;
    return 'usr_${safeName}_$ts';
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null && id! > 0) 'id': id,
      'user_id': visibleUserId,
      'name': name,
      'selfie_count': selfieCount,
      'thumbnail_path': thumbnailPath,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Person.fromMap(Map<String, dynamic> map) {
    return Person(
      id: map['id'] as int,
      visibleUserId: map['user_id'] as String,
      name: map['name'] as String,
      selfieCount: (map['selfie_count'] as int?) ?? 0,
      thumbnailPath: map['thumbnail_path'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  /// Create from server API response
  factory Person.fromApiJson(Map<String, dynamic> json) {
    return Person(
      visibleUserId: json['user_id'] as String,
      name: json['name'] as String,
      selfieCount: (json['photo_count'] as int?) ?? 0,
    );
  }

  Person copyWith({int? id, String? name, int? selfieCount, String? thumbnailPath}) {
    return Person(
      id: id ?? this.id,
      visibleUserId: visibleUserId,
      name: name ?? this.name,
      selfieCount: selfieCount ?? this.selfieCount,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      createdAt: createdAt,
    );
  }

  bool get isUnknown => visibleUserId == 'unknown';
}
