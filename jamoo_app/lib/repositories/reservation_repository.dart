import 'dart:convert';
import 'dart:io';

import '../core/app_paths.dart';
import '../models/reservation_data.dart';

class ReservationRepository {
  const ReservationRepository({this.jsonFilePath, this.projectRootPath});

  final String? jsonFilePath;
  final String? projectRootPath;

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
      throw ReservationRepositoryException('予約JSONの形式が正しくありません。\n$error');
    } on FileSystemException catch (error) {
      throw ReservationRepositoryException(
        '予約JSONを読み込めませんでした。\n'
        '${error.message}\n'
        '${file.path}',
      );
    } catch (error) {
      throw ReservationRepositoryException(
        '予約データの読み込み中に'
        '予期しないエラーが発生しました。\n$error',
      );
    }
  }

  Future<bool> exists() async {
    try {
      final file = await _resolveJsonFile();
      return file.exists();
    } on AppPathsException {
      return false;
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
      if (!await file.exists()) {
        return null;
      }

      return await file.lastModified();
    } on FileSystemException {
      return null;
    }
  }

  Future<File> _resolveJsonFile() async {
    try {
      final paths = await AppPaths.resolve(
        projectRootPath: projectRootPath,
        reservationJsonPath: jsonFilePath,
      );

      final file = paths.reservationJson;

      if (await file.exists()) {
        return file;
      }

      throw ReservationRepositoryException(
        '予約JSONが見つかりません。\n'
        '先にBooking.comから本日のチェックインを'
        '取得してください。\n\n'
        '${file.path}',
      );
    } on ReservationRepositoryException {
      rethrow;
    } on AppPathsException catch (error) {
      throw ReservationRepositoryException(
        '予約JSONの場所を確認できませんでした。\n'
        '${error.message}',
      );
    }
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
