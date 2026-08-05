import 'dart:io';

import '../core/app_paths.dart';

class EnvironmentCheckService {
  const EnvironmentCheckService({
    this.projectRootPath,
  });

  final String? projectRootPath;

  Future<EnvironmentCheckReport> run() async {
    final checks = <EnvironmentCheckItem>[];

    checks.add(
      EnvironmentCheckItem(
        label: 'Windows環境',
        status: Platform.isWindows
            ? EnvironmentCheckStatus.ok
            : EnvironmentCheckStatus.error,
        message: Platform.isWindows
            ? 'Windowsで実行されています。'
            : '現在の自動取得機能はWindows版のみ対応しています。',
      ),
    );

    AppPaths? paths;

    try {
      paths = await AppPaths.resolve(
        projectRootPath: projectRootPath,
      );

      checks.add(
        EnvironmentCheckItem(
          label: 'JamooManager保存場所',
          status: EnvironmentCheckStatus.ok,
          message: paths.projectRoot.path,
        ),
      );
    } on AppPathsException catch (error) {
      checks.add(
        EnvironmentCheckItem(
          label: 'JamooManager保存場所',
          status: EnvironmentCheckStatus.error,
          message: error.message,
        ),
      );
    }

    checks.add(
      await _checkCommand(
        label: 'Node.js',
        command: 'where.exe',
        arguments: const ['node'],
        successMessage: 'Node.jsを確認しました。',
        failureMessage:
            'Node.jsが見つかりません。node --version を確認してください。',
      ),
    );

    checks.add(
      await _checkCommand(
        label: 'PowerShell',
        command: 'where.exe',
        arguments: const ['powershell.exe'],
        successMessage: 'PowerShellを確認しました。',
        failureMessage: 'PowerShellが見つかりません。',
      ),
    );

    if (paths != null) {
      checks.add(
        await _checkFile(
          label: 'Booking.com取得プログラム',
          file: paths.bookingScript,
          missingMessage:
              r'booking_bot\booking.js が見つかりません。',
        ),
      );

      final packageJson = File(
        AppPaths.join(
          paths.bookingBotDirectory.path,
          const ['package.json'],
        ),
      );

      checks.add(
        await _checkFile(
          label: 'Node.jsプロジェクト設定',
          file: packageJson,
          missingMessage:
              r'booking_bot\package.json が見つかりません。',
        ),
      );

      final playwrightDirectory = Directory(
        AppPaths.join(
          paths.bookingBotDirectory.path,
          const [
            'node_modules',
            'playwright',
          ],
        ),
      );

      final playwrightExists =
          await playwrightDirectory.exists();

      checks.add(
        EnvironmentCheckItem(
          label: 'Playwright',
          status: playwrightExists
              ? EnvironmentCheckStatus.ok
              : EnvironmentCheckStatus.warning,
          message: playwrightExists
              ? 'Playwrightがインストールされています。'
              : 'Playwrightが見つかりません。'
                  'booking_botで npm.cmd install playwright を実行してください。',
        ),
      );

      checks.add(
        await _checkReservationJson(
          paths.reservationJson,
        ),
      );
    }

    return EnvironmentCheckReport(
      checkedAt: DateTime.now(),
      items: List.unmodifiable(checks),
    );
  }

  Future<EnvironmentCheckItem> _checkCommand({
    required String label,
    required String command,
    required List<String> arguments,
    required String successMessage,
    required String failureMessage,
  }) async {
    try {
      final result = await Process.run(
        command,
        arguments,
        runInShell: true,
      );

      return EnvironmentCheckItem(
        label: label,
        status: result.exitCode == 0
            ? EnvironmentCheckStatus.ok
            : EnvironmentCheckStatus.error,
        message: result.exitCode == 0
            ? successMessage
            : failureMessage,
      );
    } on ProcessException catch (error) {
      return EnvironmentCheckItem(
        label: label,
        status: EnvironmentCheckStatus.error,
        message: '$failureMessage\n${error.message}',
      );
    }
  }

  Future<EnvironmentCheckItem> _checkFile({
    required String label,
    required File file,
    required String missingMessage,
  }) async {
    final exists = await file.exists();

    return EnvironmentCheckItem(
      label: label,
      status: exists
          ? EnvironmentCheckStatus.ok
          : EnvironmentCheckStatus.error,
      message: exists
          ? file.path
          : '$missingMessage\n${file.path}',
    );
  }

  Future<EnvironmentCheckItem> _checkReservationJson(
    File file,
  ) async {
    if (!await file.exists()) {
      return EnvironmentCheckItem(
        label: '予約JSON',
        status: EnvironmentCheckStatus.warning,
        message: 'まだ予約JSONがありません。'
            'Booking.comから取得すると作成されます。\n${file.path}',
      );
    }

    try {
      final modifiedAt = await file.lastModified();
      final now = DateTime.now();

      final isToday =
          modifiedAt.year == now.year &&
          modifiedAt.month == now.month &&
          modifiedAt.day == now.day;

      return EnvironmentCheckItem(
        label: '予約JSON',
        status: isToday
            ? EnvironmentCheckStatus.ok
            : EnvironmentCheckStatus.warning,
        message: isToday
            ? '本日更新されています。\n${file.path}'
            : '最終更新が本日ではありません。\n'
                '${_formatDateTime(modifiedAt)}\n${file.path}',
      );
    } on FileSystemException catch (error) {
      return EnvironmentCheckItem(
        label: '予約JSON',
        status: EnvironmentCheckStatus.error,
        message: '予約JSONの状態を確認できませんでした。\n'
            '${error.message}\n${file.path}',
      );
    }
  }

  static String _formatDateTime(
    DateTime value,
  ) {
    final local = value.toLocal();

    final year =
        local.year.toString().padLeft(4, '0');
    final month =
        local.month.toString().padLeft(2, '0');
    final day =
        local.day.toString().padLeft(2, '0');
    final hour =
        local.hour.toString().padLeft(2, '0');
    final minute =
        local.minute.toString().padLeft(2, '0');

    return '$year/$month/$day $hour:$minute';
  }
}

class EnvironmentCheckReport {
  const EnvironmentCheckReport({
    required this.checkedAt,
    required this.items,
  });

  final DateTime checkedAt;
  final List<EnvironmentCheckItem> items;

  bool get hasErrors {
    return items.any(
      (item) =>
          item.status == EnvironmentCheckStatus.error,
    );
  }

  bool get hasWarnings {
    return items.any(
      (item) =>
          item.status == EnvironmentCheckStatus.warning,
    );
  }

  int get errorCount {
    return items
        .where(
          (item) =>
              item.status ==
              EnvironmentCheckStatus.error,
        )
        .length;
  }

  int get warningCount {
    return items
        .where(
          (item) =>
              item.status ==
              EnvironmentCheckStatus.warning,
        )
        .length;
  }

  bool get isReady =>
      !hasErrors && !hasWarnings;
}

class EnvironmentCheckItem {
  const EnvironmentCheckItem({
    required this.label,
    required this.status,
    required this.message,
  });

  final String label;
  final EnvironmentCheckStatus status;
  final String message;
}

enum EnvironmentCheckStatus {
  ok,
  warning,
  error,
}
