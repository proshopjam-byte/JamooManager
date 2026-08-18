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

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _facilityNameController;
  late final TextEditingController _addressController;
  late final TextEditingController _phoneController;
  late List<_RoomEditor> _rooms;
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
  }

  @override
  void dispose() {
    _facilityNameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    for (final room in _rooms) {
      room.dispose();
    }
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

    final rooms = _rooms.map((editor) => editor.toRoom()).toList()
      ..sort((first, second) => first.number.compareTo(second.number));
    final settings = FacilitySettings(
      facilityName: _facilityNameController.text.trim(),
      address: _addressController.text.trim(),
      phone: _phoneController.text.trim(),
      rooms: List.unmodifiable(rooms),
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
    setState(() {
      _rooms = FacilitySettings.defaults.rooms
          .map(_RoomEditor.fromRoom)
          .toList();
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
                  onPressed: _saving ? null : _addRoom,
                  icon: const Icon(Icons.add),
                  label: const Text('客室を追加'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              '通常人数は自動部屋割りで使う人数、'
              '最大定員はお子様を含め手動で選択できる上限です。',
            ),
            const SizedBox(height: 12),
            for (var index = 0; index < _rooms.length; index++)
              _buildRoomCard(index),
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
                        labelText: '部屋種類',
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
                        labelText: '表示名',
                        border: OutlineInputBorder(),
                      ),
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
