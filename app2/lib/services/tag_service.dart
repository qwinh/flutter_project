import 'package:sqflite/sqflite.dart';
import '../models/tag.dart';
import 'db_helper.dart';

class TagService {
  final DbHelper _dbHelper = DbHelper.instance;

  Future<List<Tag>> getAll() async {
    final db = await _dbHelper.database;
    final maps = await db.query('tags', orderBy: 'name ASC');
    return maps.map((m) => Tag.fromMap(m)).toList();
  }

  Future<Tag?> getById(int id) async {
    final db = await _dbHelper.database;
    final maps = await db.query('tags', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Tag.fromMap(maps.first);
  }

  Future<int> insert(Tag tag) async {
    final db = await _dbHelper.database;
    return await db.insert('tags', tag.toMap());
  }

  Future<void> update(Tag tag) async {
    final db = await _dbHelper.database;
    await db.update('tags', tag.toMap(), where: 'id = ?', whereArgs: [tag.id]);
  }

  Future<void> delete(int id) async {
    final db = await _dbHelper.database;
    await db.delete('tags', where: 'id = ?', whereArgs: [id]);
  }

  // --- Tag-Album relations ---

  Future<List<Tag>> getTagsForAlbum(int albumId) async {
    final db = await _dbHelper.database;
    final maps = await db.rawQuery('''
      SELECT t.* FROM tags t
      INNER JOIN tags_albums ta ON t.id = ta.tag_id
      WHERE ta.album_id = ?
      ORDER BY t.name ASC
    ''', [albumId]);
    return maps.map((m) => Tag.fromMap(m)).toList();
  }

  Future<void> setTagsForAlbum(int albumId, List<int> tagIds) async {
    final db = await _dbHelper.database;
    await db.delete('tags_albums', where: 'album_id = ?', whereArgs: [albumId]);
    final batch = db.batch();
    for (final tagId in tagIds) {
      batch.insert(
        'tags_albums',
        {'album_id': albumId, 'tag_id': tagId},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> addTagToAlbum(int albumId, int tagId) async {
    final db = await _dbHelper.database;
    await db.insert(
      'tags_albums',
      {'album_id': albumId, 'tag_id': tagId},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> removeTagFromAlbum(int albumId, int tagId) async {
    final db = await _dbHelper.database;
    await db.delete(
      'tags_albums',
      where: 'album_id = ? AND tag_id = ?',
      whereArgs: [albumId, tagId],
    );
  }
}
