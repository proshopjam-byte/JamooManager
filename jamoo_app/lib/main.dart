import 'package:flutter/material.dart';

import 'models/app_settings.dart';
import 'models/reservation.dart';
import 'models/reservation_data.dart';
import 'pages/settings_page.dart';
import 'repositories/database_reservation_repository.dart';
import 'repositories/reservation_repository.dart';
import 'repositories/settings_repository.dart';
import 'services/booking_sync_service.dart';
import 'services/database_service.dart';
import 'services/reservation_import_service.dart';

void main() {
  runApp(const JamooManagerApp());
}

class JamooManagerApp extends StatelessWidget {
  const JamooManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppSettings.defaults.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF386641)),
        useMaterial3: true,
      ),
      home: const TodayCheckInPage(),
    );
  }
}

class TodayCheckInPage extends StatefulWidget {
  const TodayCheckInPage({super.key});

  @override
  State<TodayCheckInPage> createState() => _TodayCheckInPageState();
}

class _TodayCheckInPageState extends State<TodayCheckInPage> {
  final SettingsRepository _settingsRepository = const SettingsRepository();

  Future<ReservationData>? _reservationDataFuture;
  DateTime _selectedDate = DateTime.now();

  AppSettings _settings = AppSettings.defaults;
  bool _isSyncing = false;
  bool _isLoadingSettings = true;

  ReservationRepository _createReservationRepository({AppSettings? settings}) {
    final targetSettings = settings ?? _settings;

    return ReservationRepository(
      projectRootPath: targetSettings.managerRootPath,
    );
  }

  Future<ReservationData> _loadSelectedDateCheckIns() {
    return const DatabaseReservationRepository().loadCheckInsForDate(
      _selectedDate,
    );
  }

  BookingSyncService _createBookingSyncService() {
    return BookingSyncService(projectRootPath: _settings.managerRootPath);
  }

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _initializeDatabase();

    try {
      final settings = await _settingsRepository.load();

      if (!mounted) {
        return;
      }

      setState(() {
        _settings = settings;
        _isLoadingSettings = false;
        _reservationDataFuture = _loadSelectedDateCheckIns();
      });
    } on SettingsRepositoryException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _settings = AppSettings.defaults;
        _isLoadingSettings = false;
        _reservationDataFuture = _loadSelectedDateCheckIns();
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showErrorDialog(title: '設定を読み込めませんでした', message: error.message);
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _settings = AppSettings.defaults;
        _isLoadingSettings = false;
        _reservationDataFuture = _loadSelectedDateCheckIns();
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showErrorDialog(
            title: '設定の読み込み中にエラーが発生しました',
            message: error.toString(),
          );
        }
      });
    }
  }

  Future<void> _initializeDatabase() async {
    try {
      await DatabaseService.instance.database;
    } catch (error) {
      if (!mounted) {
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }

        _showErrorDialog(
          title: 'データベースを初期化できませんでした',
          message:
              'JamooManagerの中央データベースを'
              '作成できませんでした。\n\n'
              '$error\n\n'
              '設定と保存先を確認してから、'
              'アプリを再起動してください。',
        );
      });
    }
  }

  bool get _isViewingToday {
    final now = DateTime.now();

    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  void _changeSelectedDate(int dayOffset) {
    if (_isLoadingSettings) {
      return;
    }

    final nextDate = _selectedDate.add(Duration(days: dayOffset));

    setState(() {
      _selectedDate = DateTime(nextDate.year, nextDate.month, nextDate.day);
      _reservationDataFuture = _loadSelectedDateCheckIns();
    });
  }

  void _showToday() {
    if (_isLoadingSettings) {
      return;
    }

    final now = DateTime.now();

    setState(() {
      _selectedDate = DateTime(now.year, now.month, now.day);
      _reservationDataFuture = _loadSelectedDateCheckIns();
    });
  }

  void _reload() {
    if (_isLoadingSettings) {
      return;
    }

    setState(() {
      _reservationDataFuture = _loadSelectedDateCheckIns();
    });
  }

  Future<void> _openSettings() async {
    final updatedSettings = await Navigator.of(context).push<AppSettings>(
      MaterialPageRoute(
        builder: (context) {
          return SettingsPage(initialSettings: _settings);
        },
      ),
    );

    if (!mounted || updatedSettings == null) {
      return;
    }

    setState(() {
      _settings = updatedSettings;
      _reservationDataFuture = _loadSelectedDateCheckIns();
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('設定を保存し、データ保存場所を反映しました。')));
  }

  Future<void> _syncFromBooking() async {
    if (_isSyncing || _isLoadingSettings) {
      return;
    }

    setState(() {
      _isSyncing = true;
    });

    try {
      final syncService = _createBookingSyncService();
      await syncService.run();

      final repository = _createReservationRepository();
      final reservationData = await repository.load();

      final importResult = await const ReservationImportService()
          .importReservationData(reservationData);

      if (!mounted) {
        return;
      }

      setState(() {
        _reservationDataFuture = _loadSelectedDateCheckIns();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_settings.bookingSourceName}から'
            '本日のチェックインを取得しました。\n'
            '${importResult.summary}',
          ),
        ),
      );
    } on BookingSyncException catch (error) {
      if (!mounted) {
        return;
      }

      await _showErrorDialog(
        title: '${_settings.bookingSourceName}から取得できませんでした',
        message: error.message,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      await _showErrorDialog(
        title: '予期しないエラーが発生しました',
        message: error.toString(),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  Future<void> _showErrorDialog({
    required String title,
    required String message,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: SelectableText(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('閉じる'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final syncButtonText = '${_settings.bookingSourceName}から取得';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isViewingToday
              ? '本日のチェックイン'
              : '${_formatDate(_selectedDate)}のチェックイン',
        ),
        actions: [
          IconButton(
            tooltip: '前日',
            onPressed: _isLoadingSettings
                ? null
                : () => _changeSelectedDate(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          TextButton(
            onPressed: _isLoadingSettings || _isViewingToday
                ? null
                : _showToday,
            child: const Text('今日'),
          ),
          IconButton(
            tooltip: '翌日',
            onPressed: _isLoadingSettings ? null : () => _changeSelectedDate(1),
            icon: const Icon(Icons.chevron_right),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              onPressed: _isSyncing || _isLoadingSettings
                  ? null
                  : _syncFromBooking,
              icon: _isSyncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_download_outlined),
              label: Text(_isSyncing ? '取得処理中' : syncButtonText),
            ),
          ),
          IconButton(
            tooltip: '一覧を再読込',
            onPressed: _isSyncing || _isLoadingSettings ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '設定',
            onPressed: _isLoadingSettings ? null : _openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        children: [
          if (_isLoadingSettings || _reservationDataFuture == null)
            const _LoadingView()
          else
            FutureBuilder<ReservationData>(
              future: _reservationDataFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const _LoadingView();
                }

                if (snapshot.hasError) {
                  return _ErrorView(error: snapshot.error, onRetry: _reload);
                }

                final data = snapshot.data;

                if (data == null || data.isEmpty) {
                  return _EmptyView(
                    settings: _settings,
                    targetDate: data?.targetDate ?? _selectedDate,
                    generatedAt: data?.generatedAt,
                    onReload: _reload,
                    onSync: _syncFromBooking,
                    isSyncing: _isSyncing,
                  );
                }

                return _TodayCheckInBody(
                  data: data,
                  settings: _settings,
                  onReload: _reload,
                  onSync: _syncFromBooking,
                  isSyncing: _isSyncing,
                );
              },
            ),
          if (_isSyncing)
            _SyncingBanner(bookingSourceName: _settings.bookingSourceName),
        ],
      ),
    );
  }
}

class _SyncingBanner extends StatelessWidget {
  const _SyncingBanner({required this.bookingSourceName});

  final String bookingSourceName;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 16,
      child: Card(
        elevation: 8,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  '別画面で$bookingSourceNameの操作を'
                  '完了してください。'
                  '取得後にデータベースへ保存し、画面を更新します。',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('設定と本日のチェックインを読み込んでいます…'),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final message = error is ReservationRepositoryException
        ? error.toString()
        : '予約データの読み込みに失敗しました。\n$error';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 56,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '本日のチェックインを開けませんでした',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  SelectableText(message, textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('もう一度読み込む'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({
    required this.settings,
    required this.targetDate,
    required this.generatedAt,
    required this.onReload,
    required this.onSync,
    required this.isSyncing,
  });

  final AppSettings settings;
  final DateTime targetDate;
  final DateTime? generatedAt;
  final VoidCallback onReload;
  final VoidCallback onSync;
  final bool isSyncing;

  @override
  Widget build(BuildContext context) {
    final targetDateText = _formatDate(targetDate) ?? _formatToday();
    final now = DateTime.now();
    final isToday =
        targetDate.year == now.year &&
        targetDate.month == now.month &&
        targetDate.day == now.day;
    final generatedAtText = _formatDateTime(generatedAt);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 650),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    settings.facilityName,
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 18),
                  Icon(
                    Icons.event_available,
                    size: 72,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    targetDateText,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    isToday ? '本日のチェックインは0件です' : 'この日のチェックインは0件です',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    isToday ? '本日到着予定のお客様はいません。' : 'この日に到着予定のお客様はいません。',
                    textAlign: TextAlign.center,
                  ),
                  if (generatedAtText != null) ...[
                    const SizedBox(height: 20),
                    Text(
                      '最終取得：$generatedAtText',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 26),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: isSyncing ? null : onSync,
                        icon: const Icon(Icons.cloud_download_outlined),
                        label: Text('${settings.bookingSourceName}から取得'),
                      ),
                      OutlinedButton.icon(
                        onPressed: isSyncing ? null : onReload,
                        icon: const Icon(Icons.refresh),
                        label: const Text('一覧を再読込'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TodayCheckInBody extends StatelessWidget {
  const _TodayCheckInBody({
    required this.data,
    required this.settings,
    required this.onReload,
    required this.onSync,
    required this.isSyncing,
  });

  final ReservationData data;
  final AppSettings settings;
  final VoidCallback onReload;
  final VoidCallback onSync;
  final bool isSyncing;

  @override
  Widget build(BuildContext context) {
    final reservations = data.sortedByCheckIn;

    return RefreshIndicator(
      onRefresh: () async {
        onReload();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        children: [
          if (!data.isTodayCheckIns || data.isStale) ...[
            _OldDataWarning(
              data: data,
              bookingSourceName: settings.bookingSourceName,
              onSync: onSync,
              isSyncing: isSyncing,
            ),
            const SizedBox(height: 16),
          ],
          _SummaryPanel(data: data, settings: settings),
          const SizedBox(height: 18),
          Text(
            data.isForToday ? '本日到着のお客様' : 'この日に到着のお客様',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          for (final reservation in reservations) ...[
            _ReservationCard(reservation: reservation, settings: settings),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _OldDataWarning extends StatelessWidget {
  const _OldDataWarning({
    required this.data,
    required this.bookingSourceName,
    required this.onSync,
    required this.isSyncing,
  });

  final ReservationData data;
  final String bookingSourceName;
  final VoidCallback onSync;
  final bool isSyncing;

  @override
  Widget build(BuildContext context) {
    final generatedAtText = _formatDateTime(data.generatedAt);

    final reasons = <String>[];

    if (!data.isTodayCheckIns) {
      reasons.add('表示データが「当日チェックイン専用」の形式ではありません。');
    }

    if (data.isStale) {
      reasons.add(
        generatedAtText == null
            ? '最終取得日時を確認できません。'
            : '最終取得は $generatedAtText です。',
      );
    }

    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: 30,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '予約データの取得状況を確認してください',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final reason in reasons)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '・$reason',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: isSyncing ? null : onSync,
                    icon: const Icon(Icons.cloud_download_outlined),
                    label: Text('$bookingSourceNameから本日分を取得'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({required this.data, required this.settings});

  final ReservationData data;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final generatedAtText = _formatDateTime(data.generatedAt);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              settings.facilityName,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.login, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  _formatDate(data.targetDate) ?? _formatToday(),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _SummaryItem(
                  label: 'チェックイン',
                  value: '${data.reservations.length}件',
                  icon: Icons.event_note,
                ),
                _SummaryItem(
                  label: '宿泊人数',
                  value: '${data.totalGuests}名',
                  icon: Icons.people_alt_outlined,
                ),
                if (settings.showPrice)
                  _SummaryItem(
                    label: '予約金額',
                    value: _formatYen(data.totalPriceYen),
                    icon: Icons.payments_outlined,
                  ),
              ],
            ),
            if (generatedAtText != null) ...[
              const SizedBox(height: 14),
              Text(
                '最終取得：$generatedAtText',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              Text(value, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReservationCard extends StatelessWidget {
  const _ReservationCard({required this.reservation, required this.settings});

  final Reservation reservation;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final arrivalTime = reservation.arrivalTime?.trim();
    final reservationNumber = reservation.reservationNumber?.trim();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  child: Text(_initial(reservation.displayGuestName)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reservation.displayGuestName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        reservation.displayRoomName,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                if (settings.showPrice)
                  Text(
                    reservation.displayPrice,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _InformationRow(
              icon: Icons.date_range,
              label: reservation.displayStayPeriod,
            ),
            const SizedBox(height: 8),
            _InformationRow(
              icon: Icons.people_outline,
              label: reservation.displayGuestCount,
            ),
            if (settings.showArrivalTime &&
                arrivalTime != null &&
                arrivalTime.isNotEmpty) ...[
              const SizedBox(height: 8),
              _InformationRow(icon: Icons.schedule, label: '到着予定 $arrivalTime'),
            ],
            if (settings.showReservationNumber &&
                reservationNumber != null &&
                reservationNumber.isNotEmpty) ...[
              const SizedBox(height: 8),
              _InformationRow(
                icon: Icons.confirmation_number_outlined,
                label: '予約番号 $reservationNumber',
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _initial(String name) {
    final trimmed = name.trim();

    if (trimmed.isEmpty) {
      return '?';
    }

    return trimmed.substring(0, 1).toUpperCase();
  }
}

class _InformationRow extends StatelessWidget {
  const _InformationRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(child: Text(label)),
      ],
    );
  }
}

String _formatToday() {
  final now = DateTime.now();
  final year = now.year.toString().padLeft(4, '0');
  final month = now.month.toString().padLeft(2, '0');
  final day = now.day.toString().padLeft(2, '0');

  return '$year/$month/$day';
}

String? _formatDate(DateTime? value) {
  if (value == null) {
    return null;
  }

  final year = value.year.toString().padLeft(4, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');

  return '$year/$month/$day';
}

String? _formatDateTime(DateTime? value) {
  if (value == null) {
    return null;
  }

  final local = value.toLocal();
  final year = local.year.toString().padLeft(4, '0');
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');

  return '$year/$month/$day $hour:$minute';
}

String _formatYen(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer();

  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) {
      buffer.write(',');
    }

    buffer.write(digits[index]);
  }

  final amount = value < 0 ? '-${buffer.toString()}' : buffer.toString();

  return '¥$amount';
}
