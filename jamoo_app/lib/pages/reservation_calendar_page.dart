import 'package:flutter/material.dart';

import '../models/reservation.dart';
import '../repositories/database_reservation_repository.dart';
import '../services/checkin_card_print_service.dart';
import 'manual_reservation_dialog.dart';

class ReservationCalendarPage extends StatefulWidget {
  const ReservationCalendarPage({super.key});

  @override
  State<ReservationCalendarPage> createState() =>
      _ReservationCalendarPageState();
}

class _ReservationCalendarPageState extends State<ReservationCalendarPage> {
  static const _repository = DatabaseReservationRepository();

  late DateTime _visibleMonth;
  late DateTime _selectedDate;
  late Future<List<Reservation>> _reservationsFuture;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month);
    _selectedDate = DateTime(now.year, now.month, now.day);
    _reservationsFuture = _loadMonth();
  }

  Future<List<Reservation>> _loadMonth() {
    final days = _calendarDays(_visibleMonth);
    return _repository.loadReservationsOverlapping(days.first, days.last);
  }

  void _changeMonth(int offset) {
    final next = DateTime(_visibleMonth.year, _visibleMonth.month + offset);
    setState(() {
      _visibleMonth = DateTime(next.year, next.month);
      _selectedDate = DateTime(next.year, next.month, 1);
      _reservationsFuture = _loadMonth();
    });
  }

  void _showToday() {
    final now = DateTime.now();
    setState(() {
      _visibleMonth = DateTime(now.year, now.month);
      _selectedDate = DateTime(now.year, now.month, now.day);
      _reservationsFuture = _loadMonth();
    });
  }

  void _reload() {
    setState(() {
      _reservationsFuture = _loadMonth();
    });
  }

  Future<void> _saveManualReservation([Reservation? reservation]) async {
    final data = await showManualReservationDialog(
      context,
      initialDate: reservation?.checkIn ?? _selectedDate,
      reservation: reservation,
    );
    if (data == null) return;

    await _repository.saveManualReservation(
      reservationNumber: reservation?.reservationNumber,
      guestName: data.guestName,
      checkIn: data.checkIn,
      checkOut: data.checkOut,
      roomName: data.roomName,
      adults: data.adults,
      childrenWithBed: data.childrenWithBed,
      childrenWithoutBed: data.childrenWithoutBed,
      priceYen: data.priceYen,
      phone: data.phone,
      address: data.address,
      postalCode: data.postalCode,
      notes: data.notes,
      hasBreakfast: data.hasBreakfast,
      hasDinner: data.hasDinner,
    );
    if (!mounted) return;
    _reload();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(reservation == null ? '直接予約を追加しました。' : '直接予約を更新しました。'),
      ),
    );
  }

  Future<void> _cancelManualReservation(Reservation reservation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('直接予約をキャンセル'),
        content: Text('${reservation.displayGuestName}様の予約をキャンセルしますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('キャンセルする'),
          ),
        ],
      ),
    );
    if (confirmed != true || reservation.reservationNumber == null) return;
    await _repository.cancelManualReservation(reservation.reservationNumber!);
    if (!mounted) return;
    _reload();
  }

  Future<void> _editMealSettings(Reservation reservation) async {
    final number = reservation.reservationNumber;
    if (number == null) return;
    final data = await showMealSettingsDialog(
      context,
      reservation: reservation,
    );
    if (data == null) return;
    await _repository.saveMealOverride(
      source: reservation.source,
      reservationNumber: number,
      hasBreakfast: data.hasBreakfast,
      hasDinner: data.hasDinner,
    );
    if (!mounted) return;
    _reload();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('食事設定を保存しました。')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('予約カレンダー'),
        actions: [
          FilledButton.icon(
            onPressed: _saveManualReservation,
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            icon: const Icon(Icons.add, size: 20),
            label: const Text('予約追加'),
          ),
          IconButton(
            tooltip: '前月',
            onPressed: () => _changeMonth(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          TextButton(onPressed: _showToday, child: const Text('今月')),
          IconButton(
            tooltip: '翌月',
            onPressed: () => _changeMonth(1),
            icon: const Icon(Icons.chevron_right),
          ),
          IconButton(
            tooltip: '再読込',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: FutureBuilder<List<Reservation>>(
        future: _reservationsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 44),
                    const SizedBox(height: 12),
                    Text('予約カレンダーを読み込めませんでした。\n${snapshot.error}'),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _reload, child: const Text('再試行')),
                  ],
                ),
              ),
            );
          }

          final reservations = snapshot.data ?? const <Reservation>[];
          return _CalendarBody(
            visibleMonth: _visibleMonth,
            selectedDate: _selectedDate,
            reservations: reservations,
            onDateSelected: (date) {
              setState(() {
                _selectedDate = date;
              });
            },
            onEditManual: _saveManualReservation,
            onCancelManual: _cancelManualReservation,
            onEditMeals: _editMealSettings,
          );
        },
      ),
    );
  }
}

class _CalendarBody extends StatelessWidget {
  const _CalendarBody({
    required this.visibleMonth,
    required this.selectedDate,
    required this.reservations,
    required this.onDateSelected,
    required this.onEditManual,
    required this.onCancelManual,
    required this.onEditMeals,
  });

  final DateTime visibleMonth;
  final DateTime selectedDate;
  final List<Reservation> reservations;
  final ValueChanged<DateTime> onDateSelected;
  final ValueChanged<Reservation> onEditManual;
  final ValueChanged<Reservation> onCancelManual;
  final ValueChanged<Reservation> onEditMeals;

  @override
  Widget build(BuildContext context) {
    final days = _calendarDays(visibleMonth);
    final selectedReservations = reservations
        .where((reservation) => _staysOn(reservation, selectedDate))
        .toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1050;
        final calendar = _MonthCalendar(
          visibleMonth: visibleMonth,
          selectedDate: selectedDate,
          days: days,
          reservations: reservations,
          onDateSelected: onDateSelected,
        );
        final details = _SelectedDateReservations(
          selectedDate: selectedDate,
          reservations: selectedReservations,
          allReservations: reservations,
          onEditManual: onEditManual,
          onCancelManual: onCancelManual,
          onEditMeals: onEditMeals,
        );

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: calendar),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: details),
                  ],
                )
              : Column(
                  children: [calendar, const SizedBox(height: 16), details],
                ),
        );
      },
    );
  }
}

class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({
    required this.visibleMonth,
    required this.selectedDate,
    required this.days,
    required this.reservations,
    required this.onDateSelected,
  });

  final DateTime visibleMonth;
  final DateTime selectedDate;
  final List<DateTime> days;
  final List<Reservation> reservations;
  final ValueChanged<DateTime> onDateSelected;

  @override
  Widget build(BuildContext context) {
    final monthlyCheckIns = reservations
        .where(
          (reservation) =>
              _checksInDuringMonth(reservation, visibleMonth) &&
              !_isCancelled(reservation),
        )
        .toList(growable: false);
    final monthlySales = _salesTotal(monthlyCheckIns);
    final monthlyUnsetPrices = monthlyCheckIns
        .where((reservation) => reservation.priceYen == null)
        .length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${visibleMonth.year}年 ${visibleMonth.month}月',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  _LegendDot(color: Color(0xFF386641), label: 'CHILLNN'),
                  _LegendDot(color: Color(0xFF1565C0), label: 'Booking.com'),
                  _LegendDot(color: Color(0xFFBF0000), label: '楽天トラベル'),
                  _LegendDot(color: Color(0xFFE91E63), label: 'じゃらん'),
                  _LegendDot(color: Color(0xFFEF6C00), label: '直接予約'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _MonthlySalesSummary(
              visibleMonth: visibleMonth,
              amount: monthlySales,
              reservationCount: monthlyCheckIns.length,
              unsetPriceCount: monthlyUnsetPrices,
            ),
            const SizedBox(height: 14),
            const Row(
              children: [
                _Weekday('日', color: Colors.red),
                _Weekday('月'),
                _Weekday('火'),
                _Weekday('水'),
                _Weekday('木'),
                _Weekday('金'),
                _Weekday('土', color: Colors.blue),
              ],
            ),
            const SizedBox(height: 6),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 0.75,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: days.length,
              itemBuilder: (context, index) {
                final date = days[index];
                final inVisibleMonth =
                    date.year == visibleMonth.year &&
                    date.month == visibleMonth.month;
                final dayReservations = reservations
                    .where((reservation) => _staysOn(reservation, date))
                    .toList(growable: false);
                final dayCheckIns = inVisibleMonth
                    ? reservations
                          .where(
                            (reservation) =>
                                _checksInOn(reservation, date) &&
                                !_isCancelled(reservation),
                          )
                          .toList(growable: false)
                    : const <Reservation>[];
                return _CalendarDay(
                  date: date,
                  inVisibleMonth: inVisibleMonth,
                  selected: _sameDay(date, selectedDate),
                  reservations: dayReservations,
                  checkInSales: _salesTotal(dayCheckIns),
                  checkInCount: dayCheckIns.length,
                  unsetPriceCount: dayCheckIns
                      .where((reservation) => reservation.priceYen == null)
                      .length,
                  onTap: () => onDateSelected(date),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthlySalesSummary extends StatelessWidget {
  const _MonthlySalesSummary({
    required this.visibleMonth,
    required this.amount,
    required this.reservationCount,
    required this.unsetPriceCount,
  });

  final DateTime visibleMonth;
  final int amount;
  final int reservationCount;
  final int unsetPriceCount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.payments_outlined, color: colorScheme.onPrimaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${visibleMonth.month}月の売上（チェックイン基準）',
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '有効予約 $reservationCount件',
                  style: TextStyle(color: colorScheme.onPrimaryContainer),
                ),
                if (unsetPriceCount > 0)
                  Text(
                    '※料金未設定 $unsetPriceCount件は合計に含まれません',
                    style: TextStyle(
                      color: colorScheme.error,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _formatYen(amount),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarDay extends StatelessWidget {
  const _CalendarDay({
    required this.date,
    required this.inVisibleMonth,
    required this.selected,
    required this.reservations,
    required this.checkInSales,
    required this.checkInCount,
    required this.unsetPriceCount,
    required this.onTap,
  });

  final DateTime date;
  final bool inVisibleMonth;
  final bool selected;
  final List<Reservation> reservations;
  final int checkInSales;
  final int checkInCount;
  final int unsetPriceCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final chillnnCount = reservations
        .where((reservation) => reservation.source.toUpperCase() == 'CHILLNN')
        .fold<int>(0, (sum, reservation) => sum + reservation.roomCount);
    final manualCount = reservations
        .where((reservation) => reservation.source.toUpperCase() == 'MANUAL')
        .fold<int>(0, (sum, reservation) => sum + reservation.roomCount);
    final bookingCount = reservations
        .where((reservation) => _sourceType(reservation.source) == 'booking')
        .fold<int>(0, (sum, reservation) => sum + reservation.roomCount);
    final rakutenCount = reservations
        .where((reservation) => _sourceType(reservation.source) == 'rakuten')
        .fold<int>(0, (sum, reservation) => sum + reservation.roomCount);
    final jalanCount = reservations
        .where((reservation) => _sourceType(reservation.source) == 'jalan')
        .fold<int>(0, (sum, reservation) => sum + reservation.roomCount);
    final breakfastGuests = reservations
        .where((reservation) => reservation.hasBreakfast == true)
        .fold<int>(
          0,
          (sum, reservation) =>
              sum +
              (reservation.breakfastGuestCount ?? _guestCount(reservation)),
        );
    final dinnerGuests = reservations
        .where((reservation) => reservation.hasDinner == true)
        .fold<int>(0, (sum, reservation) => sum + _guestCount(reservation));

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primaryContainer
              : inVisibleMonth
              ? colorScheme.surfaceContainerLowest
              : colorScheme.surfaceContainerLow.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? colorScheme.primary : colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${date.day}',
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    color: inVisibleMonth
                        ? colorScheme.onSurface
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
                if (inVisibleMonth && checkInCount > 0) ...[
                  const SizedBox(width: 3),
                  Expanded(
                    child: Tooltip(
                      message: unsetPriceCount > 0
                          ? 'チェックイン売上 ${_formatYen(checkInSales)}\n'
                                '料金未設定 $unsetPriceCount件'
                          : 'チェックイン売上 ${_formatYen(checkInSales)}',
                      child: Text(
                        '${_formatYen(checkInSales)}${unsetPriceCount > 0 ? '※' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                          color: Color(0xFF2E7D32),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const Spacer(),
            if (chillnnCount > 0)
              _CountBadge(color: const Color(0xFF386641), count: chillnnCount),
            if (bookingCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: _CountBadge(
                  color: const Color(0xFF1565C0),
                  count: bookingCount,
                ),
              ),
            if (rakutenCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: _CountBadge(
                  color: const Color(0xFFBF0000),
                  count: rakutenCount,
                ),
              ),
            if (jalanCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: _CountBadge(
                  color: const Color(0xFFE91E63),
                  count: jalanCount,
                ),
              ),
            if (manualCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: _CountBadge(
                  color: const Color(0xFFEF6C00),
                  count: manualCount,
                ),
              ),
            if (breakfastGuests > 0 || dinnerGuests > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    if (breakfastGuests > 0)
                      Expanded(
                        child: _MealCountBadge(
                          color: const Color(0xFF795548),
                          label: '朝食',
                          count: breakfastGuests,
                        ),
                      ),
                    if (breakfastGuests > 0 && dinnerGuests > 0)
                      const SizedBox(width: 3),
                    if (dinnerGuests > 0)
                      Expanded(
                        child: _MealCountBadge(
                          color: const Color(0xFF7E57C2),
                          label: '夕食',
                          count: dinnerGuests,
                        ),
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

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.color, required this.count});

  final Color color;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count室',
        maxLines: 1,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _MealCountBadge extends StatelessWidget {
  const _MealCountBadge({
    required this.color,
    required this.label,
    required this.count,
  });

  final Color color;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label $count人',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _SelectedDateReservations extends StatelessWidget {
  const _SelectedDateReservations({
    required this.selectedDate,
    required this.reservations,
    required this.allReservations,
    required this.onEditManual,
    required this.onCancelManual,
    required this.onEditMeals,
  });

  final DateTime selectedDate;
  final List<Reservation> reservations;
  final List<Reservation> allReservations;
  final ValueChanged<Reservation> onEditManual;
  final ValueChanged<Reservation> onCancelManual;
  final ValueChanged<Reservation> onEditMeals;

  @override
  Widget build(BuildContext context) {
    final selectedCheckIns = allReservations
        .where(
          (reservation) =>
              _checksInOn(reservation, selectedDate) &&
              !_isCancelled(reservation),
        )
        .toList(growable: false);
    final selectedDateSales = _salesTotal(selectedCheckIns);
    final selectedDateUnsetPrices = selectedCheckIns
        .where((reservation) => reservation.priceYen == null)
        .length;
    final totalGuests = reservations.fold<int>(0, (sum, reservation) {
      final count =
          reservation.totalGuests ??
          (reservation.adults ?? 0) + reservation.children;
      return sum + count;
    });
    final totalRooms = reservations.fold<int>(
      0,
      (sum, reservation) => sum + reservation.roomCount,
    );
    final breakfastGuests = allReservations
        .where(
          (reservation) =>
              reservation.hasBreakfast == true &&
              _staysOn(reservation, selectedDate),
        )
        .fold<int>(
          0,
          (sum, reservation) =>
              sum +
              (reservation.breakfastGuestCount ?? _guestCount(reservation)),
        );
    final dinnerGuests = allReservations
        .where(
          (reservation) =>
              reservation.hasDinner == true &&
              _staysOn(reservation, selectedDate),
        )
        .fold<int>(0, (sum, reservation) => sum + _guestCount(reservation));
    final unsetMeals = allReservations.where((reservation) {
      return _staysOn(reservation, selectedDate) &&
          (reservation.hasBreakfast == null || reservation.hasDinner == null);
    }).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${selectedDate.month}月${selectedDate.day}日の宿泊',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text('$totalRooms室・$totalGuests名'),
            if (selectedCheckIns.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.payments_outlined, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'チェックイン売上 ${_formatYen(selectedDateSales)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              if (selectedDateUnsetPrices > 0)
                Text(
                  '※料金未設定 $selectedDateUnsetPrices件',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'この日の食事準備',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text('☕ 翌朝の朝食　$breakfastGuests人分'),
                  Text('🍽 夕食　$dinnerGuests人分'),
                  if (unsetMeals > 0)
                    Text(
                      '⚠ 食事未設定　$unsetMeals件',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 28),
            if (reservations.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: Text('この日の宿泊予約はありません。')),
              )
            else
              ...reservations.map(
                (reservation) => _ReservationTile(
                  reservation: reservation,
                  onEditManual: onEditManual,
                  onCancelManual: onCancelManual,
                  onEditMeals: onEditMeals,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReservationTile extends StatelessWidget {
  const _ReservationTile({
    required this.reservation,
    required this.onEditManual,
    required this.onCancelManual,
    required this.onEditMeals,
  });

  final Reservation reservation;
  final ValueChanged<Reservation> onEditManual;
  final ValueChanged<Reservation> onCancelManual;
  final ValueChanged<Reservation> onEditMeals;

  @override
  Widget build(BuildContext context) {
    final sourceType = _sourceType(reservation.source);
    final isManual = sourceType == 'manual';
    final sourceColor = _sourceColor(sourceType);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: sourceColor.withValues(alpha: 0.55)),
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  reservation.displayGuestName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                _sourceLabel(sourceType, reservation.source),
                style: TextStyle(
                  color: sourceColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(reservation.displayRoomName),
          if (reservation.roomCount > 1) Text('利用客室 ${reservation.roomCount}室'),
          Text(reservation.displayStayPeriod),
          Text('${reservation.displayGuestCount}・${reservation.displayPrice}'),
          if (reservation.reservationNumber != null)
            Text('予約番号 ${reservation.reservationNumber}'),
          if (reservation.phone != null) Text('電話 ${reservation.phone}'),
          if (reservation.specialRequests != null)
            Text('メモ ${reservation.specialRequests}'),
          if (reservation.hasBreakfast != null || reservation.hasDinner != null)
            Text(
              '食事　朝食：${reservation.hasBreakfast == true ? 'あり${reservation.breakfastGuestCount == null ? '' : '（${reservation.breakfastGuestCount}人分）'}' : 'なし'}　'
              '夕食：${reservation.hasDinner == true ? 'あり' : 'なし'}',
            ),
          if (reservation.hasBreakfast == null && reservation.hasDinner == null)
            const Text('食事　未設定'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => onEditMeals(reservation),
                icon: const Icon(Icons.restaurant_menu),
                label: const Text('食事を訂正'),
              ),
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
          if (isManual) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => onEditManual(reservation),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('編集'),
                ),
                TextButton.icon(
                  onPressed: () => onCancelManual(reservation),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('キャンセル'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label),
      ],
    );
  }
}

class _Weekday extends StatelessWidget {
  const _Weekday(this.label, {this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }
}

String _sourceType(String source) {
  final normalized = source.trim().toLowerCase();
  if (normalized == 'manual') return 'manual';
  if (normalized == 'chillnn') return 'chillnn';
  if (normalized.contains('rakuten') || normalized.contains('楽天')) {
    return 'rakuten';
  }
  if (normalized.contains('jalan') || normalized.contains('じゃらん')) {
    return 'jalan';
  }
  if (normalized.contains('booking')) return 'booking';
  return 'other';
}

Color _sourceColor(String sourceType) {
  switch (sourceType) {
    case 'manual':
      return const Color(0xFFEF6C00);
    case 'chillnn':
      return const Color(0xFF386641);
    case 'rakuten':
      return const Color(0xFFBF0000);
    case 'jalan':
      return const Color(0xFFE91E63);
    case 'booking':
      return const Color(0xFF1565C0);
    default:
      return const Color(0xFF546E7A);
  }
}

String _sourceLabel(String sourceType, String original) {
  switch (sourceType) {
    case 'manual':
      return '直接予約';
    case 'rakuten':
      return '楽天トラベル';
    case 'jalan':
      return 'じゃらん';
    default:
      return original;
  }
}

List<DateTime> _calendarDays(DateTime month) {
  final first = DateTime(month.year, month.month, 1);
  final last = DateTime(month.year, month.month + 1, 0);
  final gridStart = first.subtract(Duration(days: first.weekday % 7));
  final daysAfterSaturday = 6 - (last.weekday % 7);
  final gridEnd = last.add(Duration(days: daysAfterSaturday));
  final length = gridEnd.difference(gridStart).inDays + 1;

  return List.generate(length, (index) => gridStart.add(Duration(days: index)));
}

bool _staysOn(Reservation reservation, DateTime date) {
  final checkIn = reservation.checkIn;
  final checkOut = reservation.checkOut;
  if (checkIn == null || checkOut == null) {
    return false;
  }

  final target = DateTime(date.year, date.month, date.day);
  final start = DateTime(checkIn.year, checkIn.month, checkIn.day);
  final end = DateTime(checkOut.year, checkOut.month, checkOut.day);
  return !target.isBefore(start) && target.isBefore(end);
}

bool _checksInDuringMonth(Reservation reservation, DateTime month) {
  final checkIn = reservation.checkIn;
  return checkIn != null &&
      checkIn.year == month.year &&
      checkIn.month == month.month;
}

bool _checksInOn(Reservation reservation, DateTime date) {
  final checkIn = reservation.checkIn;
  return checkIn != null && _sameDay(checkIn, date);
}

bool _isCancelled(Reservation reservation) {
  final status = reservation.status?.trim().toLowerCase();
  return status == 'cancelled' || status == 'canceled' || status == 'キャンセル';
}

int _salesTotal(Iterable<Reservation> reservations) {
  return reservations.fold<int>(
    0,
    (sum, reservation) => sum + (reservation.priceYen ?? 0),
  );
}

String _formatYen(int value) {
  final negative = value < 0;
  final digits = value.abs().toString();
  final buffer = StringBuffer();

  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[index]);
  }

  return '${negative ? '-' : ''}¥$buffer';
}

int _guestCount(Reservation reservation) {
  return reservation.totalGuests ??
      (reservation.adults ?? 0) + reservation.children;
}

bool _sameDay(DateTime first, DateTime second) {
  return first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;
}
