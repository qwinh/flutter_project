class Tag {
  final int? id;
  final String name;
  final String description;

  Tag({
    this.id,
    required this.name,
    this.description = '',
  });

  Tag copyWith({
    int? id,
    String? name,
    String? description,
  }) {
    return Tag(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'description': description,
    };
  }

  factory Tag.fromMap(Map<String, dynamic> map) {
    return Tag(
      id: map['id'] as int?,
      name: map['name'] as String,
      description: (map['description'] as String?) ?? '',
    );
  }
}
