import 'package:flutter/material.dart';

import '../models/reservation.dart';
import '../repositories/database_reservation_repository.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('予約カレンダー'),
        actions: [
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
  });

  final DateTime visibleMonth;
  final DateTime selectedDate;
  final List<Reservation> reservations;
  final ValueChanged<DateTime> onDateSelected;

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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${visibleMonth.year}年 ${visibleMonth.month}月',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                const _LegendDot(color: Color(0xFF386641), label: 'CHILLNN'),
                const SizedBox(width: 14),
                const _LegendDot(
                  color: Color(0xFF1565C0),
                  label: 'Booking.com',
                ),
              ],
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
                childAspectRatio: 1.15,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: days.length,
              itemBuilder: (context, index) {
                final date = days[index];
                final dayReservations = reservations
                    .where((reservation) => _staysOn(reservation, date))
                    .toList(growable: false);
                return _CalendarDay(
                  date: date,
                  inVisibleMonth: date.month == visibleMonth.month,
                  selected: _sameDay(date, selectedDate),
                  reservations: dayReservations,
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

class _CalendarDay extends StatelessWidget {
  const _CalendarDay({
    required this.date,
    required this.inVisibleMonth,
    required this.selected,
    required this.reservations,
    required this.onTap,
  });

  final DateTime date;
  final bool inVisibleMonth;
  final bool selected;
  final List<Reservation> reservations;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final chillnnCount = reservations
        .where((reservation) => reservation.source.toUpperCase() == 'CHILLNN')
        .length;
    final bookingCount = reservations.length - chillnnCount;

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
            Text(
              '${date.day}',
              style: TextStyle(
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: inVisibleMonth
                    ? colorScheme.onSurface
                    : colorScheme.onSurfaceVariant,
              ),
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

class _SelectedDateReservations extends StatelessWidget {
  const _SelectedDateReservations({
    required this.selectedDate,
    required this.reservations,
  });

  final DateTime selectedDate;
  final List<Reservation> reservations;

  @override
  Widget build(BuildContext context) {
    final totalGuests = reservations.fold<int>(0, (sum, reservation) {
      final count =
          reservation.totalGuests ??
          (reservation.adults ?? 0) + reservation.children;
      return sum + count;
    });

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
            Text('${reservations.length}室・$totalGuests名'),
            const Divider(height: 28),
            if (reservations.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: Text('この日の宿泊予約はありません。')),
              )
            else
              ...reservations.map(
                (reservation) => _ReservationTile(reservation: reservation),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReservationTile extends StatelessWidget {
  const _ReservationTile({required this.reservation});

  final Reservation reservation;

  @override
  Widget build(BuildContext context) {
    final isChillnn = reservation.source.toUpperCase() == 'CHILLNN';
    final sourceColor = isChillnn
        ? const Color(0xFF386641)
        : const Color(0xFF1565C0);

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
                reservation.source,
                style: TextStyle(
                  color: sourceColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(reservation.displayRoomName),
          Text(reservation.displayStayPeriod),
          Text('${reservation.displayGuestCount}・${reservation.displayPrice}'),
          if (reservation.reservationNumber != null)
            Text('予約番号 ${reservation.reservationNumber}'),
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

bool _sameDay(DateTime first, DateTime second) {
  return first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;
}
