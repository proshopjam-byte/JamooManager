import 'dart:convert';
import 'dart:io';

import '../models/app_settings.dart';

class SettingsRepository {
  const SettingsRepository({this.settingsFilePath});

  final String? settingsFilePath;

  static const String _applicationFolderName = 'JamooManager';
  static const String _settingsFileName = 'app_settings.json';

  Future<AppSettings> load() async {
    final file = await _resolveSettingsFile();

    if (!await file.exists()) {
      await save(AppSettings.defaults);
      return AppSettings.defaults;
    }

    try {
      final bytes = await file.readAsBytes();
      final text = _removeUtf8Bom(utf8.decode(bytes));

      final decoded = jsonDecode(text);

      if (decoded is! Map<String, dynamic>) {
        throw const SettingsRepositoryException('設定JSONの一番外側がオブジェクト形式ではありません。');
      }

      return AppSettings.fromJson(decoded);
    } on SettingsRepositoryException {
      rethrow;
    } on FormatException catch (error) {
      throw SettingsRepositoryException('設定JSONの形式が正しくありません。\n$error');
    } on FileSystemException catch (error) {
      throw SettingsRepositoryException(
        '設定ファイルを読み込めませんでした。\n'
        '${error.message}\n'
        '${file.path}',
      );
    } catch (error) {
      throw SettingsRepositoryException('設定の読み込み中に予期しないエラーが発生しました。\n$error');
    }
  }

  Future<void> save(AppSettings settings) async {
    final file = await _resolveSettingsFile();

    try {
      await file.parent.create(recursive: true);

      final temporaryFile = File('${file.path}.tmp');

      final json = const JsonEncoder.withIndent(
        '  ',
      ).convert(settings.toJson());

      await temporaryFile.writeAsString('$json\n', encoding: utf8, flush: true);

      if (await file.exists()) {
        await file.delete();
      }

      await temporaryFile.rename(file.path);
    } on FileSystemException catch (error) {
      throw SettingsRepositoryException(
        '設定ファイルを保存できませんでした。\n'
        '${error.message}\n'
        '${file.path}',
      );
    } catch (error) {
      throw SettingsRepositoryException('設定の保存中に予期しないエラーが発生しました。\n$error');
    }
  }

  Future<AppSettings> reset() async {
    await save(AppSettings.defaults);
    return AppSettings.defaults;
  }

  Future<bool> exists() async {
    final file = await _resolveSettingsFile();
    return file.exists();
  }

  Future<String> resolvedFilePath() async {
    final file = await _resolveSettingsFile();
    return file.path;
  }

  Future<File> _resolveSettingsFile() async {
    final explicitPath = settingsFilePath?.trim();

    if (explicitPath != null && explicitPath.isNotEmpty) {
      return File(explicitPath);
    }

    final environmentPath = Platform.environment['JAMOO_SETTINGS_JSON']?.trim();

    if (environmentPath != null && environmentPath.isNotEmpty) {
      return File(environmentPath);
    }

    if (Platform.isWindows) {
      final appDataPath = Platform.environment['APPDATA']?.trim();

      if (appDataPath != null && appDataPath.isNotEmpty) {
        return File(
          _joinPath(appDataPath, [_applicationFolderName, _settingsFileName]),
        );
      }
    }

    final homePath = Platform.environment['HOME']?.trim();

    if (homePath != null && homePath.isNotEmpty) {
      return File(_joinPath(homePath, ['.jamoo_manager', _settingsFileName]));
    }

    return File(
      _joinPath(Directory.current.path, ['config', _settingsFileName]),
    );
  }

  static String _removeUtf8Bom(String value) {
    if (value.isNotEmpty && value.codeUnitAt(0) == 0xFEFF) {
      return value.substring(1);
    }

    return value;
  }

  static String _joinPath(String basePath, List<String> parts) {
    final separator = Platform.pathSeparator;

    final normalizedBase = basePath.endsWith(separator)
        ? basePath.substring(0, basePath.length - 1)
        : basePath;

    return [normalizedBase, ...parts].join(separator);
  }
}

class SettingsRepositoryException implements Exception {
  const SettingsRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}
