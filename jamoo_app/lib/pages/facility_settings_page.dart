import 'package:flutter/material.dart';

import '../models/checkin_sheet.dart';
import '../models/facility_settings.dart';
import '../repositories/facility_settings_repository.dart';

class FacilitySettingsPage extends StatefulWidget {
  const FacilitySettingsPage({super.key, required this.initialSettings});

  final FacilitySettings initialSettings;

  @override
  State<FacilitySettingsPage> createState() => _FacilitySettingsPageState();
}

class _FacilitySettingsPageState extends State<FacilitySettingsPage> {
  static const _repository = FacilitySettingsRepository();
  static const _maximumRooms = 15;

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _facilityNameController;
  late final TextEditingController _addressController;
  late final TextEditingController _phoneController;
  late List<_RoomEditor> _rooms;
  late Map<String, _RoomRateEditor> _rateEditors;
  late _PersonRatesEditor _personRatesEditor;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadEditors(widget.initialSettings);
  }

  void _loadEditors(FacilitySettings settings) {
    _facilityNameController = TextEditingController(
      text: settings.facilityName,
    );
    _addressController = TextEditingController(text: settings.address);
    _phoneController = TextEditingController(text: settings.phone);
    _rooms = settings.rooms.map(_RoomEditor.fromRoom).toList();
    _personRatesEditor = _PersonRatesEditor.fromSettings(settings.personRates);
    _rateEditors = {
      for (final rate in settings.roomRates)
        _roomTypeKey(rate.roomTypeName): _RoomRateEditor.fromRate(
          rate,
          defaultMinimumGuests: _defaultMinimumGuests(rate.roomTypeName),
          defaultSingleUseSurchargeYen: _defaultSingleUseSurcharge(
            rate.roomTypeName,
          ),
        ),
    };
  }

  @override
  void dispose() {
    _facilityNameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    for (final room in _rooms) {
      room.dispose();
    }
    for (final rate in _rateEditors.values) {
      rate.dispose();
    }
    _personRatesEditor.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) {
      return;
    }

    final roomNumbers = _rooms
        .map((room) => int.parse(room.numberController.text.trim()))
        .toList();
    if (roomNumbers.toSet().length != roomNumbers.length) {
      _showMessage('同じ部屋番号が複数あります。');
      return;
    }
    if (_rooms.isEmpty) {
      _showMessage('客室を1室以上登録してください。');
      return;
    }
    if (_rooms.length > _maximumRooms) {
      _showMessage('客室は$_maximumRooms室まで登録できます。');
      return;
    }

    final rooms = _rooms.map((editor) => editor.toRoom()).toList()
      ..sort((first, second) => first.number.compareTo(second.number));
    final settings = FacilitySettings(
      facilityName: _facilityNameController.text.trim(),
      address: _addressController.text.trim(),
      phone: _phoneController.text.trim(),
      rooms: List.unmodifiable(rooms),
      roomRates: List.unmodifiable(
        _currentRoomTypes().map((definition) {
          return _rateEditorFor(
            definition.name,
          ).toRate(definition.name, definition.maximumGuests);
        }),
      ),
      personRates: _personRatesEditor.toSettings(),
    );

    setState(() {
      _saving = true;
    });
    try {
      await _repository.save(settings);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(settings);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
      });
      _showMessage('$error');
    }
  }

  void _addRoom() {
    if (_rooms.length >= _maximumRooms) {
      _showMessage('客室は$_maximumRooms室まで追加できます。');
      return;
    }
    final used = _rooms
        .map((room) => int.tryParse(room.numberController.text.trim()) ?? 0)
        .toSet();
    var nextNumber = 1;
    while (used.contains(nextNumber)) {
      nextNumber++;
    }
    setState(() {
      _rooms.add(
        _RoomEditor.fromRoom(
          GuestRoomSpec(
            number: nextNumber,
            label: 'ツイン',
            normalCapacity: 2,
            capacity: 3,
            type: GuestRoomType.standardTwin,
          ),
        ),
      );
    });
  }

  void _removeRoom(int index) {
    final removed = _rooms[index];
    setState(() {
      _rooms.removeAt(index);
    });
    removed.dispose();
  }

  Future<void> _restoreDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ジャムーの初期設定に戻しますか？'),
        content: const Text(
          '施設情報と客室構成を初期状態に戻します。'
          'この画面で「保存」するまでは確定しません。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('初期設定に戻す'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    _facilityNameController.text = FacilitySettings.defaults.facilityName;
    _addressController.text = FacilitySettings.defaults.address;
    _phoneController.text = FacilitySettings.defaults.phone;
    for (final room in _rooms) {
      room.dispose();
    }
    for (final rate in _rateEditors.values) {
      rate.dispose();
    }
    _personRatesEditor.dispose();
    setState(() {
      _rooms = FacilitySettings.defaults.rooms
          .map(_RoomEditor.fromRoom)
          .toList();
      _rateEditors = {
        for (final rate in FacilitySettings.defaults.roomRates)
          _roomTypeKey(rate.roomTypeName): _RoomRateEditor.fromRate(
            rate,
            defaultMinimumGuests: _defaultMinimumGuests(rate.roomTypeName),
            defaultSingleUseSurchargeYen: _defaultSingleUseSurcharge(
              rate.roomTypeName,
            ),
          ),
      };
      _personRatesEditor = _PersonRatesEditor.fromSettings(
        FacilitySettings.defaults.personRates,
      );
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('施設・客室設定'),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _restoreDefaults,
            icon: const Icon(Icons.restart_alt),
            label: const Text('初期設定'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('保存'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          children: [
            Text('施設情報', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 360,
                  child: TextFormField(
                    controller: _facilityNameController,
                    decoration: const InputDecoration(
                      labelText: '施設名',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                        value?.trim().isEmpty == true ? '施設名を入力してください' : null,
                  ),
                ),
                SizedBox(
                  width: 250,
                  child: TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(
                      labelText: '電話番号',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(
                  width: 520,
                  child: TextFormField(
                    controller: _addressController,
                    decoration: const InputDecoration(
                      labelText: '住所',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '客室設定',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _saving || _rooms.length >= _maximumRooms
                      ? null
                      : _addRoom,
                  icon: const Icon(Icons.add),
                  label: Text('客室を追加（${_rooms.length}/$_maximumRooms）'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              '小規模施設向けに最大15室まで登録できます。'
              '部屋タイプ名は自由入力でき、客室ごとに人数を設定できます。'
              '通常人数は自動部屋割りで使う人数、'
              '最大定員はお子様を含め手動で選択できる上限です。'
              '独自の部屋タイプは自動部屋割り分類で「その他」を選択してください。',
            ),
            const SizedBox(height: 12),
            for (var index = 0; index < _rooms.length; index++)
              _buildRoomCard(index),
            const SizedBox(height: 24),
            _buildRateSettings(),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomCard(int index) {
    final room = _rooms[index];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 100,
                    child: TextFormField(
                      controller: room.numberController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '部屋番号',
                        suffixText: '号室',
                        border: OutlineInputBorder(),
                      ),
                      validator: _positiveIntegerValidator,
                    ),
                  ),
                  SizedBox(
                    width: 190,
                    child: DropdownButtonFormField<GuestRoomType>(
                      initialValue: room.type,
                      decoration: const InputDecoration(
                        labelText: '自動部屋割り分類',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final type in GuestRoomType.values)
                          DropdownMenuItem(
                            value: type,
                            child: Text(type.label),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            room.type = value;
                          });
                        }
                      },
                    ),
                  ),
                  SizedBox(
                    width: 190,
                    child: TextFormField(
                      controller: room.labelController,
                      decoration: const InputDecoration(
                        labelText: '部屋タイプ名（自由入力）',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (value) =>
                          value?.trim().isEmpty == true ? '表示名を入力' : null,
                    ),
                  ),
                  SizedBox(
                    width: 110,
                    child: TextFormField(
                      controller: room.normalCapacityController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '通常人数',
                        suffixText: '名',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final error = _positiveIntegerValidator(value);
                        if (error != null) {
                          return error;
                        }
                        final normal = int.parse(value!.trim());
                        final maximum = int.tryParse(
                          room.capacityController.text.trim(),
                        );
                        if (maximum != null && normal > maximum) {
                          return '最大以下にする';
                        }
                        return null;
                      },
                    ),
                  ),
                  SizedBox(
                    width: 110,
                    child: TextFormField(
                      controller: room.capacityController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '最大定員',
                        suffixText: '名',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: _positiveIntegerValidator,
                    ),
                  ),
                  FilterChip(
                    label: Text(room.isAvailable ? '使用可' : '使用不可'),
                    selected: room.isAvailable,
                    onSelected: (value) {
                      setState(() {
                        room.isAvailable = value;
                      });
                    },
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'この客室を削除',
              onPressed: _saving ? null : () => _removeRoom(index),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }

  static String? _positiveIntegerValidator(String? value) {
    final parsed = int.tryParse(value?.trim() ?? '');
    if (parsed == null || parsed <= 0) {
      return '1以上の数字';
    }
    return null;
  }

  Widget _buildRateSettings() {
    final definitions = _currentRoomTypes();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('料金設定', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        const Text(
          '1名料金と客室別ルールから直接予約の金額を自動計算します。'
          '人数別の1室合計料金を入力した場合は、大人だけの予約でそちらを優先します。',
        ),
        const SizedBox(height: 12),
        _buildPersonRateCard(),
        const SizedBox(height: 12),
        if (definitions.isEmpty)
          const Text('使用可能な客室タイプを登録してください。')
        else
          for (final definition in definitions) _buildRateCard(definition),
      ],
    );
  }

  Widget _buildPersonRateCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('1名・1泊料金', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text('子ども料金は10歳以下を想定しています。'),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 18,
                columns: const [
                  DataColumn(label: Text('区分')),
                  DataColumn(label: Text('素泊まり')),
                  DataColumn(label: Text('朝食付き')),
                  DataColumn(label: Text('2食付き')),
                ],
                rows: [
                  _personRateDataRow('大人', _personRatesEditor.adult),
                  _personRateDataRow(
                    '子ども・ベッドあり',
                    _personRatesEditor.childWithBed,
                  ),
                  _personRateDataRow(
                    '子ども・ベッドなし',
                    _personRatesEditor.childWithoutBed,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  DataRow _personRateDataRow(String label, _PersonPlanRateEditor editor) {
    return DataRow(
      cells: [
        DataCell(Text(label)),
        DataCell(_rateField(editor.roomOnlyController)),
        DataCell(_rateField(editor.breakfastController)),
        DataCell(_rateField(editor.twoMealsController)),
      ],
    );
  }

  Widget _buildRateCard(_RoomTypeDefinition definition) {
    final editor = _rateEditorFor(definition.name);
    editor.ensureGuestCount(definition.maximumGuests);
    final enteredMinimum = int.tryParse(
      editor.minimumGuestsController.text.trim(),
    );
    final minimumGuests = (enteredMinimum ?? 1)
        .clamp(1, definition.maximumGuests)
        .toInt();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${definition.name}（最大${definition.maximumGuests}名）',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: 180,
                  child: TextFormField(
                    controller: editor.minimumGuestsController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '最低利用人数',
                      suffixText: '名',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                    validator: (value) {
                      final error = _positiveIntegerValidator(value);
                      if (error != null) return error;
                      final minimum = int.parse(value!.trim());
                      return minimum > definition.maximumGuests
                          ? '最大定員以下にする'
                          : null;
                    },
                  ),
                ),
                SizedBox(
                  width: 240,
                  child: TextFormField(
                    controller: editor.singleUseSurchargeController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '1名利用時の加算',
                      suffixText: '円',
                      border: OutlineInputBorder(),
                    ),
                    validator: _optionalMoneyValidator,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text('以下の「1室・1泊合計料金」は任意です。'),
            const SizedBox(height: 4),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 18,
                columns: const [
                  DataColumn(label: Text('人数')),
                  DataColumn(label: Text('素泊まり')),
                  DataColumn(label: Text('朝食付き')),
                  DataColumn(label: Text('2食付き')),
                ],
                rows: [
                  for (
                    var guestCount = minimumGuests;
                    guestCount <= definition.maximumGuests;
                    guestCount++
                  )
                    _rateDataRow(editor.rowFor(guestCount)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  DataRow _rateDataRow(_RateRowEditor row) {
    return DataRow(
      cells: [
        DataCell(Text('${row.guestCount}名')),
        DataCell(_rateField(row.roomOnlyController)),
        DataCell(_rateField(row.breakfastController)),
        DataCell(_rateField(row.twoMealsController)),
      ],
    );
  }

  Widget _rateField(TextEditingController controller) {
    return SizedBox(
      width: 130,
      child: TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          suffixText: '円',
          isDense: true,
          border: OutlineInputBorder(),
        ),
        validator: _optionalMoneyValidator,
      ),
    );
  }

  List<_RoomTypeDefinition> _currentRoomTypes() {
    final definitions = <String, _RoomTypeDefinition>{};
    for (final room in _rooms) {
      if (!room.isAvailable) continue;
      final name = room.labelController.text.trim();
      final maximum = int.tryParse(room.capacityController.text.trim());
      if (name.isEmpty || maximum == null || maximum <= 0) continue;
      final key = _roomTypeKey(name);
      final existing = definitions[key];
      if (existing == null || maximum > existing.maximumGuests) {
        definitions[key] = _RoomTypeDefinition(
          name: existing?.name ?? name,
          maximumGuests: maximum,
        );
      }
    }
    final result = definitions.values.toList();
    result.sort((first, second) => first.name.compareTo(second.name));
    return result;
  }

  _RoomRateEditor _rateEditorFor(String roomTypeName) {
    return _rateEditors.putIfAbsent(
      _roomTypeKey(roomTypeName),
      () => _RoomRateEditor(
        defaultMinimumGuests: _defaultMinimumGuests(roomTypeName),
        defaultSingleUseSurchargeYen: _defaultSingleUseSurcharge(roomTypeName),
      ),
    );
  }

  GuestRoomType? _roomClassification(String roomTypeName) {
    final key = _roomTypeKey(roomTypeName);
    for (final room in _rooms) {
      if (room.isAvailable && _roomTypeKey(room.labelController.text) == key) {
        return room.type;
      }
    }
    return null;
  }

  int _defaultMinimumGuests(String roomTypeName) {
    return _roomClassification(roomTypeName) == GuestRoomType.loft ? 3 : 1;
  }

  int _defaultSingleUseSurcharge(String roomTypeName) {
    return _roomClassification(roomTypeName) == GuestRoomType.standardTwin
        ? 3000
        : 0;
  }

  static String? _optionalMoneyValidator(String? value) {
    final text = value?.replaceAll(',', '').trim() ?? '';
    if (text.isEmpty) return null;
    final parsed = int.tryParse(text);
    if (parsed == null || parsed < 0) return '0以上の数字';
    return null;
  }

  static String _roomTypeKey(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
  }
}

class _RoomEditor {
  _RoomEditor({
    required this.numberController,
    required this.labelController,
    required this.normalCapacityController,
    required this.capacityController,
    required this.type,
    required this.isAvailable,
  });

  factory _RoomEditor.fromRoom(GuestRoomSpec room) {
    return _RoomEditor(
      numberController: TextEditingController(text: '${room.number}'),
      labelController: TextEditingController(text: room.label),
      normalCapacityController: TextEditingController(
        text: '${room.normalCapacity}',
      ),
      capacityController: TextEditingController(text: '${room.capacity}'),
      type: room.type,
      isAvailable: room.isAvailable,
    );
  }

  final TextEditingController numberController;
  final TextEditingController labelController;
  final TextEditingController normalCapacityController;
  final TextEditingController capacityController;
  GuestRoomType type;
  bool isAvailable;

  GuestRoomSpec toRoom() {
    return GuestRoomSpec(
      number: int.parse(numberController.text.trim()),
      label: labelController.text.trim(),
      normalCapacity: int.parse(normalCapacityController.text.trim()),
      capacity: int.parse(capacityController.text.trim()),
      type: type,
      isAvailable: isAvailable,
    );
  }

  void dispose() {
    numberController.dispose();
    labelController.dispose();
    normalCapacityController.dispose();
    capacityController.dispose();
  }
}

class _RoomTypeDefinition {
  const _RoomTypeDefinition({required this.name, required this.maximumGuests});

  final String name;
  final int maximumGuests;
}

class _RoomRateEditor {
  _RoomRateEditor({
    required int defaultMinimumGuests,
    required int defaultSingleUseSurchargeYen,
  }) : minimumGuestsController = TextEditingController(
         text: '$defaultMinimumGuests',
       ),
       singleUseSurchargeController = TextEditingController(
         text: '$defaultSingleUseSurchargeYen',
       );

  factory _RoomRateEditor.fromRate(
    RoomTypeRate rate, {
    required int defaultMinimumGuests,
    required int defaultSingleUseSurchargeYen,
  }) {
    final editor = _RoomRateEditor(
      defaultMinimumGuests: rate.minimumGuests ?? defaultMinimumGuests,
      defaultSingleUseSurchargeYen:
          rate.singleUseSurchargeYen ?? defaultSingleUseSurchargeYen,
    );
    for (final guestRate in rate.rates) {
      editor._rows[guestRate.guestCount] = _RateRowEditor.fromRate(guestRate);
    }
    return editor;
  }

  final Map<int, _RateRowEditor> _rows = {};
  final TextEditingController minimumGuestsController;
  final TextEditingController singleUseSurchargeController;

  void ensureGuestCount(int maximumGuests) {
    for (var guestCount = 1; guestCount <= maximumGuests; guestCount++) {
      _rows.putIfAbsent(guestCount, () => _RateRowEditor(guestCount));
    }
  }

  _RateRowEditor rowFor(int guestCount) {
    return _rows.putIfAbsent(guestCount, () => _RateRowEditor(guestCount));
  }

  RoomTypeRate toRate(String roomTypeName, int maximumGuests) {
    ensureGuestCount(maximumGuests);
    return RoomTypeRate(
      roomTypeName: roomTypeName,
      minimumGuests: int.tryParse(minimumGuestsController.text.trim()),
      singleUseSurchargeYen: _RateRowEditor._readMoney(
        singleUseSurchargeController.text,
      ),
      rates: List.unmodifiable([
        for (var guestCount = 1; guestCount <= maximumGuests; guestCount++)
          rowFor(guestCount).toRate(),
      ]),
    );
  }

  void dispose() {
    for (final row in _rows.values) {
      row.dispose();
    }
    minimumGuestsController.dispose();
    singleUseSurchargeController.dispose();
  }
}

class _PersonRatesEditor {
  _PersonRatesEditor({
    required this.adult,
    required this.childWithBed,
    required this.childWithoutBed,
  });

  factory _PersonRatesEditor.fromSettings(PersonRateSettings settings) {
    return _PersonRatesEditor(
      adult: _PersonPlanRateEditor.fromRate(settings.adult),
      childWithBed: _PersonPlanRateEditor.fromRate(settings.childWithBed),
      childWithoutBed: _PersonPlanRateEditor.fromRate(settings.childWithoutBed),
    );
  }

  final _PersonPlanRateEditor adult;
  final _PersonPlanRateEditor childWithBed;
  final _PersonPlanRateEditor childWithoutBed;

  PersonRateSettings toSettings() => PersonRateSettings(
    adult: adult.toRate(),
    childWithBed: childWithBed.toRate(),
    childWithoutBed: childWithoutBed.toRate(),
  );

  void dispose() {
    adult.dispose();
    childWithBed.dispose();
    childWithoutBed.dispose();
  }
}

class _PersonPlanRateEditor {
  _PersonPlanRateEditor({
    required this.roomOnlyController,
    required this.breakfastController,
    required this.twoMealsController,
  });

  factory _PersonPlanRateEditor.fromRate(PersonPlanRate rate) {
    return _PersonPlanRateEditor(
      roomOnlyController: TextEditingController(
        text: rate.roomOnlyYen?.toString() ?? '',
      ),
      breakfastController: TextEditingController(
        text: rate.breakfastYen?.toString() ?? '',
      ),
      twoMealsController: TextEditingController(
        text: rate.twoMealsYen?.toString() ?? '',
      ),
    );
  }

  final TextEditingController roomOnlyController;
  final TextEditingController breakfastController;
  final TextEditingController twoMealsController;

  PersonPlanRate toRate() => PersonPlanRate(
    roomOnlyYen: _RateRowEditor._readMoney(roomOnlyController.text),
    breakfastYen: _RateRowEditor._readMoney(breakfastController.text),
    twoMealsYen: _RateRowEditor._readMoney(twoMealsController.text),
  );

  void dispose() {
    roomOnlyController.dispose();
    breakfastController.dispose();
    twoMealsController.dispose();
  }
}

class _RateRowEditor {
  _RateRowEditor(this.guestCount)
    : roomOnlyController = TextEditingController(),
      breakfastController = TextEditingController(),
      twoMealsController = TextEditingController();

  factory _RateRowEditor.fromRate(GuestCountRate rate) {
    return _RateRowEditor._(
      rate.guestCount,
      roomOnlyController: TextEditingController(
        text: rate.roomOnlyYen?.toString() ?? '',
      ),
      breakfastController: TextEditingController(
        text: rate.breakfastYen?.toString() ?? '',
      ),
      twoMealsController: TextEditingController(
        text: rate.twoMealsYen?.toString() ?? '',
      ),
    );
  }

  _RateRowEditor._(
    this.guestCount, {
    required this.roomOnlyController,
    required this.breakfastController,
    required this.twoMealsController,
  });

  final int guestCount;
  final TextEditingController roomOnlyController;
  final TextEditingController breakfastController;
  final TextEditingController twoMealsController;

  GuestCountRate toRate() {
    return GuestCountRate(
      guestCount: guestCount,
      roomOnlyYen: _readMoney(roomOnlyController.text),
      breakfastYen: _readMoney(breakfastController.text),
      twoMealsYen: _readMoney(twoMealsController.text),
    );
  }

  void dispose() {
    roomOnlyController.dispose();
    breakfastController.dispose();
    twoMealsController.dispose();
  }

  static int? _readMoney(String value) {
    final text = value.replaceAll(',', '').trim();
    return text.isEmpty ? null : int.tryParse(text);
  }
}
