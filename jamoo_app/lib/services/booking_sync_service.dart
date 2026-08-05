import 'dart:async';
import 'dart:io';

class BookingSyncService {
  const BookingSyncService({
    this.projectRootPath,
    this.pollInterval = const Duration(seconds: 1),
    this.timeout = const Duration(minutes: 15),
  });

  final String? projectRootPath;
  final Duration pollInterval;
  final Duration timeout;

  static const String _bookingScriptName = 'booking.js';
  static const String _reservationJsonName =
      'reservations_latest.json';

  Future<BookingSyncResult> run() async {
    if (!Platform.isWindows) {
      throw const BookingSyncException(
        'Booking.comの取得処理は現在Windows版のみ対応しています。',
      );
    }

    final rootDirectory = await _resolveProjectRoot();
    final bookingDirectory = Directory(
      _joinPath(
        rootDirectory.path,
        ['booking_bot'],
      ),
    );

    final bookingScript = File(
      _joinPath(
        bookingDirectory.path,
        [_bookingScriptName],
      ),
    );

    if (!await bookingScript.exists()) {
      throw BookingSyncException(
        'Booking.com取得ファイルが見つかりません。\n'
        '${bookingScript.path}',
      );
    }

    await _confirmNodeIsAvailable();

    final jsonFile = File(
      _joinPath(
        bookingDirectory.path,
        [
          'output',
          _reservationJsonName,
        ],
      ),
    );

    final previousSnapshot =
        await _readFileSnapshot(jsonFile);

    await _launchBookingPowerShell(
      bookingDirectory: bookingDirectory,
    );

    final updatedSnapshot = await _waitForJsonUpdate(
      jsonFile: jsonFile,
      previousSnapshot: previousSnapshot,
    );

    return BookingSyncResult(
      jsonFilePath: jsonFile.path,
      updatedAt: updatedSnapshot.modifiedAt,
    );
  }

  Future<Directory> _resolveProjectRoot() async {
    final explicitPath = projectRootPath?.trim();

    if (explicitPath != null && explicitPath.isNotEmpty) {
      final directory = Directory(explicitPath);

      if (await _containsBookingScript(directory)) {
        return directory.absolute;
      }

      throw BookingSyncException(
        '指定されたJamooManagerフォルダ内に'
        'booking_bot\\booking.jsが見つかりません。\n'
        '$explicitPath',
      );
    }

    final startingDirectories = <Directory>[
      Directory.current,
      File(Platform.resolvedExecutable).parent,
    ];

    final visited = <String>{};

    for (final startingDirectory in startingDirectories) {
      var current = startingDirectory.absolute;

      while (visited.add(current.path)) {
        if (await _containsBookingScript(current)) {
          return current;
        }

        final parent = current.parent;

        if (parent.path == current.path) {
          break;
        }

        current = parent;
      }
    }

    throw const BookingSyncException(
      'JamooManagerフォルダを見つけられませんでした。\n'
      'C:\\work\\JamooManagerからアプリを起動してください。',
    );
  }

  Future<bool> _containsBookingScript(
    Directory directory,
  ) {
    final file = File(
      _joinPath(
        directory.path,
        [
          'booking_bot',
          _bookingScriptName,
        ],
      ),
    );

    return file.exists();
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
  }) async {
    final escapedDirectory = _escapePowerShellLiteral(
      bookingDirectory.path,
    );

    final command = [
      '& {',
      "Set-Location -LiteralPath '$escapedDirectory';",
      'node .\\booking.js;',
      r'$exitCode = $LASTEXITCODE;',
      "Write-Host '';",
      r"if ($exitCode -eq 0) {",
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

      final currentSnapshot =
          await _readFileSnapshot(jsonFile);

      if (currentSnapshot == null) {
        continue;
      }

      if (previousSnapshot == null ||
          currentSnapshot.content !=
              previousSnapshot.content ||
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

  static String _joinPath(
    String basePath,
    List<String> parts,
  ) {
    final separator = Platform.pathSeparator;
    final normalizedBase = basePath.endsWith(separator)
        ? basePath.substring(0, basePath.length - 1)
        : basePath;

    return [
      normalizedBase,
      ...parts,
    ].join(separator);
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
