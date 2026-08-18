import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/facility_settings.dart';

class FacilitySettingsRepository {
  const FacilitySettingsRepository();

  static const _fileName = 'facility_settings.json';

  Future<FacilitySettings> load() async {
    final file = await _settingsFile();
    final backup = File('${file.path}.bak');
    final sourceFile = await file.exists()
        ? file
        : await backup.exists()
        ? backup
        : null;
    if (sourceFile == null) {
      return FacilitySettings.defaults;
    }

    try {
      return await _read(sourceFile);
    } catch (error) {
      if (sourceFile.path == file.path && await backup.exists()) {
        try {
          return await _read(backup);
        } catch (_) {
          // 主ファイルとバックアップの両方が読めない場合は下で通知する。
        }
      }
      throw FacilitySettingsException('施設・客室設定を読み込めませんでした。\n$error');
    }
  }

  Future<FacilitySettings> _read(File file) async {
    final source = await file.readAsString();
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('設定ファイルの形式が正しくありません。');
    }
    return FacilitySettings.fromJson(
      decoded.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  Future<void> save(FacilitySettings settings) async {
    final file = await _settingsFile();
    final temporary = File('${file.path}.tmp');
    final backup = File('${file.path}.bak');
    try {
      await file.parent.create(recursive: true);
      final source = const JsonEncoder.withIndent(
        '  ',
      ).convert(settings.toJson());
      await temporary.writeAsString(source, flush: true);
      if (await backup.exists()) {
        await backup.delete();
      }
      if (await file.exists()) {
        await file.rename(backup.path);
      }
      await temporary.rename(file.path);
    } catch (error) {
      if (await temporary.exists()) {
        await temporary.delete();
      }
      if (!await file.exists() && await backup.exists()) {
        await backup.rename(file.path);
      }
      throw FacilitySettingsException('施設・客室設定を保存できませんでした。\n$error');
    }
  }

  Future<File> _settingsFile() async {
    final supportDirectory = await getApplicationSupportDirectory();
    return File(
      p.join(supportDirectory.path, 'JamooManager', 'settings', _fileName),
    );
  }
}

class FacilitySettingsException implements Exception {
  const FacilitySettingsException(this.message);

  final String message;

  @override
  String toString() => message;
}
