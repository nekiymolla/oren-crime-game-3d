import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'save_data.dart';

/// Где лежит сохранение. Файл в папке документов приложения; пишется
/// через временный файл и переименование, чтобы вылет посреди записи не
/// оставил битое сохранение.
class SaveStore {
  SaveStore({Future<Directory> Function()? directory}) : _directory = directory ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _directory;

  static const String fileName = 'crime_oren_save.json';

  Future<File> _file() async => File('${(await _directory()).path}/$fileName');

  Future<void> write(SaveData data) async {
    final file = await _file();
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(const JsonEncoder.withIndent('  ').convert(data.toJson()), flush: true);
    await temp.rename(file.path);
  }

  /// null — сохранения нет или оно не читается (битое, из будущей версии).
  Future<SaveData?> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) return null;
      return SaveData.fromJson(json);
    } on Object {
      return null;
    }
  }
}
