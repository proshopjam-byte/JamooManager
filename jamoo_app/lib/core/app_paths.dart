import 'dart:io';

class AppPaths {
  const AppPaths._({
    required this.projectRoot,
    required this.bookingBotDirectory,
    required this.bookingScript,
    required this.reservationJson,
  });

  final Directory projectRoot;
  final Directory bookingBotDirectory;
  final File bookingScript;
  final File reservationJson;

  static const String bookingBotFolderName = 'booking_bot';
  static const String bookingScriptFileName = 'booking.js';
  static const String outputFolderName = 'output';
  static const String reservationJsonFileName = 'reservations_latest.json';

  static Future<AppPaths> resolve({
    String? projectRootPath,
    String? bookingScriptPath,
    String? reservationJsonPath,
  }) async {
    final explicitBookingScript =
        _cleanPath(bookingScriptPath) ??
        _cleanPath(Platform.environment['JAMOO_BOOKING_SCRIPT']);

    final explicitReservationJson =
        _cleanPath(reservationJsonPath) ??
        _cleanPath(Platform.environment['JAMOO_RESERVATIONS_JSON']);

    final explicitProjectRoot =
        _cleanPath(projectRootPath) ??
        _cleanPath(Platform.environment['JAMOO_MANAGER_ROOT']);

    if (explicitProjectRoot != null) {
      return _fromProjectRoot(
        Directory(explicitProjectRoot),
        explicitBookingScript: explicitBookingScript,
        explicitReservationJson: explicitReservationJson,
      );
    }

    if (explicitBookingScript != null) {
      final scriptFile = File(explicitBookingScript).absolute;

      if (!await scriptFile.exists()) {
        throw AppPathsException(
          '指定されたBooking.com取得ファイルが'
          '見つかりません。\n${scriptFile.path}',
        );
      }

      final bookingDirectory = scriptFile.parent.absolute;

      final inferredRoot = bookingDirectory.parent.absolute;

      final jsonFile = explicitReservationJson != null
          ? File(explicitReservationJson).absolute
          : File(
              join(bookingDirectory.path, [
                outputFolderName,
                reservationJsonFileName,
              ]),
            );

      return AppPaths._(
        projectRoot: inferredRoot,
        bookingBotDirectory: bookingDirectory,
        bookingScript: scriptFile,
        reservationJson: jsonFile,
      );
    }

    final startingDirectories = <Directory>[
      File(Platform.resolvedExecutable).parent,
      Directory.current,
    ];

    final visited = <String>{};
    final searchedScripts = <String>[];

    for (final startingDirectory in startingDirectories) {
      var current = startingDirectory.absolute;

      while (visited.add(_normalizeForComparison(current.path))) {
        final candidateScript = File(
          join(current.path, [bookingBotFolderName, bookingScriptFileName]),
        );

        searchedScripts.add(candidateScript.path);

        if (await candidateScript.exists()) {
          return _fromProjectRoot(
            current,
            explicitReservationJson: explicitReservationJson,
          );
        }

        final parent = current.parent;

        if (_samePath(parent.path, current.path)) {
          break;
        }

        current = parent;
      }
    }

    throw AppPathsException(
      'JamooManagerのプロジェクトフォルダを'
      '見つけられませんでした。\n\n'
      '確認した場所：\n'
      '${searchedScripts.join('\n')}\n\n'
      '環境変数 JAMOO_MANAGER_ROOT で'
      'プロジェクト場所を指定することもできます。',
    );
  }

  static Future<AppPaths> _fromProjectRoot(
    Directory projectRoot, {
    String? explicitBookingScript,
    String? explicitReservationJson,
  }) async {
    final absoluteRoot = projectRoot.absolute;

    final bookingDirectory = Directory(
      join(absoluteRoot.path, [bookingBotFolderName]),
    );

    final scriptFile = explicitBookingScript != null
        ? File(explicitBookingScript).absolute
        : File(join(bookingDirectory.path, [bookingScriptFileName]));

    if (!await scriptFile.exists()) {
      throw AppPathsException(
        'JamooManagerフォルダ内に'
        'Booking.com取得ファイルが見つかりません。\n'
        '${scriptFile.path}',
      );
    }

    final jsonFile = explicitReservationJson != null
        ? File(explicitReservationJson).absolute
        : File(
            join(bookingDirectory.path, [
              outputFolderName,
              reservationJsonFileName,
            ]),
          );

    return AppPaths._(
      projectRoot: absoluteRoot,
      bookingBotDirectory: scriptFile.parent.absolute,
      bookingScript: scriptFile,
      reservationJson: jsonFile,
    );
  }

  Future<void> ensureOutputDirectory() async {
    await reservationJson.parent.create(recursive: true);
  }

  Future<bool> bookingScriptExists() {
    return bookingScript.exists();
  }

  Future<bool> reservationJsonExists() {
    return reservationJson.exists();
  }

  static String join(String basePath, List<String> parts) {
    final separator = Platform.pathSeparator;

    var result = basePath;

    for (final part in parts) {
      final cleanedPart = part
          .replaceAll('/', separator)
          .replaceAll('\\', separator)
          .replaceFirst(RegExp('^${RegExp.escape(separator)}+'), '');

      if (result.endsWith(separator)) {
        result = '$result$cleanedPart';
      } else {
        result = '$result$separator$cleanedPart';
      }
    }

    return result;
  }

  static String? _cleanPath(String? value) {
    if (value == null) {
      return null;
    }

    final cleaned = value.trim();

    if (cleaned.isEmpty) {
      return null;
    }

    if (cleaned.length >= 2 &&
        ((cleaned.startsWith('"') && cleaned.endsWith('"')) ||
            (cleaned.startsWith("'") && cleaned.endsWith("'")))) {
      return cleaned.substring(1, cleaned.length - 1);
    }

    return cleaned;
  }

  static bool _samePath(String first, String second) {
    return _normalizeForComparison(first) == _normalizeForComparison(second);
  }

  static String _normalizeForComparison(String value) {
    final absolute = Directory(value).absolute.path;

    if (Platform.isWindows) {
      return absolute.toLowerCase();
    }

    return absolute;
  }
}

class AppPathsException implements Exception {
  const AppPathsException(this.message);

  final String message;

  @override
  String toString() => message;
}
