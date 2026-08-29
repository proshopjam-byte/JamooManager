import 'package:flutter/material.dart';

import 'models/app_settings.dart';
import 'models/daily_operations.dart';
import 'models/reservation.dart';
import 'pages/customer_list_page.dart';
import 'pages/checkin_sheet_page.dart';
import 'pages/reservation_calendar_page.dart';
import 'pages/settings_page.dart';
import 'repositories/database_reservation_repository.dart';
import 'repositories/reservation_repository.dart';
import 'repositories/settings_repository.dart';
import 'services/booking_sync_service.dart';
import 'services/checkin_card_print_service.dart';
import 'services/chillnn_sync_service.dart';
import 'services/database_service.dart';
import 'services/portal_sync_service.dart';
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

  Future<DailyOperationsData>? _operationsFuture;
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

  Future<DailyOperationsData> _loadSelectedDateOperations() {
    return const DatabaseReservationRepository().loadDailyOperationsForDate(
      _selectedDate,
    );
  }

  BookingSyncService _createBookingSyncService() {
    return BookingSyncService(projectRootPath: _settings.managerRootPath);
  }

  ChillnnSyncService _createChillnnSyncService() {
    return ChillnnSyncService(projectRootPath: _settings.managerRootPath);
  }

  PortalSyncService _createPortalSyncService() {
    return PortalSyncService(projectRootPath: _settings.managerRootPath);
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
        _operationsFuture = _loadSelectedDateOperations();
      });
    } on SettingsRepositoryException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _settings = AppSettings.defaults;
        _isLoadingSettings = false;
        _operationsFuture = _loadSelectedDateOperations();
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
        _operationsFuture = _loadSelectedDateOperations();
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
      _operationsFuture = _loadSelectedDateOperations();
    });
  }

  void _showToday() {
    if (_isLoadingSettings) {
      return;
    }

    final now = DateTime.now();

    setState(() {
      _selectedDate = DateTime(now.year, now.month, now.day);
      _operationsFuture = _loadSelectedDateOperations();
    });
  }

  void _reload() {
    if (_isLoadingSettings) {
      return;
    }

    setState(() {
      _operationsFuture = _loadSelectedDateOperations();
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
      _operationsFuture = _loadSelectedDateOperations();
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('設定を保存し、データ保存場所を反映しました。')));
  }

  Future<void> _openReservationCalendar() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (context) => const ReservationCalendarPage()),
    );

    if (mounted) {
      _reload();
    }
  }

  Future<void> _openCustomerList() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (context) => const CustomerListPage()),
    );

    if (mounted) {
      _reload();
    }
  }

  Future<void> _openCheckinSheet() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => CheckinSheetPage(date: _selectedDate),
      ),
    );

    if (mounted) {
      _reload();
    }
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
        _operationsFuture = _loadSelectedDateOperations();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_settings.bookingSourceName}から'
            '今後の予約を取得しました。\n'
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

  Future<void> _syncFromChillnn() async {
    if (_isSyncing || _isLoadingSettings) {
      return;
    }

    setState(() {
      _isSyncing = true;
    });

    try {
      final syncResult = await _createChillnnSyncService().run();

      if (!mounted) {
        return;
      }

      setState(() {
        _operationsFuture = _loadSelectedDateOperations();
      });

      if (syncResult.failed > 0) {
        await _showErrorDialog(
          title: '一部のCHILLNNメールを取り込めませんでした',
          message:
              '${syncResult.summary}\n\n'
              '${syncResult.errorDetails ?? ''}',
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 8),
            content: Text(
              'CHILLNN予約を取得して保存しました。\n'
              '${syncResult.summary}',
            ),
          ),
        );
      }
    } on ChillnnSyncException catch (error) {
      if (!mounted) {
        return;
      }

      await _showErrorDialog(
        title: 'CHILLNNから取得できませんでした',
        message: error.message,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      await _showErrorDialog(
        title: 'CHILLNN取得中にエラーが発生しました',
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

  Future<void> _syncFromPortals() async {
    if (_isSyncing || _isLoadingSettings) {
      return;
    }

    setState(() {
      _isSyncing = true;
    });

    try {
      final syncResult = await _createPortalSyncService().run();
      if (!mounted) {
        return;
      }
      setState(() {
        _operationsFuture = _loadSelectedDateOperations();
      });
      if (syncResult.failed > 0) {
        await _showErrorDialog(
          title: '一部の楽天・じゃらんメールを取り込めませんでした',
          message:
              '${syncResult.summary}\n\n'
              '${syncResult.errorDetails ?? ''}',
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 8),
            content: Text(
              '楽天・じゃらん予約を取得して保存しました。\n'
              '${syncResult.summary}',
            ),
          ),
        );
      }
    } on PortalSyncException catch (error) {
      if (!mounted) {
        return;
      }
      await _showErrorDialog(
        title: '楽天・じゃらんから取得できませんでした',
        message: error.message,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await _showErrorDialog(
        title: '楽天・じゃらん取得中にエラーが発生しました',
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

  Future<void> _editArrivalTime(Reservation reservation) async {
    final reservationNumber = reservation.reservationNumber?.trim();
    if (reservationNumber == null || reservationNumber.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('予約番号がないため到着時間を保存できません。')));
      return;
    }

    final controller = TextEditingController(
      text: reservation.arrivalTime?.trim() ?? '',
    );
    final result = await showDialog<_ArrivalTimeEditResult>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${reservation.displayGuestName}様の到着時間'),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '到着予定',
              hintText: '例：15:00、15:00〜16:00、未定',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (value) =>
                Navigator.of(context).pop(_ArrivalTimeEditResult(value)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(const _ArrivalTimeEditResult(null)),
            child: const Text('未設定に戻す'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(
              context,
            ).pop(_ArrivalTimeEditResult(controller.text)),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;

    try {
      await const DatabaseReservationRepository().saveArrivalTime(
        source: reservation.source,
        reservationNumber: reservationNumber,
        arrivalTime: result.value,
      );
      if (!mounted) return;
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.value?.trim().isNotEmpty == true
                ? '到着時間を保存しました。'
                : '到着時間を未設定に戻しました。',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      await _showErrorDialog(title: '到着時間を保存できませんでした', message: '$error');
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
              ? '本日の運営ダッシュボード'
              : '${_formatDate(_selectedDate)}の運営ダッシュボード',
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
          IconButton(
            tooltip: '予約カレンダー',
            onPressed: _isLoadingSettings ? null : _openReservationCalendar,
            icon: const Icon(Icons.calendar_month_outlined),
          ),
          IconButton(
            tooltip: '部屋割り・チェックインシート',
            onPressed: _isLoadingSettings ? null : _openCheckinSheet,
            icon: const Icon(Icons.table_view_outlined),
          ),
          IconButton(
            tooltip: '顧客一覧',
            onPressed: _isLoadingSettings ? null : _openCustomerList,
            icon: const Icon(Icons.people_alt_outlined),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: OutlinedButton.icon(
              onPressed: _isSyncing || _isLoadingSettings
                  ? null
                  : _syncFromPortals,
              icon: const Icon(Icons.travel_explore_outlined),
              label: const Text('楽天・じゃらん'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: OutlinedButton.icon(
              onPressed: _isSyncing || _isLoadingSettings
                  ? null
                  : _syncFromChillnn,
              icon: const Icon(Icons.mail_outline),
              label: const Text('CHILLNNから取得'),
            ),
          ),
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
          if (_isLoadingSettings || _operationsFuture == null)
            const _LoadingView()
          else
            FutureBuilder<DailyOperationsData>(
              future: _operationsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const _LoadingView();
                }

                if (snapshot.hasError) {
                  return _ErrorView(error: snapshot.error, onRetry: _reload);
                }

                final data = snapshot.data;

                if (data == null) {
                  return _ErrorView(error: '運営データが空です。', onRetry: _reload);
                }

                return _TodayOperationsBody(
                  data: data,
                  settings: _settings,
                  onReload: _reload,
                  onSync: _syncFromBooking,
                  isSyncing: _isSyncing,
                  onEditArrivalTime: _editArrivalTime,
                );
              },
            ),
          if (_isSyncing) const _SyncingBanner(),
        ],
      ),
    );
  }
}

class _ArrivalTimeEditResult {
  const _ArrivalTimeEditResult(this.value);

  final String? value;
}

class _SyncingBanner extends StatelessWidget {
  const _SyncingBanner();

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
                  '予約情報を取得しています。'
                  '別画面が開いた場合は案内に従ってください。'
                  '取得後にデータベースへ保存して画面を更新します。',
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
          Text('設定と本日の運営情報を読み込んでいます…'),
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
                    '運営ダッシュボードを開けませんでした',
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

class _TodayOperationsBody extends StatelessWidget {
  const _TodayOperationsBody({
    required this.data,
    required this.settings,
    required this.onReload,
    required this.onSync,
    required this.isSyncing,
    required this.onEditArrivalTime,
  });

  final DailyOperationsData data;
  final AppSettings settings;
  final VoidCallback onReload;
  final VoidCallback onSync;
  final bool isSyncing;
  final Future<void> Function(Reservation) onEditArrivalTime;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        onReload();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        children: [
          if (data.isStale) ...[
            _OperationsDataWarning(
              generatedAt: data.generatedAt,
              bookingSourceName: settings.bookingSourceName,
              onSync: onSync,
              isSyncing: isSyncing,
            ),
            const SizedBox(height: 16),
          ],
          _OperationsSummaryPanel(data: data, settings: settings),
          const SizedBox(height: 18),
          _OperationSection(
            title: 'チェックアウト',
            description: '朝の対応・清掃準備を確認',
            icon: Icons.logout,
            reservations: data.departures,
            settings: settings,
            emptyMessage: '本日のチェックアウトはありません',
            showCheckinCard: false,
          ),
          const SizedBox(height: 18),
          _OperationSection(
            title: '連泊中',
            description: '今日も宿泊するお客様',
            icon: Icons.hotel_outlined,
            reservations: data.stayovers,
            settings: settings,
            emptyMessage: '連泊中のお客様はいません',
            showCheckinCard: false,
          ),
          const SizedBox(height: 18),
          _OperationSection(
            title: 'チェックイン',
            description: '到着時間・食事・料金を確認',
            icon: Icons.login,
            reservations: data.arrivals,
            settings: settings,
            emptyMessage: '本日のチェックインはありません',
            showCheckinCard: true,
            showReview: true,
            onEditArrivalTime: onEditArrivalTime,
          ),
        ],
      ),
    );
  }
}

class _OperationSection extends StatelessWidget {
  const _OperationSection({
    required this.title,
    required this.description,
    required this.icon,
    required this.reservations,
    required this.settings,
    required this.emptyMessage,
    required this.showCheckinCard,
    this.showReview = false,
    this.onEditArrivalTime,
  });

  final String title;
  final String description;
  final IconData icon;
  final List<Reservation> reservations;
  final AppSettings settings;
  final String emptyMessage;
  final bool showCheckinCard;
  final bool showReview;
  final Future<void> Function(Reservation)? onEditArrivalTime;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(width: 10),
            Text('${reservations.length}件'),
          ],
        ),
        const SizedBox(height: 2),
        Text(description, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 10),
        if (reservations.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(emptyMessage),
          )
        else
          for (final reservation in reservations) ...[
            _ReservationCard(
              reservation: reservation,
              settings: settings,
              showCheckinCard: showCheckinCard,
              showReview: showReview,
              onEditArrivalTime: onEditArrivalTime,
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _OperationsDataWarning extends StatelessWidget {
  const _OperationsDataWarning({
    required this.generatedAt,
    required this.bookingSourceName,
    required this.onSync,
    required this.isSyncing,
  });

  final DateTime? generatedAt;
  final String bookingSourceName;
  final VoidCallback onSync;
  final bool isSyncing;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, size: 30),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                generatedAt == null
                    ? '最終取得日時を確認できません。予約を再取得してください。'
                    : '最終取得は ${_formatDateTime(generatedAt)} です。最新の予約を確認してください。',
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: isSyncing ? null : onSync,
              icon: const Icon(Icons.cloud_download_outlined),
              label: Text('$bookingSourceNameから取得'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OperationsSummaryPanel extends StatelessWidget {
  const _OperationsSummaryPanel({required this.data, required this.settings});

  final DailyOperationsData data;
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
                  _formatDate(data.date) ?? _formatToday(),
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
                  label: 'チェックアウト',
                  value: '${data.departures.length}件・${data.departureGuests}名',
                  icon: Icons.logout,
                ),
                _SummaryItem(
                  label: '連泊',
                  value: '${data.stayovers.length}件・${data.stayoverGuests}名',
                  icon: Icons.hotel_outlined,
                ),
                _SummaryItem(
                  label: 'チェックイン',
                  value: '${data.arrivals.length}件・${data.arrivalGuests}名',
                  icon: Icons.login,
                ),
                _SummaryItem(
                  label: '今夜の宿泊',
                  value: '${data.occupiedRooms}室・${data.occupiedGuests}名',
                  icon: Icons.bed_outlined,
                ),
                _SummaryItem(
                  label: '朝食',
                  value: '${data.breakfastGuests}名',
                  icon: Icons.free_breakfast_outlined,
                ),
                _SummaryItem(
                  label: '夕食',
                  value: '${data.dinnerGuests}名',
                  icon: Icons.restaurant_outlined,
                ),
                _SummaryItem(
                  label: '要確認',
                  value: '${data.reviewCount}件',
                  icon: Icons.fact_check_outlined,
                  emphasize: data.reviewCount > 0,
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
    this.emphasize = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: emphasize
            ? Theme.of(context).colorScheme.errorContainer
            : Theme.of(context).colorScheme.surfaceContainerHighest,
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
  const _ReservationCard({
    required this.reservation,
    required this.settings,
    this.showCheckinCard = true,
    this.showReview = false,
    this.onEditArrivalTime,
  });

  final Reservation reservation;
  final AppSettings settings;
  final bool showCheckinCard;
  final bool showReview;
  final Future<void> Function(Reservation)? onEditArrivalTime;

  @override
  Widget build(BuildContext context) {
    final arrivalTime = reservation.arrivalTime?.trim();
    final reservationNumber = reservation.reservationNumber?.trim();
    final reviewReasons = showReview
        ? DailyOperationsData.reviewReasons(reservation)
        : const <String>[];

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
            const SizedBox(height: 8),
            _InformationRow(
              icon: Icons.restaurant_menu,
              label: _mealLabel(reservation),
            ),
            if (reviewReasons.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('要確認：${reviewReasons.join('・')}'),
              ),
            ],
            if (showCheckinCard || onEditArrivalTime != null) ...[
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    if (onEditArrivalTime != null)
                      FilledButton.tonalIcon(
                        onPressed: () async {
                          await onEditArrivalTime!(reservation);
                        },
                        icon: const Icon(Icons.schedule),
                        label: Text(
                          arrivalTime == null || arrivalTime.isEmpty
                              ? '到着時間を設定'
                              : '到着時間を変更',
                        ),
                      ),
                    if (showCheckinCard)
                      OutlinedButton.icon(
                        onPressed: () async {
                          try {
                            await const CheckinCardPrintService().previewCard(
                              context,
                              reservation,
                            );
                          } catch (error) {
                            if (!context.mounted) {
                              return;
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('PDFの作成に失敗しました: $error')),
                            );
                          }
                        },
                        icon: const Icon(Icons.print_outlined),
                        label: const Text('チェックインカード'),
                      ),
                  ],
                ),
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

  static String _mealLabel(Reservation reservation) {
    final breakfast = reservation.hasBreakfast == null
        ? '未設定'
        : reservation.hasBreakfast == true
        ? 'あり${reservation.breakfastGuestCount == null ? '' : '（${reservation.breakfastGuestCount}人分）'}'
        : 'なし';
    final dinner = reservation.hasDinner == null
        ? '未設定'
        : reservation.hasDinner == true
        ? 'あり'
        : 'なし';
    return '食事　朝食：$breakfast　夕食：$dinner';
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
