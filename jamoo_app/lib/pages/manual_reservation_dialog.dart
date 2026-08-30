import 'package:flutter/material.dart';

import '../models/facility_settings.dart';
import '../models/reservation.dart';
import '../repositories/facility_settings_repository.dart';
import '../widgets/postal_code_lookup_button.dart';

class ManualReservationFormData {
  const ManualReservationFormData({
    required this.guestName,
    required this.checkIn,
    required this.checkOut,
    required this.roomName,
    required this.adults,
    required this.childrenWithBed,
    required this.childrenWithoutBed,
    required this.dailyGuestCounts,
    required this.priceYen,
    required this.phone,
    required this.address,
    required this.postalCode,
    required this.notes,
    required this.hasBreakfast,
    required this.hasDinner,
  });

  final String guestName;
  final DateTime checkIn;
  final DateTime checkOut;
  final String roomName;
  final int adults;
  final int childrenWithBed;
  final int childrenWithoutBed;
  final List<ReservationDailyGuestCount> dailyGuestCounts;
  int get children => childrenWithBed + childrenWithoutBed;
  final int? priceYen;
  final String? phone;
  final String? address;
  final String? postalCode;
  final String? notes;
  final bool hasBreakfast;
  final bool hasDinner;
}

class MealSettingsData {
  const MealSettingsData({required this.hasBreakfast, required this.hasDinner});

  final bool hasBreakfast;
  final bool hasDinner;
}

Future<MealSettingsData?> showMealSettingsDialog(
  BuildContext context, {
  required Reservation reservation,
}) {
  var hasBreakfast = reservation.hasBreakfast ?? false;
  var hasDinner = reservation.hasDinner ?? false;

  return showDialog<MealSettingsData>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('食事の有無を訂正'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                reservation.displayGuestName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(reservation.displayStayPeriod),
              const SizedBox(height: 14),
              CheckboxListTile(
                value: hasBreakfast,
                onChanged: (value) {
                  setDialogState(() => hasBreakfast = value ?? false);
                },
                title: const Text('朝食あり'),
                secondary: const Icon(Icons.free_breakfast_outlined),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              CheckboxListTile(
                value: hasDinner,
                onChanged: (value) {
                  setDialogState(() => hasDinner = value ?? false);
                },
                title: const Text('夕食あり'),
                secondary: const Icon(Icons.dinner_dining_outlined),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('戻る'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(
              MealSettingsData(
                hasBreakfast: hasBreakfast,
                hasDinner: hasDinner,
              ),
            ),
            icon: const Icon(Icons.save_outlined),
            label: const Text('保存'),
          ),
        ],
      ),
    ),
  );
}

Future<ManualReservationFormData?> showManualReservationDialog(
  BuildContext context, {
  required DateTime initialDate,
  Reservation? reservation,
}) async {
  FacilitySettings settings;
  try {
    settings = await const FacilitySettingsRepository().load();
  } catch (_) {
    settings = FacilitySettings.defaults;
  }
  if (!context.mounted) return null;
  return showDialog<ManualReservationFormData>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _ManualReservationDialog(
      initialDate: initialDate,
      reservation: reservation,
      settings: settings,
    ),
  );
}

class _ManualReservationDialog extends StatefulWidget {
  const _ManualReservationDialog({
    required this.initialDate,
    required this.settings,
    this.reservation,
  });

  final DateTime initialDate;
  final FacilitySettings settings;
  final Reservation? reservation;

  @override
  State<_ManualReservationDialog> createState() =>
      _ManualReservationDialogState();
}

class _ManualReservationDialogState extends State<_ManualReservationDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _guestController;
  late final TextEditingController _adultsController;
  late final TextEditingController _childrenWithBedController;
  late final TextEditingController _childrenWithoutBedController;
  late final TextEditingController _priceController;
  late final TextEditingController _phoneController;
  late final TextEditingController _postalCodeController;
  late final TextEditingController _addressController;
  late final TextEditingController _notesController;
  late DateTime _checkIn;
  late DateTime _checkOut;
  late String _selectedRoomType;
  late StayPlan _stayPlan;
  late List<ReservationDailyGuestCount> _dailyGuestCounts;

  @override
  void initState() {
    super.initState();
    final reservation = widget.reservation;
    _checkIn = reservation?.checkIn ?? widget.initialDate;
    _checkOut = reservation?.checkOut ?? _checkIn.add(const Duration(days: 1));
    _guestController = TextEditingController(
      text: reservation?.guestName ?? '',
    );
    final existingRoom = reservation?.roomName?.trim() ?? '';
    final roomTypes = widget.settings.availableRoomTypeNames;
    _selectedRoomType = existingRoom.isNotEmpty
        ? existingRoom
        : roomTypes.isNotEmpty
        ? roomTypes.first
        : 'その他';
    _adultsController = TextEditingController(
      text: '${reservation?.adults ?? 1}',
    );
    final knownChildrenWithBed = reservation?.childrenWithBed;
    final knownChildrenWithoutBed = reservation?.childrenWithoutBed;
    _childrenWithBedController = TextEditingController(
      text: '${knownChildrenWithBed ?? reservation?.children ?? 0}',
    );
    _childrenWithoutBedController = TextEditingController(
      text: '${knownChildrenWithoutBed ?? 0}',
    );
    _priceController = TextEditingController(
      text: reservation?.priceYen?.toString() ?? '',
    );
    _phoneController = TextEditingController(text: reservation?.phone ?? '');
    _postalCodeController = TextEditingController(
      text: reservation?.postalCode ?? '',
    );
    _addressController = TextEditingController(
      text: reservation?.address ?? '',
    );
    _notesController = TextEditingController(
      text: reservation?.specialRequests ?? '',
    );
    _stayPlan = reservation?.hasDinner == true
        ? StayPlan.twoMeals
        : reservation?.hasBreakfast == true
        ? StayPlan.breakfast
        : StayPlan.roomOnly;
    _dailyGuestCounts = List<ReservationDailyGuestCount>.from(
      reservation?.dailyGuestCounts ?? const [],
    );
  }

  @override
  void dispose() {
    _guestController.dispose();
    _adultsController.dispose();
    _childrenWithBedController.dispose();
    _childrenWithoutBedController.dispose();
    _priceController.dispose();
    _phoneController.dispose();
    _postalCodeController.dispose();
    _addressController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool checkIn}) async {
    final current = checkIn ? _checkIn : _checkOut;
    final selected = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (selected == null) return;
    setState(() {
      if (checkIn) {
        _checkIn = selected;
        if (!_checkOut.isAfter(_checkIn)) {
          _checkOut = _checkIn.add(const Duration(days: 1));
        }
      } else {
        _checkOut = selected;
      }
      _dailyGuestCounts = _dailyGuestCounts
          .where(
            (value) =>
                !value.date.isBefore(_checkIn) &&
                value.date.isBefore(_checkOut),
          )
          .toList(growable: false);
    });
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (!_checkOut.isAfter(_checkIn)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('チェックアウトはチェックインより後にしてください。')),
      );
      return;
    }
    final adults = int.parse(_adultsController.text);
    final childrenWithBed = int.parse(_childrenWithBedController.text);
    final childrenWithoutBed = int.parse(_childrenWithoutBedController.text);
    final guests = adults + childrenWithBed + childrenWithoutBed;
    if (guests <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('人数は1名以上にしてください。')));
      return;
    }
    if (!_validateRoomOccupancy(guests)) return;
    final dailyGuestCounts = _normalizedDailyGuestCounts();
    for (final daily in dailyGuestCounts) {
      if (daily.totalGuests <= 0) {
        _showMessage('${_formatDate(daily.date)}の人数は1名以上にしてください。');
        return;
      }
      if (!_validateRoomOccupancy(daily.totalGuests)) return;
    }
    Navigator.of(context).pop(
      ManualReservationFormData(
        guestName: _guestController.text.trim(),
        checkIn: _checkIn,
        checkOut: _checkOut,
        roomName: _selectedRoomType,
        adults: adults,
        childrenWithBed: childrenWithBed,
        childrenWithoutBed: childrenWithoutBed,
        dailyGuestCounts: dailyGuestCounts,
        priceYen: int.tryParse(_priceController.text.replaceAll(',', '')),
        phone: _emptyToNull(_phoneController.text),
        address: _emptyToNull(_addressController.text),
        postalCode: _emptyToNull(_postalCodeController.text),
        notes: _emptyToNull(_notesController.text),
        hasBreakfast: _stayPlan != StayPlan.roomOnly,
        hasDinner: _stayPlan == StayPlan.twoMeals,
      ),
    );
  }

  void _calculatePrice() {
    final adults = int.tryParse(_adultsController.text.trim()) ?? 0;
    final childrenWithBed =
        int.tryParse(_childrenWithBedController.text.trim()) ?? 0;
    final childrenWithoutBed =
        int.tryParse(_childrenWithoutBedController.text.trim()) ?? 0;
    final guests = adults + childrenWithBed + childrenWithoutBed;
    if (guests <= 0) {
      _showMessage('先に人数を入力してください。');
      return;
    }
    if (!_validateRoomOccupancy(guests)) return;
    final nights = _checkOut.difference(_checkIn).inDays;
    if (nights <= 0) {
      _showMessage('先に宿泊日を確認してください。');
      return;
    }
    var total = 0;
    final daily = _normalizedDailyGuestCounts();
    if (daily.isNotEmpty) {
      for (final guestsForDate in daily) {
        final nightlyRate = widget.settings.calculateNightlyRate(
          roomTypeName: _selectedRoomType,
          adults: guestsForDate.adults,
          childrenWithBed: guestsForDate.childrenWithBed,
          childrenWithoutBed: guestsForDate.childrenWithoutBed,
          plan: _stayPlan,
        );
        if (nightlyRate == null) {
          _showMessage('${_formatDate(guestsForDate.date)}の料金が未設定です。');
          return;
        }
        total += nightlyRate;
      }
    } else {
      final nightlyRate = widget.settings.calculateNightlyRate(
        roomTypeName: _selectedRoomType,
        adults: adults,
        childrenWithBed: childrenWithBed,
        childrenWithoutBed: childrenWithoutBed,
        plan: _stayPlan,
      );
      if (nightlyRate == null) {
        _showMessage('この人数内訳・プランの料金が未設定です。');
        return;
      }
      total = nightlyRate * nights;
    }
    setState(() => _priceController.text = '$total');
    _showMessage(
      daily.isEmpty
          ? '${_stayPlan.label}、$nights泊で計算しました。'
          : '${_stayPlan.label}、日別人数で$nights泊分を計算しました。',
    );
  }

  Future<void> _editDailyGuestCounts() async {
    final nights = _checkOut.difference(_checkIn).inDays;
    if (nights <= 1) {
      _showMessage('日別人数は2泊以上の予約で設定できます。');
      return;
    }
    final baseAdults = int.tryParse(_adultsController.text.trim()) ?? 0;
    final baseChildrenWithBed =
        int.tryParse(_childrenWithBedController.text.trim()) ?? 0;
    final baseChildrenWithoutBed =
        int.tryParse(_childrenWithoutBedController.text.trim()) ?? 0;
    final existingByDate = {
      for (final value in _dailyGuestCounts) _dateKey(value.date): value,
    };
    final editors = <_DailyGuestEditors>[];
    for (var index = 0; index < nights; index++) {
      final date = _checkIn.add(Duration(days: index));
      final existing = existingByDate[_dateKey(date)];
      editors.add(
        _DailyGuestEditors(
          date: date,
          adults: existing?.adults ?? baseAdults,
          childrenWithBed:
              existing?.childrenWithBed ?? baseChildrenWithBed,
          childrenWithoutBed:
              existing?.childrenWithoutBed ?? baseChildrenWithoutBed,
        ),
      );
    }

    final formKey = GlobalKey<FormState>();
    String? errorMessage;
    final result = await showDialog<List<ReservationDailyGuestCount>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('宿泊日ごとの人数'),
          content: SizedBox(
            width: 680,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('人数が変わる日だけ数値を変更してください。'),
                    const SizedBox(height: 12),
                    if (errorMessage != null) ...[
                      Text(
                        errorMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    for (final editor in editors) ...[
                      Row(
                        children: [
                          SizedBox(
                            width: 105,
                            child: Text(
                              _formatDate(editor.date),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _dailyNumberField(
                              editor.adultsController,
                              '大人',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _dailyNumberField(
                              editor.childrenWithBedController,
                              '子ども・ベッドあり',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _dailyNumberField(
                              editor.childrenWithoutBedController,
                              '子ども・ベッドなし',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(
                const <ReservationDailyGuestCount>[],
              ),
              child: const Text('共通人数に戻す'),
            ),
            FilledButton.icon(
              onPressed: () {
                if (formKey.currentState?.validate() != true) return;
                final values = editors
                    .map((editor) => editor.toValue())
                    .toList(growable: false);
                for (final value in values) {
                  if (value.totalGuests <= 0) {
                    setDialogState(() {
                      errorMessage =
                          '${_formatDate(value.date)}の人数は1名以上にしてください。';
                    });
                    return;
                  }
                  final minimum = widget.settings.minimumGuestsFor(
                    _selectedRoomType,
                  );
                  final maximum = widget.settings.maximumGuestsFor(
                    _selectedRoomType,
                  );
                  if (value.totalGuests < minimum ||
                      (maximum > 0 && value.totalGuests > maximum)) {
                    setDialogState(() {
                      errorMessage =
                          '${_formatDate(value.date)}は$_selectedRoomTypeの'
                          '利用人数（$minimum～$maximum名）に収まりません。';
                    });
                    return;
                  }
                }
                Navigator.of(dialogContext).pop(values);
              },
              icon: const Icon(Icons.save_outlined),
              label: const Text('日別人数を反映'),
            ),
          ],
        ),
      ),
    );
    for (final editor in editors) {
      editor.dispose();
    }
    if (result == null || !mounted) return;
    setState(() => _dailyGuestCounts = result);
  }

  List<ReservationDailyGuestCount> _normalizedDailyGuestCounts() {
    if (_dailyGuestCounts.isEmpty) return const [];
    final result = _dailyGuestCounts
        .where(
          (value) =>
              !value.date.isBefore(_checkIn) && value.date.isBefore(_checkOut),
        )
        .toList(growable: false)
      ..sort((first, second) => first.date.compareTo(second.date));
    return result;
  }

  bool _validateRoomOccupancy(int guests) {
    final minimum = widget.settings.minimumGuestsFor(_selectedRoomType);
    final maximum = widget.settings.maximumGuestsFor(_selectedRoomType);
    if (guests < minimum) {
      _showMessage('$_selectedRoomTypeは$minimum名から利用できます。');
      return false;
    }
    if (maximum > 0 && guests > maximum) {
      _showMessage('$_selectedRoomTypeの最大定員は$maximum名です。');
      return false;
    }
    return true;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.reservation == null ? '直接予約を追加' : '直接予約を編集'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _guestController,
                  decoration: const InputDecoration(labelText: 'お客様名 *'),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<StayPlan>(
                  initialValue: _stayPlan,
                  decoration: const InputDecoration(
                    labelText: '宿泊プラン',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final plan in StayPlan.values)
                      DropdownMenuItem(value: plan, child: Text(plan.label)),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _stayPlan = value);
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickDate(checkIn: true),
                        icon: const Icon(Icons.login),
                        label: Text('チェックイン ${_formatDate(_checkIn)}'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickDate(checkIn: false),
                        icon: const Icon(Icons.logout),
                        label: Text('チェックアウト ${_formatDate(_checkOut)}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _checkOut.difference(_checkIn).inDays > 1
                        ? _editDailyGuestCounts
                        : null,
                    icon: const Icon(Icons.people_alt_outlined),
                    label: Text(
                      _dailyGuestCounts.isEmpty
                          ? '連泊の日別人数を設定'
                          : '日別人数を編集（設定済み）',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _selectedRoomType,
                  decoration: const InputDecoration(
                    labelText: '部屋タイプ *',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final roomType in _roomTypeChoices())
                      DropdownMenuItem(value: roomType, child: Text(roomType)),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedRoomType = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _numberField(_adultsController, '大人 *')),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _numberField(
                        _childrenWithBedController,
                        '子ども・ベッドあり',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _numberField(
                        _childrenWithoutBedController,
                        '子ども・ベッドなし',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _priceController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '金額（円）'),
                        validator: _optionalNumber,
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: _calculatePrice,
                      icon: const Icon(Icons.calculate_outlined),
                      label: const Text('設定料金から自動計算'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(labelText: '電話番号'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _postalCodeController,
                  decoration: const InputDecoration(
                    labelText: '郵便番号',
                    hintText: '例：123-4567',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(labelText: '住所'),
                  keyboardType: TextInputType.streetAddress,
                  minLines: 1,
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                PostalCodeLookupButton(
                  addressController: _addressController,
                  postalCodeController: _postalCodeController,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(labelText: 'メモ'),
                  minLines: 2,
                  maxLines: 4,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('保存'),
        ),
      ],
    );
  }

  Widget _numberField(TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
      validator: (value) {
        final number = int.tryParse(value ?? '');
        return number == null || number < 0 ? '0以上を入力' : null;
      },
    );
  }

  Widget _dailyNumberField(
    TextEditingController controller,
    String label,
  ) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      validator: (value) {
        final number = int.tryParse(value ?? '');
        return number == null || number < 0 ? '0以上' : null;
      },
    );
  }

  List<String> _roomTypeChoices() {
    final result = widget.settings.availableRoomTypeNames.toList();
    if (!result.contains(_selectedRoomType)) {
      result.add(_selectedRoomType);
    }
    return result;
  }

  static String? _required(String? value) {
    return value == null || value.trim().isEmpty ? '入力してください' : null;
  }

  static String? _optionalNumber(String? value) {
    final text = value?.replaceAll(',', '').trim() ?? '';
    return text.isNotEmpty && int.tryParse(text) == null ? '数字で入力' : null;
  }

  static String? _emptyToNull(String value) {
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  static String _formatDate(DateTime date) {
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/'
        '${date.day.toString().padLeft(2, '0')}';
  }
}

class _DailyGuestEditors {
  _DailyGuestEditors({
    required this.date,
    required int adults,
    required int childrenWithBed,
    required int childrenWithoutBed,
  }) : adultsController = TextEditingController(text: '$adults'),
       childrenWithBedController = TextEditingController(
         text: '$childrenWithBed',
       ),
       childrenWithoutBedController = TextEditingController(
         text: '$childrenWithoutBed',
       );

  final DateTime date;
  final TextEditingController adultsController;
  final TextEditingController childrenWithBedController;
  final TextEditingController childrenWithoutBedController;

  ReservationDailyGuestCount toValue() {
    return ReservationDailyGuestCount(
      date: date,
      adults: int.parse(adultsController.text),
      childrenWithBed: int.parse(childrenWithBedController.text),
      childrenWithoutBed: int.parse(childrenWithoutBedController.text),
    );
  }

  void dispose() {
    adultsController.dispose();
    childrenWithBedController.dispose();
    childrenWithoutBedController.dispose();
  }
}

String _dateKey(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}
