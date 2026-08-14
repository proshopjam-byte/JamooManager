import 'package:flutter/material.dart';

import '../models/customer.dart';
import '../repositories/customer_repository.dart';

class CustomerListPage extends StatefulWidget {
  const CustomerListPage({super.key});

  @override
  State<CustomerListPage> createState() => _CustomerListPageState();
}

class _CustomerListPageState extends State<CustomerListPage> {
  final CustomerRepository _repository = const CustomerRepository();
  final TextEditingController _searchController = TextEditingController();
  late Future<List<Customer>> _customersFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _customersFuture = _repository.searchCustomers(_searchController.text);
    });
  }

  Future<void> _openNewCustomer() async {
    await _openEditor(const CustomerDraft(fullName: ''));
  }

  Future<void> _openReservationPicker() async {
    final reservation = await showDialog<CustomerReservationCandidate>(
      context: context,
      builder: (context) => _ReservationPickerDialog(repository: _repository),
    );
    if (!mounted || reservation == null) {
      return;
    }
    await _openEditor(
      CustomerDraft.fromReservation(reservation),
      reservation: reservation,
    );
  }

  Future<void> _openEditor(
    CustomerDraft initial, {
    Customer? customer,
    CustomerReservationCandidate? reservation,
  }) async {
    final draft = await showDialog<CustomerDraft>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _CustomerEditDialog(
        initial: initial,
        title: customer == null ? '顧客を登録' : '顧客情報を編集',
        reservation: reservation,
      ),
    );
    if (!mounted || draft == null) {
      return;
    }

    var targetCustomerId = customer?.id;
    final duplicate = await _repository.findDuplicate(
      draft,
      excludingCustomerId: customer?.id,
    );
    if (!mounted) {
      return;
    }
    if (duplicate != null) {
      final action = await showDialog<_DuplicateAction>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('同じ顧客の可能性があります'),
          content: Text(
            '「${duplicate.fullName}」さんとメールアドレス、電話番号、'
            'または氏名が一致しました。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(
                context,
                _DuplicateAction.cancel,
              ),
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(
                context,
                _DuplicateAction.createSeparate,
              ),
              child: const Text('別の顧客として登録'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                _DuplicateAction.updateExisting,
              ),
              child: const Text('既存顧客を更新'),
            ),
          ],
        ),
      );
      if (!mounted || action == null || action == _DuplicateAction.cancel) {
        return;
      }
      if (action == _DuplicateAction.updateExisting) {
        targetCustomerId = duplicate.id;
      }
    }

    try {
      await _repository.saveCustomer(
        draft,
        customerId: targetCustomerId,
        reservation: reservation,
      );
      if (!mounted) {
        return;
      }
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            customer == null && targetCustomerId == null
                ? '顧客を登録しました。'
                : '顧客情報を更新しました。',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('顧客情報を保存できませんでした'),
          content: SelectableText(error.toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('閉じる'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _showHistory(Customer customer) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _CustomerHistoryDialog(
        customer: customer,
        historyFuture: _repository.loadHistory(customer),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('顧客一覧'),
        actions: [
          OutlinedButton.icon(
            onPressed: _openReservationPicker,
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: const Text('予約から登録'),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: '再読込',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNewCustomer,
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('手入力で登録'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              onSubmitted: (_) => _reload(),
              decoration: InputDecoration(
                labelText: '氏名・電話・メール・住所で検索',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: '検索',
                  onPressed: _reload,
                  icon: const Icon(Icons.arrow_forward),
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: FutureBuilder<List<Customer>>(
                future: _customersFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return _CustomerErrorView(
                      error: snapshot.error,
                      onRetry: _reload,
                    );
                  }
                  final customers = snapshot.data ?? const <Customer>[];
                  if (customers.isEmpty) {
                    return const Center(
                      child: Text('該当する顧客はありません。'),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: customers.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final customer = customers[index];
                      return _CustomerCard(
                        customer: customer,
                        onEdit: () => _openEditor(
                          CustomerDraft.fromCustomer(customer),
                          customer: customer,
                        ),
                        onHistory: () => _showHistory(customer),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _DuplicateAction { cancel, createSeparate, updateExisting }

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({
    required this.customer,
    required this.onEdit,
    required this.onHistory,
  });

  final Customer customer;
  final VoidCallback onEdit;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    final contact = [customer.phone, customer.email]
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .join('　');
    final address = [customer.postalCode, customer.address]
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .join(' ');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(18, 10, 8, 10),
        leading: CircleAvatar(
          child: Text(customer.fullName.characters.first),
        ),
        title: Text(
          customer.fullName,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (contact.isNotEmpty) Text(contact),
            if (address.isNotEmpty) Text(address),
            const SizedBox(height: 4),
            Text(
              '宿泊 ${customer.stayCount}回　'
              '累計 ${_formatYen(customer.totalSpendYen)}　'
              '最終宿泊 ${_formatDate(customer.lastStayDate)}',
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton.icon(
              onPressed: onHistory,
              icon: const Icon(Icons.history),
              label: const Text('宿泊履歴'),
            ),
            IconButton(
              tooltip: '編集',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerEditDialog extends StatefulWidget {
  const _CustomerEditDialog({
    required this.initial,
    required this.title,
    this.reservation,
  });

  final CustomerDraft initial;
  final String title;
  final CustomerReservationCandidate? reservation;

  @override
  State<_CustomerEditDialog> createState() => _CustomerEditDialogState();
}

class _CustomerEditDialogState extends State<_CustomerEditDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _postalCodeController;
  late final TextEditingController _addressController;
  late final TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initial.fullName);
    _emailController = TextEditingController(text: widget.initial.email);
    _phoneController = TextEditingController(text: widget.initial.phone);
    _postalCodeController = TextEditingController(
      text: widget.initial.postalCode,
    );
    _addressController = TextEditingController(text: widget.initial.address);
    _notesController = TextEditingController(text: widget.initial.notes);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _postalCodeController.dispose();
    _addressController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    Navigator.pop(
      context,
      CustomerDraft(
        fullName: _nameController.text.trim(),
        email: _emptyToNull(_emailController.text),
        phone: _emptyToNull(_phoneController.text),
        postalCode: _emptyToNull(_postalCodeController.text),
        address: _emptyToNull(_addressController.text),
        notes: _emptyToNull(_notesController.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reservation = widget.reservation;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 680,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (reservation != null) ...[
                  Card(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(Icons.event_available_outlined),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${reservation.source} '
                              '${reservation.reservationNumber}　'
                              '${_formatDate(reservation.checkIn)}から登録',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _nameController,
                  autofocus: reservation == null,
                  decoration: const InputDecoration(
                    labelText: '氏名 *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? '氏名を入力してください。'
                      : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _phoneController,
                        decoration: const InputDecoration(
                          labelText: '電話番号',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _emailController,
                        decoration: const InputDecoration(
                          labelText: 'メールアドレス',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 180,
                      child: TextFormField(
                        controller: _postalCodeController,
                        decoration: const InputDecoration(
                          labelText: '郵便番号',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _addressController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: '住所',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'メモ',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
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
}

class _ReservationPickerDialog extends StatefulWidget {
  const _ReservationPickerDialog({required this.repository});

  final CustomerRepository repository;

  @override
  State<_ReservationPickerDialog> createState() =>
      _ReservationPickerDialogState();
}

class _ReservationPickerDialogState extends State<_ReservationPickerDialog> {
  final TextEditingController _searchController = TextEditingController();
  late Future<List<CustomerReservationCandidate>> _future;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _search() {
    setState(() {
      _future = widget.repository.loadReservationCandidates(
        _searchController.text,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('予約から顧客を登録'),
      content: SizedBox(
        width: 780,
        height: 560,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                labelText: '予約者名・電話・メール・予約番号で検索',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  onPressed: _search,
                  icon: const Icon(Icons.arrow_forward),
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: FutureBuilder<List<CustomerReservationCandidate>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: SelectableText('${snapshot.error}'));
                  }
                  final values =
                      snapshot.data ?? const <CustomerReservationCandidate>[];
                  if (values.isEmpty) {
                    return const Center(child: Text('該当する予約はありません。'));
                  }
                  return ListView.separated(
                    itemCount: values.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final value = values[index];
                      final contact = [value.phone, value.email]
                          .whereType<String>()
                          .join('　');
                      return ListTile(
                        title: Text(value.guestName),
                        subtitle: Text(
                          '${_formatDate(value.checkIn)}　'
                          '${value.source} ${value.reservationNumber}'
                          '${contact.isEmpty ? '' : '\n$contact'}',
                        ),
                        isThreeLine: contact.isNotEmpty,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.pop(context, value),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('閉じる'),
        ),
      ],
    );
  }
}

class _CustomerHistoryDialog extends StatelessWidget {
  const _CustomerHistoryDialog({
    required this.customer,
    required this.historyFuture,
  });

  final Customer customer;
  final Future<List<CustomerStay>> historyFuture;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${customer.fullName}さんの宿泊履歴'),
      content: SizedBox(
        width: 720,
        height: 480,
        child: FutureBuilder<List<CustomerStay>>(
          future: historyFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: SelectableText('${snapshot.error}'));
            }
            final stays = snapshot.data ?? const <CustomerStay>[];
            if (stays.isEmpty) {
              return const Center(child: Text('紐づく宿泊履歴はありません。'));
            }
            return ListView.separated(
              itemCount: stays.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final stay = stays[index];
                return ListTile(
                  leading: const Icon(Icons.hotel_outlined),
                  title: Text(
                    '${_formatDate(stay.checkIn)} ～ '
                    '${_formatDate(stay.checkOut)}',
                  ),
                  subtitle: Text(
                    '${stay.source} ${stay.reservationNumber}'
                    '${stay.roomName == null ? '' : '　${stay.roomName}'}',
                  ),
                  trailing: Text(_formatYen(stay.priceYen ?? 0)),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('閉じる'),
        ),
      ],
    );
  }
}

class _CustomerErrorView extends StatelessWidget {
  const _CustomerErrorView({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48),
          const SizedBox(height: 12),
          const Text('顧客一覧を読み込めませんでした。'),
          const SizedBox(height: 8),
          SelectableText('$error'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('再試行'),
          ),
        ],
      ),
    );
  }
}

String? _emptyToNull(String value) {
  final text = value.trim();
  return text.isEmpty ? null : text;
}

String _formatDate(DateTime? value) {
  if (value == null) {
    return '未設定';
  }
  return '${value.year.toString().padLeft(4, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/'
      '${value.day.toString().padLeft(2, '0')}';
}

String _formatYen(int value) {
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
