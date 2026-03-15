import 'package:sqflite/sqflite.dart';
import '../models/album.dart';
import 'db_helper.dart';

class AlbumService {
  final DbHelper _dbHelper = DbHelper.instance;

  Future<List<Album>> getAll() async {
    final db = await _dbHelper.database;
    final maps = await db.query('albums', orderBy: 'date_latest_modify DESC');
    return maps.map((m) => Album.fromMap(m)).toList();
  }

  Future<Album?> getById(int id) async {
    final db = await _dbHelper.database;
    final maps = await db.query('albums', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Album.fromMap(maps.first);
  }

  Future<int> insert(Album album) async {
    final db = await _dbHelper.database;
    return await db.insert('albums', album.toMap());
  }

  Future<void> update(Album album) async {
    final db = await _dbHelper.database;
    await db.update(
      'albums',
      album.toMap(),
      where: 'id = ?',
      whereArgs: [album.id],
    );
  }

  Future<void> delete(int id) async {
    final db = await _dbHelper.database;
    await db.delete('albums', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> toggleFavorite(int id, bool favorite) async {
    final db = await _dbHelper.database;
    await db.update(
      'albums',
      {
        'favorite': favorite ? 1 : 0,
        'date_latest_modify': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // --- Album-Image relations ---

  Future<void> addImage(int albumId, String imageUri) async {
    final db = await _dbHelper.database;
    await db.insert(
      'albums_images',
      {'album_id': albumId, 'image_uri': imageUri},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> addImages(int albumId, List<String> imageUris) async {
    final db = await _dbHelper.database;
    final batch = db.batch();
    for (final uri in imageUris) {
      batch.insert(
        'albums_images',
        {'album_id': albumId, 'image_uri': uri},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> removeImage(int albumId, String imageUri) async {
    final db = await _dbHelper.database;
    await db.delete(
      'albums_images',
      where: 'album_id = ? AND image_uri = ?',
      whereArgs: [albumId, imageUri],
    );
  }

  Future<List<String>> getAlbumImageUris(int albumId) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'albums_images',
      where: 'album_id = ?',
      whereArgs: [albumId],
    );
    return maps.map((m) => m['image_uri'] as String).toList();
  }

  Future<int> getImageCount(int albumId) async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM albums_images WHERE album_id = ?',
      [albumId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<Album>> getAlbumsByTag(int tagId) async {
    final db = await _dbHelper.database;
    final maps = await db.rawQuery('''
      SELECT a.* FROM albums a
      INNER JOIN tags_albums ta ON a.id = ta.album_id
      WHERE ta.tag_id = ?
      ORDER BY a.date_latest_modify DESC
    ''', [tagId]);
    return maps.map((m) => Album.fromMap(m)).toList();
  }

  Future<String?> getAlbumCoverUri(int albumId) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'albums_images',
      where: 'album_id = ?',
      whereArgs: [albumId],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return maps.first['image_uri'] as String;
  }
}
