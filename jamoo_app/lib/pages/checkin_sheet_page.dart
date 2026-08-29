import 'package:flutter/material.dart';

import '../models/checkin_sheet.dart';
import '../models/facility_settings.dart';
import '../models/reservation.dart';
import '../pages/facility_settings_page.dart';
import '../repositories/checkin_sheet_repository.dart';
import '../repositories/database_reservation_repository.dart';
import '../repositories/facility_settings_repository.dart';
import '../services/checkin_sheet_print_service.dart';
import '../services/room_assignment_service.dart';

class CheckinSheetPage extends StatefulWidget {
  const CheckinSheetPage({super.key, required this.date});

  final DateTime date;

  @override
  State<CheckinSheetPage> createState() => _CheckinSheetPageState();
}

class _CheckinSheetPageState extends State<CheckinSheetPage> {
  static const _sheetRepository = CheckinSheetRepository();
  static const _reservationRepository = DatabaseReservationRepository();
  static const _facilitySettingsRepository = FacilitySettingsRepository();
  static const _printService = CheckinSheetPrintService();

  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();

  List<Reservation> _reservations = const [];
  List<CheckinSheetRow> _rows = const [];
  List<String> _warnings = const [];
  FacilitySettings _facilitySettings = FacilitySettings.defaults;
  late RoomAssignmentService _assignmentService;
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  Object? _error;
  int _editorGeneration = 0;

  @override
  void initState() {
    super.initState();
    _assignmentService = RoomAssignmentService(
      rooms: FacilitySettings.defaults.rooms,
      stayDate: widget.date,
    );
    _load();
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final facilitySettings = await _facilitySettingsRepository.load();
      final assignmentService = RoomAssignmentService(
        rooms: facilitySettings.rooms,
        stayDate: widget.date,
      );
      final data = await _reservationRepository.loadStaysForDate(widget.date);
      final savedRows = await _sheetRepository.load(
        widget.date,
        rooms: facilitySettings.rooms,
      );
      final previousRows = await _sheetRepository.load(
        widget.date.subtract(const Duration(days: 1)),
        rooms: facilitySettings.rooms,
      );
      final hasSavedAssignment = savedRows.any((row) => row.hasReservation);
      final hasPreviousAssignment = previousRows.any(
        (row) => row.hasReservation,
      );
      final result = hasSavedAssignment || hasPreviousAssignment
          ? assignmentService.reconcileWithCarryForward(
              savedRows,
              previousRows,
              data.reservations,
            )
          : assignmentService.create(data.reservations);

      if (!mounted) {
        return;
      }
      setState(() {
        _facilitySettings = facilitySettings;
        _assignmentService = assignmentService;
        _reservations = data.reservations;
        _rows = result.rows;
        _warnings = result.warnings;
        _dirty = !hasSavedAssignment && data.reservations.isNotEmpty;
        _loading = false;
        _editorGeneration++;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<bool> _save({bool showMessage = true}) async {
    if (_saving) {
      return false;
    }
    setState(() {
      _saving = true;
    });
    try {
      await _sheetRepository.save(widget.date, _rows);
      final warnings = _assignmentService.validate(_rows, _reservations);
      if (!mounted) {
        return true;
      }
      setState(() {
        _warnings = warnings;
        _dirty = false;
        _saving = false;
      });
      if (showMessage) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('部屋割りとチェックインシートを保存しました。')));
      }
      return true;
    } catch (error) {
      if (!mounted) {
        return false;
      }
      setState(() {
        _saving = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存できませんでした: $error')));
      return false;
    }
  }

  Future<void> _autoAssign() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('自動部屋割りをやり直しますか？'),
        content: const Text(
          '現在の部屋割りと人数を、予約情報を基に作り直します。'
          '入力済みの時間・備考も初期化されます。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('自動配室する'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final result = _assignmentService.create(_reservations);
    setState(() {
      _rows = result.rows;
      _warnings = result.warnings;
      _dirty = true;
      _editorGeneration++;
    });
  }

  Future<void> _preview() async {
    final saved = await _save(showMessage: false);
    if (!saved || !mounted) {
      return;
    }
    try {
      await _printService.preview(
        context,
        date: widget.date,
        rows: _rows,
        facilitySettings: _facilitySettings,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('PDFを作成できませんでした: $error')));
    }
  }

  Future<void> _openFacilitySettings() async {
    if (_dirty) {
      final saved = await _save(showMessage: false);
      if (!saved || !mounted) {
        return;
      }
    }

    final updated = await Navigator.of(context).push<FacilitySettings>(
      MaterialPageRoute(
        builder: (context) =>
            FacilitySettingsPage(initialSettings: _facilitySettings),
      ),
    );
    if (!mounted || updated == null) {
      return;
    }

    await _load();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('施設・客室設定を反映しました。')));
    }
  }

  void _changeReservation(int index, String key) {
    if (key.isEmpty) {
      setState(() {
        _rows = List<CheckinSheetRow>.from(_rows)
          ..[index] = CheckinSheetRow.empty(_rows[index].roomNumber);
        _warnings = _assignmentService.validate(_rows, _reservations);
        _dirty = true;
        _editorGeneration++;
      });
      return;
    }

    final reservation = _reservations.firstWhere(
      (item) => RoomAssignmentService.reservationKey(item) == key,
    );
    final assignedElsewhere = _rows
        .asMap()
        .entries
        .where(
          (entry) => entry.key != index && entry.value.reservationKey == key,
        )
        .fold<int>(0, (sum, entry) => sum + entry.value.guestCount);
    final remaining =
        RoomAssignmentService.guestCount(reservation) - assignedElsewhere;
    final room = _facilitySettings.roomByNumber(_rows[index].roomNumber);
    final count = remaining <= 0
        ? 1
        : remaining > room.capacity
        ? room.capacity
        : remaining;
    final includeDetails = !_rows.asMap().entries.any(
      (entry) => entry.key != index && entry.value.reservationKey == key,
    );
    final replacement = _assignmentService.assignReservation(
      roomNumber: room.number,
      reservation: reservation,
      guestCount: count,
      includeBookingDetails: includeDetails,
    );

    setState(() {
      _rows = List<CheckinSheetRow>.from(_rows)..[index] = replacement;
      _warnings = _assignmentService.validate(_rows, _reservations);
      _dirty = true;
      _editorGeneration++;
    });
  }

  void _replaceRow(int index, CheckinSheetRow row, {bool rebuild = false}) {
    _rows = List<CheckinSheetRow>.from(_rows)..[index] = row;
    _dirty = true;
    if (rebuild) {
      setState(() {
        _warnings = _assignmentService.validate(_rows, _reservations);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${_formatDate(widget.date)} チェックインシート'),
        actions: [
          OutlinedButton.icon(
            onPressed: _loading || _saving ? null : _autoAssign,
            icon: const Icon(Icons.auto_awesome_outlined),
            label: const Text('自動部屋割り'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _loading || _saving ? null : () => _save(),
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_dirty ? '保存' : '保存済み'),
          ),
          IconButton(
            tooltip: 'A4横PDFをプレビュー・印刷',
            onPressed: _loading || _saving ? null : _preview,
            icon: const Icon(Icons.print_outlined),
          ),
          IconButton(
            tooltip: '施設・客室設定',
            onPressed: _loading || _saving ? null : _openFacilitySettings,
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            tooltip: '再読込',
            onPressed: _loading || _saving ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 44),
              const SizedBox(height: 12),
              Text('チェックインシートを開けませんでした\n$_error'),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('再試行')),
            ],
          ),
        ),
      );
    }

    final totalGuests = _rows.fold<int>(0, (sum, row) => sum + row.guestCount);
    final totalAmount = _rows.fold<int>(
      0,
      (sum, row) => sum + (row.amountYen ?? 0),
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: [
              _SummaryCard(label: '予約', value: '${_reservations.length}件'),
              const SizedBox(width: 10),
              _SummaryCard(label: '配室人数', value: '$totalGuests名'),
              const SizedBox(width: 10),
              _SummaryCard(label: '精算合計', value: _formatYen(totalAmount)),
              const SizedBox(width: 16),
              Expanded(child: Text(_facilitySettings.capacitySummary)),
            ],
          ),
        ),
        if (_warnings.isNotEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(_warnings.map((warning) => '・$warning').join('\n')),
          ),
        Expanded(
          child: Scrollbar(
            controller: _verticalController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _verticalController,
              child: Scrollbar(
                controller: _horizontalController,
                thumbVisibility: true,
                notificationPredicate: (notification) =>
                    notification.metrics.axis == Axis.horizontal,
                child: SingleChildScrollView(
                  controller: _horizontalController,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 22),
                  child: _buildTable(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTable() {
    return DataTable(
      headingRowHeight: 54,
      dataRowMinHeight: 78,
      dataRowMaxHeight: 88,
      columnSpacing: 10,
      horizontalMargin: 8,
      columns: const [
        DataColumn(label: Text('部屋')),
        DataColumn(label: Text('お名前・予約')),
        DataColumn(label: Text('人数')),
        DataColumn(label: Text('CI')),
        DataColumn(label: Text('精算金額')),
        DataColumn(label: Text('決済')),
        DataColumn(label: Text('夕食時間・テーブル')),
        DataColumn(label: Text('入浴時間')),
        DataColumn(label: Text('朝食時間')),
        DataColumn(label: Text('CO')),
        DataColumn(label: Text('備考')),
      ],
      rows: [
        for (var index = 0; index < _rows.length; index++) _buildDataRow(index),
      ],
    );
  }

  DataRow _buildDataRow(int index) {
    final row = _rows[index];
    final room = _facilitySettings.roomByNumber(row.roomNumber);
    final unavailable = !room.isAvailable;
    final editable = !unavailable && row.hasReservation;
    final reservationKeys = _reservations
        .map(RoomAssignmentService.reservationKey)
        .toSet();
    final currentKey = reservationKeys.contains(row.reservationKey)
        ? row.reservationKey ?? ''
        : '';
    final guestMaximum = row.guestCount > room.capacity
        ? row.guestCount
        : room.capacity;

    return DataRow(
      color: unavailable
          ? WidgetStatePropertyAll(
              Theme.of(context).colorScheme.surfaceContainerHighest,
            )
          : null,
      cells: [
        DataCell(
          SizedBox(
            width: 92,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  room.displayName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(room.typeLabel, style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
        ),
        DataCell(
          SizedBox(
            width: 230,
            child: unavailable
                ? const Text('使用不可')
                : DropdownButtonFormField<String>(
                    key: ValueKey(
                      'reservation-$_editorGeneration-${row.roomNumber}',
                    ),
                    initialValue: currentKey,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('未設定')),
                      for (final reservation in _reservations)
                        DropdownMenuItem(
                          value: RoomAssignmentService.reservationKey(
                            reservation,
                          ),
                          child: Text(
                            '${reservation.displayGuestName} '
                            '(${RoomAssignmentService.guestCount(reservation)}名)',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) =>
                        _changeReservation(index, value ?? ''),
                  ),
          ),
        ),
        DataCell(
          SizedBox(
            width: 76,
            child: !editable
                ? const SizedBox.shrink()
                : DropdownButtonFormField<int>(
                    key: ValueKey(
                      'guests-$_editorGeneration-${row.roomNumber}',
                    ),
                    initialValue: row.guestCount,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (var count = 0; count <= guestMaximum; count++)
                        DropdownMenuItem(value: count, child: Text('$count')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        _replaceRow(
                          index,
                          row.copyWith(guestCount: value),
                          rebuild: true,
                        );
                      }
                    },
                  ),
          ),
        ),
        DataCell(
          Checkbox(
            value: row.checkedIn,
            onChanged: !editable
                ? null
                : (value) => _replaceRow(
                    index,
                    row.copyWith(checkedIn: value ?? false),
                    rebuild: true,
                  ),
          ),
        ),
        DataCell(
          _textField(
            key: 'amount-$_editorGeneration-${row.roomNumber}',
            width: 90,
            initialValue: row.amountYen?.toString() ?? '',
            enabled: editable,
            keyboardType: TextInputType.number,
            onChanged: (value) {
              final amount = int.tryParse(value.replaceAll(',', '').trim());
              _replaceRow(
                index,
                row.copyWith(amountYen: amount, clearAmount: amount == null),
              );
            },
          ),
        ),
        DataCell(
          _textField(
            key: 'payment-$_editorGeneration-${row.roomNumber}',
            width: 76,
            initialValue: row.payment,
            enabled: editable,
            onChanged: (value) =>
                _replaceRow(index, row.copyWith(payment: value)),
          ),
        ),
        DataCell(
          _textField(
            key: 'dinner-$_editorGeneration-${row.roomNumber}',
            width: 125,
            initialValue: row.dinnerAndTable,
            enabled: editable,
            onChanged: (value) =>
                _replaceRow(index, row.copyWith(dinnerAndTable: value)),
          ),
        ),
        DataCell(
          _textField(
            key: 'bath-$_editorGeneration-${row.roomNumber}',
            width: 86,
            initialValue: row.bathTime,
            enabled: editable,
            onChanged: (value) =>
                _replaceRow(index, row.copyWith(bathTime: value)),
          ),
        ),
        DataCell(
          _textField(
            key: 'breakfast-$_editorGeneration-${row.roomNumber}',
            width: 86,
            initialValue: row.breakfastTime,
            enabled: editable,
            onChanged: (value) =>
                _replaceRow(index, row.copyWith(breakfastTime: value)),
          ),
        ),
        DataCell(
          Checkbox(
            value: row.checkedOut,
            onChanged: !editable
                ? null
                : (value) => _replaceRow(
                    index,
                    row.copyWith(checkedOut: value ?? false),
                    rebuild: true,
                  ),
          ),
        ),
        DataCell(
          _textField(
            key: 'notes-$_editorGeneration-${row.roomNumber}',
            width: 190,
            initialValue: row.notes,
            enabled: editable,
            maxLines: 2,
            onChanged: (value) =>
                _replaceRow(index, row.copyWith(notes: value)),
          ),
        ),
      ],
    );
  }

  static Widget _textField({
    required String key,
    required double width,
    required String initialValue,
    required bool enabled,
    required ValueChanged<String> onChanged,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return SizedBox(
      width: width,
      child: TextFormField(
        key: ValueKey(key),
        initialValue: initialValue,
        enabled: enabled,
        keyboardType: keyboardType,
        maxLines: maxLines,
        decoration: const InputDecoration(
          isDense: true,
          border: OutlineInputBorder(),
        ),
        onChanged: onChanged,
      ),
    );
  }

  static String _formatDate(DateTime value) {
    return '${value.year}/${value.month.toString().padLeft(2, '0')}/'
        '${value.day.toString().padLeft(2, '0')}';
  }

  static String _formatYen(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(digits[index]);
    }
    return '¥$buffer';
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
