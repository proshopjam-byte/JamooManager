import 'package:flutter/material.dart';

import 'models/reservation.dart';
import 'models/reservation_data.dart';
import 'repositories/reservation_repository.dart';

void main() {
  runApp(const JamooManagerApp());
}

class JamooManagerApp extends StatelessWidget {
  const JamooManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JamooManager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF386641),
        ),
        useMaterial3: true,
      ),
      home: const ReservationListPage(),
    );
  }
}

class ReservationListPage extends StatefulWidget {
  const ReservationListPage({super.key});

  @override
  State<ReservationListPage> createState() =>
      _ReservationListPageState();
}

class _ReservationListPageState
    extends State<ReservationListPage> {
  final ReservationRepository _repository =
      ReservationRepository();

  late Future<ReservationData> _reservationDataFuture;

  @override
  void initState() {
    super.initState();
    _reservationDataFuture = _repository.load();
  }

  void _reload() {
    setState(() {
      _reservationDataFuture = _repository.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('本日のチェックイン'),
        actions: [
          IconButton(
            tooltip: '本日のチェックインを再読込',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<ReservationData>(
        future: _reservationDataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            return const _LoadingView();
          }

          if (snapshot.hasError) {
            return _ErrorView(
              error: snapshot.error,
              onRetry: _reload,
            );
          }

          final data = snapshot.data;

          if (data == null || data.isEmpty) {
            return _EmptyView(onReload: _reload);
          }

          return _ReservationBody(
            data: data,
            onReload: _reload,
          );
        },
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
          Text('本日のチェックインを読み込んでいます…'),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.error,
    required this.onRetry,
  });

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
                    color: Theme.of(context)
                        .colorScheme
                        .error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '本日のチェックインを開けませんでした',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  SelectableText(
                    message,
                    textAlign: TextAlign.center,
                  ),
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
    required this.onReload,
  });

  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.event_available,
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              '本日のチェックインは0件です',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              '本日到着予定のお客様はいません。',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onReload,
              icon: const Icon(Icons.refresh),
              label: const Text('再読込'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReservationBody extends StatelessWidget {
  const _ReservationBody({
    required this.data,
    required this.onReload,
  });

  final ReservationData data;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final reservations = data.sortedByCheckIn;

    return RefreshIndicator(
      onRefresh: () async {
        onReload();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          16,
          16,
          16,
          32,
        ),
        children: [
          _SummaryPanel(data: data),
          const SizedBox(height: 16),
          Text(
            '本日到着のお客様',
            style: Theme.of(context)
                .textTheme
                .titleLarge,
          ),
          const SizedBox(height: 8),
          for (final reservation in reservations) ...[
            _ReservationCard(
              reservation: reservation,
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({
    required this.data,
  });

  final ReservationData data;

  @override
  Widget build(BuildContext context) {
    final generatedAtText =
        _formatGeneratedAt(data.generatedAt);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.hotel,
                  color: Theme.of(context)
                      .colorScheme
                      .primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '本日のチェックイン状況',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium,
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
                'データ取得：$generatedAtText',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String? _formatGeneratedAt(
    DateTime? value,
  ) {
    if (value == null) {
      return null;
    }

    final local = value.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month =
        local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour =
        local.hour.toString().padLeft(2, '0');
    final minute =
        local.minute.toString().padLeft(2, '0');

    return '$year/$month/$day $hour:$minute';
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
      constraints: const BoxConstraints(
        minWidth: 150,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall,
              ),
              Text(
                value,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium,
              ),
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
  });

  final Reservation reservation;

  @override
  Widget build(BuildContext context) {
    final arrivalTime =
        reservation.arrivalTime?.trim();
    final reservationNumber =
        reservation.reservationNumber?.trim();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  child: Text(
                    _initial(
                      reservation.displayGuestName,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        reservation.displayGuestName,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        reservation.displayRoomName,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium,
                      ),
                    ],
                  ),
                ),
                Text(
                  reservation.displayPrice,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium,
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
            if (arrivalTime != null &&
                arrivalTime.isNotEmpty) ...[
              const SizedBox(height: 8),
              _InformationRow(
                icon: Icons.schedule,
                label: '到着予定 $arrivalTime',
              ),
            ],
            if (reservationNumber != null &&
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
  const _InformationRow({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 20,
          color: Theme.of(context)
              .colorScheme
              .primary,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label),
        ),
      ],
    );
  }
}

String _formatYen(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer();

  for (var index = 0;
      index < digits.length;
      index++) {
    if (index > 0 &&
        (digits.length - index) % 3 == 0) {
      buffer.write(',');
    }

    buffer.write(digits[index]);
  }

  final amount = value < 0
      ? '-${buffer.toString()}'
      : buffer.toString();

  return '¥$amount';
}
