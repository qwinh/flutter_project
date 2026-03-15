class Album {
  final int? id;
  final String name;
  final String description;
  final bool favorite;
  final DateTime dateCreated;
  final DateTime dateLatestModify;

  Album({
    this.id,
    required this.name,
    this.description = '',
    this.favorite = false,
    required this.dateCreated,
    required this.dateLatestModify,
  });

  Album copyWith({
    int? id,
    String? name,
    String? description,
    bool? favorite,
    DateTime? dateCreated,
    DateTime? dateLatestModify,
  }) {
    return Album(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      favorite: favorite ?? this.favorite,
      dateCreated: dateCreated ?? this.dateCreated,
      dateLatestModify: dateLatestModify ?? this.dateLatestModify,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'description': description,
      'favorite': favorite ? 1 : 0,
      'date_created': dateCreated.toIso8601String(),
      'date_latest_modify': dateLatestModify.toIso8601String(),
    };
  }

  factory Album.fromMap(Map<String, dynamic> map) {
    return Album(
      id: map['id'] as int?,
      name: map['name'] as String,
      description: (map['description'] as String?) ?? '',
      favorite: (map['favorite'] as int?) == 1,
      dateCreated: DateTime.parse(map['date_created'] as String),
      dateLatestModify: DateTime.parse(map['date_latest_modify'] as String),
    );
  }
}
