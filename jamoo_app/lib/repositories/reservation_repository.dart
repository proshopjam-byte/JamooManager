import 'dart:convert';
import 'dart:io';

import '../models/reservation_data.dart';

class ReservationRepository {
  const ReservationRepository({
    this.jsonFilePath,
  });

  final String? jsonFilePath;

  static const String jsonFileName = 'reservations_latest.json';

  Future<ReservationData> load() async {
    final file = await _resolveJsonFile();

    try {
      final bytes = await file.readAsBytes();
      final text = _removeUtf8Bom(utf8.decode(bytes));
      final decoded = jsonDecode(text);

      if (decoded is! Map<String, dynamic>) {
        throw const ReservationRepositoryException(
          '予約JSONの一番外側がオブジェクト形式ではありません。',
        );
      }

      return ReservationData.fromJson(decoded);
    } on ReservationRepositoryException {
      rethrow;
    } on FormatException catch (error) {
      throw ReservationRepositoryException(
        '予約JSONの形式が正しくありません。\n$error',
      );
    } on FileSystemException catch (error) {
      throw ReservationRepositoryException(
        '予約JSONを読み込めませんでした。\n'
        '${error.message}\n'
        '${file.path}',
      );
    } catch (error) {
      throw ReservationRepositoryException(
        '予約データの読み込み中に予期しないエラーが発生しました。\n$error',
      );
    }
  }

  Future<bool> exists() async {
    try {
      final file = await _resolveJsonFile();
      return file.exists();
    } on ReservationRepositoryException {
      return false;
    }
  }

  Future<String> resolvedFilePath() async {
    final file = await _resolveJsonFile();
    return file.path;
  }

  Future<DateTime?> lastModified() async {
    final file = await _resolveJsonFile();

    try {
      return await file.lastModified();
    } on FileSystemException {
      return null;
    }
  }

  Future<File> _resolveJsonFile() async {
    final explicitPath = jsonFilePath?.trim();

    if (explicitPath != null && explicitPath.isNotEmpty) {
      final explicitFile = File(explicitPath);

      if (await explicitFile.exists()) {
        return explicitFile;
      }

      throw ReservationRepositoryException(
        '指定された予約JSONが見つかりません。\n$explicitPath',
      );
    }

    final environmentPath =
        Platform.environment['JAMOO_RESERVATIONS_JSON']?.trim();

    if (environmentPath != null && environmentPath.isNotEmpty) {
      final environmentFile = File(environmentPath);

      if (await environmentFile.exists()) {
        return environmentFile;
      }
    }

    final searchedPaths = <String>[];
    final startingDirectories = <Directory>[
      Directory.current,
      File(Platform.resolvedExecutable).parent,
    ];

    for (final startingDirectory in startingDirectories) {
      final foundFile = await _searchUpward(
        startingDirectory,
        searchedPaths,
      );

      if (foundFile != null) {
        return foundFile;
      }
    }

    throw ReservationRepositoryException(
      '予約JSONが見つかりません。\n'
      '先に booking_bot で予約取得を実行してください。\n\n'
      '検索した場所：\n${searchedPaths.join('\n')}',
    );
  }

  Future<File?> _searchUpward(
    Directory startingDirectory,
    List<String> searchedPaths,
  ) async {
    var current = startingDirectory.absolute;
    final visitedDirectories = <String>{};

    while (visitedDirectories.add(current.path)) {
      final candidate = File(
        _joinPath(
          current.path,
          [
            'booking_bot',
            'output',
            jsonFileName,
          ],
        ),
      );

      if (!searchedPaths.contains(candidate.path)) {
        searchedPaths.add(candidate.path);
      }

      if (await candidate.exists()) {
        return candidate;
      }

      final parent = current.parent;

      if (parent.path == current.path) {
        break;
      }

      current = parent;
    }

    return null;
  }

  static String _joinPath(
    String basePath,
    List<String> parts,
  ) {
    final separator = Platform.pathSeparator;
    final cleanedBase = basePath.endsWith(separator)
        ? basePath.substring(0, basePath.length - 1)
        : basePath;

    return [
      cleanedBase,
      ...parts,
    ].join(separator);
  }

  static String _removeUtf8Bom(String value) {
    if (value.isNotEmpty && value.codeUnitAt(0) == 0xFEFF) {
      return value.substring(1);
    }

    return value;
  }
}

class ReservationRepositoryException implements Exception {
  const ReservationRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}
