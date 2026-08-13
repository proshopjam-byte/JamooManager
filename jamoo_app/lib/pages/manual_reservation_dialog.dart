import 'package:flutter/material.dart';

import '../models/reservation.dart';

class ManualReservationFormData {
  const ManualReservationFormData({
    required this.guestName,
    required this.checkIn,
    required this.checkOut,
    required this.roomName,
    required this.adults,
    required this.children,
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
  final int children;
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
}) {
  return showDialog<ManualReservationFormData>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _ManualReservationDialog(
      initialDate: initialDate,
      reservation: reservation,
    ),
  );
}

class _ManualReservationDialog extends StatefulWidget {
  const _ManualReservationDialog({required this.initialDate, this.reservation});

  final DateTime initialDate;
  final Reservation? reservation;

  @override
  State<_ManualReservationDialog> createState() =>
      _ManualReservationDialogState();
}

class _ManualReservationDialogState extends State<_ManualReservationDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _guestController;
  late final TextEditingController _roomController;
  late final TextEditingController _adultsController;
  late final TextEditingController _childrenController;
  late final TextEditingController _priceController;
  late final TextEditingController _phoneController;
  late final TextEditingController _postalCodeController;
  late final TextEditingController _addressController;
  late final TextEditingController _notesController;
  late DateTime _checkIn;
  late DateTime _checkOut;
  late bool _hasBreakfast;
  late bool _hasDinner;

  @override
  void initState() {
    super.initState();
    final reservation = widget.reservation;
    _checkIn = reservation?.checkIn ?? widget.initialDate;
    _checkOut = reservation?.checkOut ?? _checkIn.add(const Duration(days: 1));
    _guestController = TextEditingController(
      text: reservation?.guestName ?? '',
    );
    _roomController = TextEditingController(text: reservation?.roomName ?? '');
    _adultsController = TextEditingController(
      text: '${reservation?.adults ?? 1}',
    );
    _childrenController = TextEditingController(
      text: '${reservation?.children ?? 0}',
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
    _hasBreakfast = reservation?.hasBreakfast ?? false;
    _hasDinner = reservation?.hasDinner ?? false;
  }

  @override
  void dispose() {
    _guestController.dispose();
    _roomController.dispose();
    _adultsController.dispose();
    _childrenController.dispose();
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
    Navigator.of(context).pop(
      ManualReservationFormData(
        guestName: _guestController.text.trim(),
        checkIn: _checkIn,
        checkOut: _checkOut,
        roomName: _roomController.text.trim(),
        adults: int.parse(_adultsController.text),
        children: int.parse(_childrenController.text),
        priceYen: int.tryParse(_priceController.text.replaceAll(',', '')),
        phone: _emptyToNull(_phoneController.text),
        address: _emptyToNull(_addressController.text),
        postalCode: _emptyToNull(_postalCodeController.text),
        notes: _emptyToNull(_notesController.text),
        hasBreakfast: _hasBreakfast,
        hasDinner: _hasDinner,
      ),
    );
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
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      CheckboxListTile(
                        value: _hasBreakfast,
                        onChanged: (value) {
                          setState(() => _hasBreakfast = value ?? false);
                        },
                        secondary: const Icon(Icons.free_breakfast_outlined),
                        title: const Text('朝食あり'),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      CheckboxListTile(
                        value: _hasDinner,
                        onChanged: (value) {
                          setState(() => _hasDinner = value ?? false);
                        },
                        secondary: const Icon(Icons.dinner_dining_outlined),
                        title: const Text('夕食あり'),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ],
                  ),
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
                const SizedBox(height: 12),
                TextFormField(
                  controller: _roomController,
                  decoration: const InputDecoration(labelText: '部屋名 *'),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _numberField(_adultsController, '大人 *')),
                    const SizedBox(width: 10),
                    Expanded(child: _numberField(_childrenController, '子供 *')),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _priceController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '金額（円）'),
                        validator: _optionalNumber,
                      ),
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
