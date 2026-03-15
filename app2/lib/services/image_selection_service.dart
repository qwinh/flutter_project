import 'db_helper.dart';
import 'package:sqflite/sqflite.dart';

class ImageSelectionService {
  final DbHelper _dbHelper = DbHelper.instance;

  Future<List<String>> getAll() async {
    final db = await _dbHelper.database;
    final maps = await db.query('images_selected');
    return maps.map((m) => m['image_uri'] as String).toList();
  }

  Future<Set<String>> getAllAsSet() async {
    final list = await getAll();
    return list.toSet();
  }

  Future<void> add(String imageUri) async {
    final db = await _dbHelper.database;
    await db.insert(
      'images_selected',
      {'image_uri': imageUri},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> addMultiple(List<String> imageUris) async {
    final db = await _dbHelper.database;
    final batch = db.batch();
    for (final uri in imageUris) {
      batch.insert(
        'images_selected',
        {'image_uri': uri},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> remove(String imageUri) async {
    final db = await _dbHelper.database;
    await db.delete(
      'images_selected',
      where: 'image_uri = ?',
      whereArgs: [imageUri],
    );
  }

  Future<void> removeMultiple(List<String> imageUris) async {
    final db = await _dbHelper.database;
    final batch = db.batch();
    for (final uri in imageUris) {
      batch.delete(
        'images_selected',
        where: 'image_uri = ?',
        whereArgs: [uri],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> clear() async {
    final db = await _dbHelper.database;
    await db.delete('images_selected');
  }

  Future<bool> isSelected(String imageUri) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'images_selected',
      where: 'image_uri = ?',
      whereArgs: [imageUri],
    );
    return maps.isNotEmpty;
  }
}
