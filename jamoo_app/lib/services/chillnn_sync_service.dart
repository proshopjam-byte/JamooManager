import 'dart:convert';
import 'dart:io';

import '../core/app_paths.dart';
import 'chillnn_email_parser.dart';
import 'chillnn_reservation_import_service.dart';
import 'database_service.dart';

class ChillnnSyncService {
  static const String _parserVersion = '2';

  const ChillnnSyncService({this.projectRootPath});

  final String? projectRootPath;

  Future<ChillnnSyncResult> run() async {
    if (!Platform.isWindows) {
      throw const ChillnnSyncException('CHILLNNの取得処理は現在Windows版のみ対応しています。');
    }

    final paths = await _resolvePaths();
    await _confirmPythonIsAvailable();

    final processResult = await _runFetchScript(paths);

    if (processResult.exitCode != 0) {
      final details = '${processResult.stdout}\n${processResult.stderr}'.trim();

      throw ChillnnSyncException(
        'CHILLNNメールの取得に失敗しました。\n'
        '${details.isEmpty ? 'Python処理の終了コード: ${processResult.exitCode}' : details}',
      );
    }

    final messages = await _readMessages(paths.emailJson);
    messages.sort(_compareBySentAt);

    final parserVersionChanged = await _prepareParserVersion();

    var inserted = 0;
    var updated = 0;
    var cancelled = 0;
    var skipped = 0;
    var failed = 0;
    final errors = <String>[];

    const parser = ChillnnEmailParser();
    const importer = ChillnnReservationImportService();

    for (final message in messages) {
      final messageId = message['messageId']?.toString().trim();
      final subject = message['subject']?.toString();
      final body = message['body']?.toString();

      if (messageId == null || messageId.isEmpty) {
        failed++;
        errors.add('${subject ?? '件名なし'}：メールIDがありません。');
        continue;
      }

      if (body == null || body.trim().isEmpty) {
        failed++;
        errors.add('${subject ?? '件名なし'}：本文がありません。');
        continue;
      }

      try {
        final email = parser.parse(subject: subject, body: body);
        final result = await importer.importEmail(
          email,
          externalMessageId: messageId,
        );

        switch (result.action) {
          case ChillnnImportAction.inserted:
            inserted++;
          case ChillnnImportAction.updated:
            updated++;
          case ChillnnImportAction.cancelled:
            cancelled++;
          case ChillnnImportAction.skipped:
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

    return ChillnnSyncResult(
      totalMessages: messages.length,
      inserted: inserted,
      updated: updated,
      cancelled: cancelled,
      skipped: skipped,
      failed: failed,
      errors: List.unmodifiable(errors),
    );
  }

  Future<bool> _prepareParserVersion() async {
    final db = await DatabaseService.instance.database;
    final current = await db.query(
      'app_metadata',
      columns: const ['value'],
      where: 'key = ?',
      whereArgs: const ['chillnn_email_parser_version'],
      limit: 1,
    );

    if (current.isNotEmpty &&
        current.first['value']?.toString() == _parserVersion) {
      return false;
    }

    await db.delete(
      'import_history',
      where: 'source = ?',
      whereArgs: const ['CHILLNN'],
    );

    return true;
  }

  Future<void> _saveParserVersion() async {
    final db = await DatabaseService.instance.database;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.rawInsert(
      'INSERT OR REPLACE INTO app_metadata '
      '(key, value, updated_at) VALUES (?, ?, ?)',
      ['chillnn_email_parser_version', _parserVersion, now],
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

  Future<_ChillnnPaths> _resolvePaths() async {
    try {
      final appPaths = await AppPaths.resolve(projectRootPath: projectRootPath);

      final botDirectory = Directory(
        AppPaths.join(appPaths.projectRoot.path, const ['chillnn_mail_bot']),
      );

      final fetchScript = File(
        AppPaths.join(botDirectory.path, const ['fetch_chillnn.py']),
      );

      final emailJson = File(
        AppPaths.join(botDirectory.path, const [
          'output',
          'chillnn_emails_latest.json',
        ]),
      );

      if (!await fetchScript.exists()) {
        throw ChillnnSyncException(
          'CHILLNN取得ファイルが見つかりません。\n${fetchScript.path}',
        );
      }

      await emailJson.parent.create(recursive: true);

      return _ChillnnPaths(
        botDirectory: botDirectory,
        fetchScript: fetchScript,
        emailJson: emailJson,
      );
    } on ChillnnSyncException {
      rethrow;
    } on AppPathsException catch (error) {
      throw ChillnnSyncException(
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
        throw const ChillnnSyncException(
          'Pythonが見つかりません。\n'
          'PowerShellで py --version が動くか確認してください。',
        );
      }
    } on ChillnnSyncException {
      rethrow;
    } on ProcessException catch (error) {
      throw ChillnnSyncException('Pythonの確認に失敗しました。\n${error.message}');
    }
  }

  Future<ProcessResult> _runFetchScript(_ChillnnPaths paths) async {
    try {
      return await Process.run(
        'py',
        [paths.fetchScript.path],
        workingDirectory: paths.botDirectory.path,
        runInShell: true,
      );
    } on ProcessException catch (error) {
      throw ChillnnSyncException('CHILLNN取得処理を開始できませんでした。\n${error.message}');
    }
  }

  Future<List<Map<String, dynamic>>> _readMessages(File jsonFile) async {
    if (!await jsonFile.exists()) {
      throw ChillnnSyncException(
        'CHILLNNメールのJSONが作成されませんでした。\n${jsonFile.path}',
      );
    }

    try {
      final decoded = jsonDecode(await jsonFile.readAsString());

      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('JSONの最上位がオブジェクトではありません。');
      }

      final rawMessages = decoded['messages'];

      if (rawMessages is! List) {
        throw const FormatException('messagesの配列がありません。');
      }

      return rawMessages
          .map((value) => Map<String, dynamic>.from(value as Map))
          .toList(growable: false);
    } on FileSystemException catch (error) {
      throw ChillnnSyncException(
        'CHILLNNメールのJSONを読み込めませんでした。\n${error.message}',
      );
    } on FormatException catch (error) {
      throw ChillnnSyncException(
        'CHILLNNメールのJSON形式が正しくありません。\n${error.message}',
      );
    } on TypeError catch (error) {
      throw ChillnnSyncException('CHILLNNメールのJSON内容を解析できませんでした。\n$error');
    }
  }

  static int _compareBySentAt(
    Map<String, dynamic> first,
    Map<String, dynamic> second,
  ) {
    final firstDate = DateTime.tryParse(first['sentAt']?.toString() ?? '');
    final secondDate = DateTime.tryParse(second['sentAt']?.toString() ?? '');

    if (firstDate == null && secondDate == null) {
      return 0;
    }
    if (firstDate == null) {
      return -1;
    }
    if (secondDate == null) {
      return 1;
    }

    return firstDate.compareTo(secondDate);
  }
}

class ChillnnSyncResult {
  const ChillnnSyncResult({
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
    final lines = <String>[
      '対象メール：$totalMessages件',
      '新規登録：$inserted件',
      '更新：$updated件',
      'キャンセル反映：$cancelled件',
      '取込み済み：$skipped件',
    ];

    if (failed > 0) {
      lines.add('解析失敗：$failed件');
    }

    return lines.join('\n');
  }

  String? get errorDetails {
    if (errors.isEmpty) {
      return null;
    }

    return errors.take(10).join('\n');
  }
}

class ChillnnSyncException implements Exception {
  const ChillnnSyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _ChillnnPaths {
  const _ChillnnPaths({
    required this.botDirectory,
    required this.fetchScript,
    required this.emailJson,
  });

  final Directory botDirectory;
  final File fetchScript;
  final File emailJson;
}
