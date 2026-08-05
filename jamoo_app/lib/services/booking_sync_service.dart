import 'dart:async';
import 'dart:io';

import '../core/app_paths.dart';

class BookingSyncService {
  const BookingSyncService({
    this.projectRootPath,
    this.pollInterval = const Duration(seconds: 1),
    this.timeout = const Duration(minutes: 15),
  });

  final String? projectRootPath;
  final Duration pollInterval;
  final Duration timeout;

  Future<BookingSyncResult> run() async {
    if (!Platform.isWindows) {
      throw const BookingSyncException(
        'Booking.comの取得処理は現在Windows版のみ対応しています。',
      );
    }

    final paths = await _resolvePaths();

    await _confirmNodeIsAvailable();

    final previousSnapshot = await _readFileSnapshot(
      paths.reservationJson,
    );

    await _launchBookingPowerShell(
      bookingDirectory: paths.bookingBotDirectory,
      bookingScript: paths.bookingScript,
    );

    final updatedSnapshot = await _waitForJsonUpdate(
      jsonFile: paths.reservationJson,
      previousSnapshot: previousSnapshot,
    );

    return BookingSyncResult(
      jsonFilePath: paths.reservationJson.path,
      updatedAt: updatedSnapshot.modifiedAt,
    );
  }

  Future<AppPaths> _resolvePaths() async {
    try {
      final paths = await AppPaths.resolve(
        projectRootPath: projectRootPath,
      );

      if (!await paths.bookingScriptExists()) {
        throw BookingSyncException(
          'Booking.com取得ファイルが見つかりません。\n'
          '${paths.bookingScript.path}',
        );
      }

      await paths.ensureOutputDirectory();

      return paths;
    } on BookingSyncException {
      rethrow;
    } on AppPathsException catch (error) {
      throw BookingSyncException(
        'JamooManagerのファイル場所を確認できませんでした。\n'
        '${error.message}',
      );
    }
  }

  Future<void> _confirmNodeIsAvailable() async {
    try {
      final result = await Process.run(
        'where.exe',
        ['node'],
        runInShell: true,
      );

      if (result.exitCode != 0) {
        throw const BookingSyncException(
          'Node.jsが見つかりません。\n'
          'PowerShellで node --version が動くか確認してください。',
        );
      }
    } on BookingSyncException {
      rethrow;
    } on ProcessException catch (error) {
      throw BookingSyncException(
        'Node.jsの確認に失敗しました。\n${error.message}',
      );
    }
  }

  Future<void> _launchBookingPowerShell({
    required Directory bookingDirectory,
    required File bookingScript,
  }) async {
    final escapedDirectory = _escapePowerShellLiteral(
      bookingDirectory.path,
    );

    final scriptName = _escapePowerShellLiteral(
      bookingScript.path.split(Platform.pathSeparator).last,
    );

    final command = [
      '& {',
      "Set-Location -LiteralPath '$escapedDirectory';",
      "node '.\\$scriptName';",
      r'$exitCode = $LASTEXITCODE;',
      "Write-Host '';",
      r'if ($exitCode -eq 0) {',
      "Write-Host 'JamooManagerへの予約取込みが完了しました。';",
      '} else {',
      "Write-Host '予約取込み中にエラーが発生しました。';",
      '}',
      "Read-Host 'Enterを押すとこの画面を閉じます';",
      r'exit $exitCode;',
      '}',
    ].join(' ');

    try {
      await Process.start(
        'cmd.exe',
        [
          '/c',
          'start',
          '""',
          'powershell.exe',
          '-NoLogo',
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          command,
        ],
        runInShell: true,
        mode: ProcessStartMode.detached,
      );
    } on ProcessException catch (error) {
      throw BookingSyncException(
        'Booking.com取得用PowerShellを開けませんでした。\n'
        '${error.message}',
      );
    }
  }

  Future<_FileSnapshot> _waitForJsonUpdate({
    required File jsonFile,
    required _FileSnapshot? previousSnapshot,
  }) async {
    final stopwatch = Stopwatch()..start();

    while (stopwatch.elapsed < timeout) {
      await Future<void>.delayed(pollInterval);

      final currentSnapshot = await _readFileSnapshot(
        jsonFile,
      );

      if (currentSnapshot == null) {
        continue;
      }

      if (previousSnapshot == null ||
          currentSnapshot.content != previousSnapshot.content ||
          currentSnapshot.modifiedAt.isAfter(
            previousSnapshot.modifiedAt,
          )) {
        return currentSnapshot;
      }
    }

    throw BookingSyncException(
      '予約データの更新を確認できませんでした。\n'
      'Booking.com取得用PowerShellがまだ開いている場合は、'
      '操作を完了してください。\n'
      '待機時間：${timeout.inMinutes}分',
    );
  }

  Future<_FileSnapshot?> _readFileSnapshot(
    File file,
  ) async {
    if (!await file.exists()) {
      return null;
    }

    try {
      return _FileSnapshot(
        modifiedAt: await file.lastModified(),
        content: await file.readAsString(),
      );
    } on FileSystemException catch (error) {
      throw BookingSyncException(
        '予約JSONの状態を確認できませんでした。\n'
        '${error.message}\n'
        '${file.path}',
      );
    }
  }

  static String _escapePowerShellLiteral(
    String value,
  ) {
    return value.replaceAll("'", "''");
  }
}

class BookingSyncResult {
  const BookingSyncResult({
    required this.jsonFilePath,
    required this.updatedAt,
  });

  final String jsonFilePath;
  final DateTime updatedAt;
}

class BookingSyncException implements Exception {
  const BookingSyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _FileSnapshot {
  const _FileSnapshot({
    required this.modifiedAt,
    required this.content,
  });

  final DateTime modifiedAt;
  final String content;
}
