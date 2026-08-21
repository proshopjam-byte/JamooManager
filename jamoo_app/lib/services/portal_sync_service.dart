import 'dart:convert';
import 'dart:io';

import '../core/app_paths.dart';
import 'database_service.dart';
import 'portal_reservation_email.dart';
import 'portal_reservation_import_service.dart';

class PortalSyncService {
  static const String _parserVersion = '1';

  const PortalSyncService({this.projectRootPath});

  final String? projectRootPath;

  Future<PortalSyncResult> run() async {
    if (!Platform.isWindows) {
      throw const PortalSyncException('楽天・じゃらんの取得は現在Windows版のみ対応しています。');
    }

    final paths = await _resolvePaths();
    await _confirmPythonIsAvailable();
    final process = await Process.run(
      'py',
      [paths.fetchScript.path],
      workingDirectory: paths.botDirectory.path,
      runInShell: true,
    );
    if (process.exitCode != 0) {
      final details = '${process.stdout}\n${process.stderr}'.trim();
      throw PortalSyncException(
        '楽天・じゃらんメールの取得に失敗しました。\n'
        '${details.isEmpty ? '終了コード: ${process.exitCode}' : details}',
      );
    }

    final payload = await _readPayload(paths.outputJson);
    final reservations = payload.reservations..sort(_compareBySentAt);
    final parserVersionChanged = await _prepareParserVersion();
    var inserted = 0;
    var updated = 0;
    var cancelled = 0;
    var skipped = 0;
    var failed = payload.errors.length;
    final errors = <String>[...payload.errors];
    const importer = PortalReservationImportService();

    for (final item in reservations) {
      final messageId = item['messageId']?.toString().trim();
      final subject = item['subject']?.toString().trim();
      if (messageId == null || messageId.isEmpty) {
        failed++;
        errors.add('${subject ?? '件名なし'}：メールIDがありません。');
        continue;
      }
      try {
        final email = PortalReservationEmail.fromJson(item);
        final result = await importer.importEmail(
          email,
          externalMessageId: messageId,
        );
        switch (result.action) {
          case PortalImportAction.inserted:
            inserted++;
          case PortalImportAction.updated:
            updated++;
          case PortalImportAction.cancelled:
            cancelled++;
          case PortalImportAction.skipped:
            skipped++;
        }
      } catch (error) {
        failed++;
        errors.add('${subject ?? '件名なし'}：$error');
      }
    }

    if (parserVersionChanged) {
      await _saveParserVersion();
    }
    await _saveLastSuccessfulSync();
    return PortalSyncResult(
      totalMessages: reservations.length + payload.errors.length,
      inserted: inserted,
      updated: updated,
      cancelled: cancelled,
      skipped: skipped,
      failed: failed,
      errors: List.unmodifiable(errors),
    );
  }

  Future<_PortalPaths> _resolvePaths() async {
    try {
      final appPaths = await AppPaths.resolve(projectRootPath: projectRootPath);
      final botDirectory = Directory(
        AppPaths.join(appPaths.projectRoot.path, const ['chillnn_mail_bot']),
      );
      final fetchScript = File(
        AppPaths.join(botDirectory.path, const ['fetch_portals.py']),
      );
      final outputJson = File(
        AppPaths.join(botDirectory.path, const [
          'output',
          'portal_emails_latest.json',
        ]),
      );
      if (!await fetchScript.exists()) {
        throw PortalSyncException(
          '楽天・じゃらん取得ファイルが見つかりません。\n${fetchScript.path}',
        );
      }
      await outputJson.parent.create(recursive: true);
      return _PortalPaths(
        botDirectory: botDirectory,
        fetchScript: fetchScript,
        outputJson: outputJson,
      );
    } on PortalSyncException {
      rethrow;
    } on AppPathsException catch (error) {
      throw PortalSyncException(
        'JamooManagerの場所を確認できませんでした。\n${error.message}',
      );
    }
  }

  Future<void> _confirmPythonIsAvailable() async {
    try {
      final result = await Process.run('where.exe', const [
        'py',
      ], runInShell: true);
      if (result.exitCode != 0) {
        throw const PortalSyncException(
          'Pythonが見つかりません。\nPowerShellで py --version を確認してください。',
        );
      }
    } on ProcessException catch (error) {
      throw PortalSyncException('Pythonの確認に失敗しました。\n${error.message}');
    }
  }

  Future<_PortalPayload> _readPayload(File file) async {
    if (!await file.exists()) {
      throw PortalSyncException('楽天・じゃらんのJSONが作成されませんでした。\n${file.path}');
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        throw const FormatException('JSONの最上位がオブジェクトではありません。');
      }
      final map = Map<String, dynamic>.from(decoded);
      final rawReservations = map['reservations'];
      if (rawReservations is! List) {
        throw const FormatException('reservations配列がありません。');
      }
      final reservations = rawReservations
          .map((value) => Map<String, dynamic>.from(value as Map))
          .toList();
      final errors = (map['errors'] as List? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false);
      return _PortalPayload(reservations: reservations, errors: errors);
    } on FileSystemException catch (error) {
      throw PortalSyncException('JSONを読み込めませんでした。\n${error.message}');
    } on Object catch (error) {
      throw PortalSyncException('JSONを解析できませんでした。\n$error');
    }
  }

  Future<bool> _prepareParserVersion() async {
    final db = await DatabaseService.instance.database;
    final current = await db.query(
      'app_metadata',
      columns: const ['value'],
      where: 'key = ?',
      whereArgs: const ['portal_email_parser_version'],
      limit: 1,
    );
    if (current.isNotEmpty &&
        current.first['value']?.toString() == _parserVersion) {
      return false;
    }
    await db.delete(
      'import_history',
      where: 'source = ?',
      whereArgs: const ['PORTAL_MAIL'],
    );
    return true;
  }

  Future<void> _saveParserVersion() async {
    final db = await DatabaseService.instance.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.rawInsert(
      'INSERT OR REPLACE INTO app_metadata '
      '(key, value, updated_at) VALUES (?, ?, ?)',
      ['portal_email_parser_version', _parserVersion, now],
    );
  }

  Future<void> _saveLastSuccessfulSync() async {
    final db = await DatabaseService.instance.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.rawInsert(
      'INSERT OR REPLACE INTO app_metadata '
      '(key, value, updated_at) VALUES (?, ?, ?)',
      ['last_reservation_import_at', now, now],
    );
  }

  static int _compareBySentAt(
    Map<String, dynamic> first,
    Map<String, dynamic> second,
  ) {
    final firstDate = DateTime.tryParse(first['sentAt']?.toString() ?? '');
    final secondDate = DateTime.tryParse(second['sentAt']?.toString() ?? '');
    if (firstDate == null && secondDate == null) return 0;
    if (firstDate == null) return -1;
    if (secondDate == null) return 1;
    return firstDate.compareTo(secondDate);
  }
}

class PortalSyncResult {
  const PortalSyncResult({
    required this.totalMessages,
    required this.inserted,
    required this.updated,
    required this.cancelled,
    required this.skipped,
    required this.failed,
    required this.errors,
  });

  final int totalMessages;
  final int inserted;
  final int updated;
  final int cancelled;
  final int skipped;
  final int failed;
  final List<String> errors;

  String get summary {
    final values = <String>[
      '対象メール：$totalMessages件',
      '新規登録：$inserted件',
      '更新：$updated件',
      'キャンセル反映：$cancelled件',
      '取込み済み：$skipped件',
    ];
    if (failed > 0) values.add('解析失敗：$failed件');
    return values.join('\n');
  }

  String? get errorDetails =>
      errors.isEmpty ? null : errors.take(10).join('\n');
}

class PortalSyncException implements Exception {
  const PortalSyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _PortalPaths {
  const _PortalPaths({
    required this.botDirectory,
    required this.fetchScript,
    required this.outputJson,
  });

  final Directory botDirectory;
  final File fetchScript;
  final File outputJson;
}

class _PortalPayload {
  const _PortalPayload({required this.reservations, required this.errors});

  final List<Map<String, dynamic>> reservations;
  final List<String> errors;
}
