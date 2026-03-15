// lib/models/models.dart
// Central data models for PhotoVault.

class AlbumModel {
  final int? id;
  final String name;
  final String description;
  final bool isFavorite;
  final DateTime dateCreated;
  final DateTime dateLatestModify;

  AlbumModel({
    this.id,
    required this.name,
    this.description = '',
    this.isFavorite = false,
    DateTime? dateCreated,
    DateTime? dateLatestModify,
  })  : dateCreated = dateCreated ?? DateTime.now(),
        dateLatestModify = dateLatestModify ?? DateTime.now();

  AlbumModel copyWith({
    int? id,
    String? name,
    String? description,
    bool? isFavorite,
    DateTime? dateCreated,
    DateTime? dateLatestModify,
  }) {
    return AlbumModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      isFavorite: isFavorite ?? this.isFavorite,
      dateCreated: dateCreated ?? this.dateCreated,
      dateLatestModify: dateLatestModify ?? this.dateLatestModify,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'description': description,
        'is_favorite': isFavorite ? 1 : 0,
        'date_created': dateCreated.toIso8601String(),
        'date_latest_modify': dateLatestModify.toIso8601String(),
      };

  factory AlbumModel.fromMap(Map<String, dynamic> m) => AlbumModel(
        id: m['id'] as int?,
        name: m['name'] as String,
        description: m['description'] as String? ?? '',
        isFavorite: (m['is_favorite'] as int? ?? 0) == 1,
        dateCreated: m['date_created'] != null
            ? DateTime.parse(m['date_created'] as String)
            : DateTime.now(),
        dateLatestModify: m['date_latest_modify'] != null
            ? DateTime.parse(m['date_latest_modify'] as String)
            : DateTime.now(),
      );
}

class TagModel {
  final int? id;
  final String name;
  final String description;

  const TagModel({this.id, required this.name, this.description = ''});

  TagModel copyWith({int? id, String? name, String? description}) => TagModel(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'description': description,
      };

  factory TagModel.fromMap(Map<String, dynamic> m) => TagModel(
        id: m['id'] as int?,
        name: m['name'] as String,
        description: m['description'] as String? ?? '',
      );
}

/// Represents a device image (from photo_manager) stored/linked in the DB.
/// The [assetId] is the AssetEntity.id from photo_manager.
class ImageRecord {
  final String assetId;
  const ImageRecord({required this.assetId});
}
