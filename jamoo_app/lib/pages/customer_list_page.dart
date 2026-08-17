import 'package:flutter/material.dart';

import '../models/customer.dart';
import '../repositories/customer_repository.dart';
import '../services/customer_document_service.dart';
import '../services/customer_export_service.dart';

class CustomerListPage extends StatefulWidget {
  const CustomerListPage({super.key});

  @override
  State<CustomerListPage> createState() => _CustomerListPageState();
}

class _CustomerListPageState extends State<CustomerListPage> {
  final CustomerRepository _repository = const CustomerRepository();
  final CustomerDocumentService _documentService =
      const CustomerDocumentService();
  final CustomerExportService _exportService = const CustomerExportService();
  final TextEditingController _searchController = TextEditingController();
  late Future<List<Customer>> _customersFuture;
  bool _importingCards = false;
  bool _exportingCustomers = false;

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

  Future<void> _openCardImport() async {
    if (_importingCards) {
      return;
    }
    CustomerCardImportBatch? batch;
    try {
      final selected = await _documentService.pickCustomerCardFile();
      if (!mounted || selected == null) {
        return;
      }
      final configured = await _ensureCloudOcrApiKey();
      if (!mounted || !configured) {
        return;
      }

      setState(() => _importingCards = true);
      batch = await _documentService.runCardImportOcr(selected);
      if (!mounted) {
        return;
      }
      setState(() => _importingCards = false);

      final pages = batch.result.pages.isNotEmpty
          ? batch.result.pages
          : <CustomerOcrPageResult>[
              CustomerOcrPageResult(
                pageNumber: 1,
                rawText: batch.result.rawText,
                fullName: batch.result.fullName,
                email: batch.result.email,
                phone: batch.result.phone,
                postalCode: batch.result.postalCode,
                address: batch.result.address,
                country: batch.result.country,
              ),
            ];
      var registeredCount = 0;
      var updatedCount = 0;
      var skippedCount = 0;
      var cancelled = false;

      for (var index = 0; index < pages.length; index++) {
        if (!mounted) {
          return;
        }
        final page = pages[index];
        final review = await showDialog<_CardImportReviewResult>(
          context: context,
          barrierDismissible: false,
          builder: (context) => _CardImportReviewDialog(
            page: page,
            pageIndex: index,
            pageCount: pages.length,
            warning: batch!.result.warning,
            onOpenOriginal: () async {
              try {
                await _documentService.openImportedPage(
                  source: batch!.source,
                  page: page,
                );
              } catch (error) {
                if (mounted) {
                  await _showError('カード原本を開けませんでした', error);
                }
              }
            },
          ),
        );
        if (!mounted || review == null) {
          cancelled = true;
          break;
        }
        if (review.action == _CardImportReviewAction.cancelAll) {
          cancelled = true;
          break;
        }
        if (review.action == _CardImportReviewAction.skip) {
          skippedCount++;
          continue;
        }

        final draft = review.draft;
        if (draft == null) {
          skippedCount++;
          continue;
        }
        final saved = await _saveImportedCustomer(draft);
        if (!mounted) {
          return;
        }
        if (saved == null) {
          skippedCount++;
          continue;
        }
        try {
          await _documentService.attachImportedPage(
            customerId: saved.customerId,
            source: batch.source,
            page: page,
          );
        } catch (error) {
          if (mounted) {
            await _showError('顧客は保存しましたが、カードを添付できませんでした', error);
          }
        }
        if (saved.updatedExisting) {
          updatedCount++;
        } else {
          registeredCount++;
        }
      }

      if (!mounted) {
        return;
      }
      _reload();
      final summary = <String>[
        '新規 $registeredCount件',
        '既存更新 $updatedCount件',
        'スキップ $skippedCount件',
      ].join('、');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            cancelled ? 'カード登録を途中で終了しました。$summary' : 'カード登録が完了しました。$summary',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        await _showError('カードから顧客を登録できませんでした', error);
      }
    } finally {
      if (mounted && _importingCards) {
        setState(() => _importingCards = false);
      }
      if (batch != null) {
        await _documentService.cleanupCardImport(batch);
      }
    }
  }

  Future<_ImportedCustomerSave?> _saveImportedCustomer(
    CustomerDraft draft,
  ) async {
    var targetDraft = draft;
    int? targetCustomerId;
    var updatedExisting = false;
    final duplicate = await _repository.findDuplicate(draft);
    if (!mounted) {
      return null;
    }
    if (duplicate != null) {
      final action = await _showDuplicateAction(duplicate);
      if (!mounted || action == null || action == _DuplicateAction.cancel) {
        return null;
      }
      if (action == _DuplicateAction.updateExisting) {
        targetCustomerId = duplicate.id;
        updatedExisting = true;
        targetDraft = CustomerDraft(
          fullName: draft.fullName,
          email: draft.email ?? duplicate.email,
          phone: draft.phone ?? duplicate.phone,
          postalCode: draft.postalCode ?? duplicate.postalCode,
          address: draft.address ?? duplicate.address,
          country: draft.country ?? duplicate.country,
          notes: duplicate.notes,
        );
      }
    }
    final customerId = await _repository.saveCustomer(
      targetDraft,
      customerId: targetCustomerId,
    );
    return _ImportedCustomerSave(
      customerId: customerId,
      updatedExisting: updatedExisting,
    );
  }

  Future<_DuplicateAction?> _showDuplicateAction(Customer duplicate) {
    return showDialog<_DuplicateAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('同じ顧客の可能性があります'),
        content: Text(
          '「${duplicate.fullName}」さんとメールアドレス、電話番号、'
          'または氏名が一致しました。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _DuplicateAction.cancel),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, _DuplicateAction.createSeparate),
            child: const Text('別の顧客として登録'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, _DuplicateAction.updateExisting),
            child: const Text('既存顧客を更新'),
          ),
        ],
      ),
    );
  }

  Future<bool> _ensureCloudOcrApiKey() async {
    if (await _documentService.hasCloudOcrApiKey()) {
      return true;
    }
    if (!mounted) {
      return false;
    }
    var input = '';
    var obscureText = true;
    final apiKey = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Google Cloud Vision APIキー'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'カード画像をGoogle Cloudへ送信して手書きOCRを実行します。'
                  'APIキーはこのPC内だけに保存されます。',
                ),
                const SizedBox(height: 16),
                TextField(
                  autofocus: true,
                  obscureText: obscureText,
                  onChanged: (value) {
                    input = value;
                    setDialogState(() {});
                  },
                  decoration: InputDecoration(
                    labelText: 'Vision APIキー',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: obscureText ? '表示する' : '隠す',
                      onPressed: () {
                        setDialogState(() => obscureText = !obscureText);
                      },
                      icon: Icon(
                        obscureText
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: input.trim().length < 20
                  ? null
                  : () => Navigator.pop(context, input.trim()),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (apiKey == null) {
      return false;
    }
    await _documentService.saveCloudOcrApiKey(apiKey);
    return true;
  }

  Future<void> _showError(String title, Object error) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
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

  Future<void> _exportCustomers({bool asExcel = false}) async {
    if (_exportingCustomers) {
      return;
    }
    setState(() => _exportingCustomers = true);
    try {
      final customers = await _repository.searchCustomers(
        _searchController.text,
      );
      if (!mounted) {
        return;
      }
      if (customers.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('出力する顧客がありません。')));
        return;
      }
      final path = asExcel
          ? await _exportService.exportXlsx(customers)
          : await _exportService.exportCsv(customers);
      if (!mounted || path == null) {
        return;
      }
      final format = asExcel ? 'Excel' : 'CSV';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('顧客一覧 ${customers.length}件を$formatへ保存しました。\n$path'),
        ),
      );
    } catch (error) {
      if (mounted) {
        final format = asExcel ? 'Excel' : 'CSV';
        await _showError('顧客一覧を$formatへ保存できませんでした', error);
      }
    } finally {
      if (mounted) {
        setState(() => _exportingCustomers = false);
      }
    }
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
      final action = await _showDuplicateAction(duplicate);
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

  Future<void> _openDocuments(Customer customer) async {
    final updatedDraft = await showDialog<CustomerDraft>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _CustomerDocumentsDialog(
        customer: customer,
        repository: _repository,
        documentService: _documentService,
      ),
    );
    if (!mounted || updatedDraft == null) {
      return;
    }
    await _repository.saveCustomer(updatedDraft, customerId: customer.id);
    if (!mounted) {
      return;
    }
    _reload();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('OCR候補を顧客情報へ反映しました。')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('顧客一覧'),
        actions: [
          OutlinedButton.icon(
            onPressed: _importingCards || _exportingCustomers
                ? null
                : () => _exportCustomers(asExcel: true),
            icon: const Icon(Icons.table_view_outlined),
            label: const Text('Excel出力'),
          ),
          IconButton(
            tooltip: 'CSV出力',
            onPressed: _importingCards || _exportingCustomers
                ? null
                : () => _exportCustomers(),
            icon: const Icon(Icons.description_outlined),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _importingCards ? null : _openCardImport,
            icon: const Icon(Icons.document_scanner_outlined),
            label: const Text('カードから登録'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _importingCards ? null : _openReservationPicker,
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
        onPressed: _importingCards ? null : _openNewCustomer,
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('手入力で登録'),
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  onSubmitted: (_) => _reload(),
                  decoration: InputDecoration(
                    labelText: '氏名・電話・メール・住所・国名で検索',
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
                        return const Center(child: Text('該当する顧客はありません。'));
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
                            onDocuments: () => _openDocuments(customer),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          if (_importingCards)
            Positioned.fill(
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surface.withAlpha(220),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 14),
                      Text('カードを読み取っています…'),
                      SizedBox(height: 6),
                      Text('複数ページPDFは少し時間がかかります。'),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

enum _DuplicateAction { cancel, createSeparate, updateExisting }

class _ImportedCustomerSave {
  const _ImportedCustomerSave({
    required this.customerId,
    required this.updatedExisting,
  });

  final int customerId;
  final bool updatedExisting;
}

enum _CardImportReviewAction { register, skip, cancelAll }

class _CardImportReviewResult {
  const _CardImportReviewResult({required this.action, this.draft});

  final _CardImportReviewAction action;
  final CustomerDraft? draft;
}

class _CardImportReviewDialog extends StatefulWidget {
  const _CardImportReviewDialog({
    required this.page,
    required this.pageIndex,
    required this.pageCount,
    required this.onOpenOriginal,
    this.warning,
  });

  final CustomerOcrPageResult page;
  final int pageIndex;
  final int pageCount;
  final Future<void> Function() onOpenOriginal;
  final String? warning;

  @override
  State<_CardImportReviewDialog> createState() =>
      _CardImportReviewDialogState();
}

class _CardImportReviewDialogState extends State<_CardImportReviewDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _postalCodeController;
  late final TextEditingController _addressController;
  late final TextEditingController _countryController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.page.fullName);
    _phoneController = TextEditingController(text: widget.page.phone);
    _emailController = TextEditingController(text: widget.page.email);
    _postalCodeController = TextEditingController(text: widget.page.postalCode);
    _addressController = TextEditingController(text: widget.page.address);
    _countryController = TextEditingController(text: widget.page.country);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _postalCodeController.dispose();
    _addressController.dispose();
    _countryController.dispose();
    super.dispose();
  }

  void _register() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    Navigator.pop(
      context,
      _CardImportReviewResult(
        action: _CardImportReviewAction.register,
        draft: CustomerDraft(
          fullName: _nameController.text.trim(),
          phone: _emptyToNull(_phoneController.text),
          email: _emptyToNull(_emailController.text),
          postalCode: _emptyToNull(_postalCodeController.text),
          address: _emptyToNull(_addressController.text),
          country: _emptyToNull(_countryController.text),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pageLabel = widget.pageCount > 1
        ? '${widget.pageIndex + 1}/${widget.pageCount}ページ'
        : '1ページ';
    return AlertDialog(
      title: Text('カードから顧客登録（$pageLabel）'),
      content: SizedBox(
        width: 860,
        height: 640,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'OCR候補を原本と照合して修正してください。'
                      '保存前に既存顧客との重複も確認します。',
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: widget.onOpenOriginal,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('原本ページを開く'),
                  ),
                ],
              ),
              if (widget.warning != null && widget.warning!.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    widget.warning!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: '氏名 *',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? '氏名を入力してください。'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 190,
                    child: TextFormField(
                      controller: _countryController,
                      decoration: const InputDecoration(
                        labelText: '国名',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _phoneController,
                      decoration: const InputDecoration(
                        labelText: '電話番号',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'メールアドレス',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 190,
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
                      minLines: 2,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: '住所',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'OCRが読み取った全文（参考）',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      widget.page.rawText.trim().isEmpty
                          ? '文字を認識できませんでした。'
                          : widget.page.rawText,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            const _CardImportReviewResult(
              action: _CardImportReviewAction.cancelAll,
            ),
          ),
          child: const Text('一括登録を終了'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            const _CardImportReviewResult(action: _CardImportReviewAction.skip),
          ),
          child: const Text('このページをスキップ'),
        ),
        FilledButton.icon(
          onPressed: _register,
          icon: const Icon(Icons.person_add_outlined),
          label: const Text('このページを登録'),
        ),
      ],
    );
  }
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({
    required this.customer,
    required this.onEdit,
    required this.onHistory,
    required this.onDocuments,
  });

  final Customer customer;
  final VoidCallback onEdit;
  final VoidCallback onHistory;
  final VoidCallback onDocuments;

  @override
  Widget build(BuildContext context) {
    final contact = [
      customer.phone,
      customer.email,
    ].whereType<String>().where((value) => value.isNotEmpty).join('　');
    final address = [
      customer.postalCode,
      customer.address,
    ].whereType<String>().where((value) => value.isNotEmpty).join(' ');
    final location = [
      customer.country,
      address,
    ].whereType<String>().where((value) => value.isNotEmpty).join('　');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(18, 10, 8, 10),
        leading: CircleAvatar(child: Text(customer.fullName.characters.first)),
        title: Text(
          customer.fullName,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (contact.isNotEmpty) Text(contact),
            if (location.isNotEmpty) Text(location),
            const SizedBox(height: 4),
            Text(
              '予約経路 ${customer.reservationSourceLabel}　'
              '状態 ${customer.reservationStatusLabel}',
              style: TextStyle(
                color: customer.isCancelledOnly
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: customer.isCancelledOnly
                    ? FontWeight.w600
                    : FontWeight.normal,
              ),
            ),
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
              onPressed: onDocuments,
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('書類'),
            ),
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
  late final TextEditingController _countryController;
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
    _countryController = TextEditingController(text: widget.initial.country);
    _notesController = TextEditingController(text: widget.initial.notes);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _postalCodeController.dispose();
    _addressController.dispose();
    _countryController.dispose();
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
        country: _emptyToNull(_countryController.text),
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
                  controller: _countryController,
                  decoration: const InputDecoration(
                    labelText: '国名',
                    border: OutlineInputBorder(),
                  ),
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
                      final contact = [
                        value.phone,
                        value.email,
                      ].whereType<String>().join('　');
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

enum _CustomerOcrMode { local, cloud }

class _CustomerDocumentsDialog extends StatefulWidget {
  const _CustomerDocumentsDialog({
    required this.customer,
    required this.repository,
    required this.documentService,
  });

  final Customer customer;
  final CustomerRepository repository;
  final CustomerDocumentService documentService;

  @override
  State<_CustomerDocumentsDialog> createState() =>
      _CustomerDocumentsDialogState();
}

class _CustomerDocumentsDialogState extends State<_CustomerDocumentsDialog> {
  late Future<List<CustomerDocument>> _documentsFuture;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _documentsFuture = widget.repository.loadCustomerDocuments(
        widget.customer.id,
      );
    });
  }

  Future<void> _attach() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final document = await widget.documentService.pickAndAttach(
        widget.customer.id,
      );
      if (!mounted || document == null) {
        return;
      }
      _reload();
      final ocrMode = await showDialog<_CustomerOcrMode>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('書類を添付しました'),
          content: const Text('手書きの宿帳は「手書きOCR」、印刷文書は「標準OCR」を選択してください。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('後で実行'),
            ),
            TextButton.icon(
              onPressed: () => Navigator.pop(context, _CustomerOcrMode.local),
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('標準OCR'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, _CustomerOcrMode.cloud),
              icon: const Icon(Icons.cloud_outlined),
              label: const Text('手書きOCR'),
            ),
          ],
        ),
      );
      if (mounted && ocrMode != null) {
        await _runOcr(document, mode: ocrMode);
      }
    } catch (error) {
      if (mounted) {
        await _showError('書類を添付できませんでした', error);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _runOcr(
    CustomerDocument document, {
    _CustomerOcrMode mode = _CustomerOcrMode.local,
  }) async {
    if (_busy && document.ocrStatus != 'not_processed') {
      return;
    }
    if (mode == _CustomerOcrMode.cloud) {
      final configured = await _ensureCloudOcrApiKey();
      if (!mounted || !configured) {
        return;
      }
    }
    setState(() => _busy = true);
    try {
      final result = await widget.documentService.runOcr(
        document,
        useCloud: mode == _CustomerOcrMode.cloud,
      );
      if (!mounted) {
        return;
      }
      _reload();
      final draft = await showDialog<CustomerDraft>(
        context: context,
        barrierDismissible: false,
        builder: (context) =>
            _OcrReviewDialog(customer: widget.customer, result: result),
      );
      if (!mounted || draft == null) {
        return;
      }
      Navigator.pop(context, draft);
    } catch (error) {
      if (mounted) {
        _reload();
        await _showError('OCRを実行できませんでした', error);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<bool> _ensureCloudOcrApiKey({bool replaceExisting = false}) async {
    if (!replaceExisting) {
      final configured = await widget.documentService.hasCloudOcrApiKey();
      if (configured) {
        return true;
      }
    }
    if (!mounted) {
      return false;
    }

    var input = '';
    var obscureText = true;
    final apiKey = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Google Cloud Vision APIキー'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '手書きOCRでは宿帳画像をGoogle Cloudへ送信します。'
                  'APIキーはこのPC内だけに保存されます。',
                ),
                const SizedBox(height: 16),
                TextField(
                  autofocus: true,
                  obscureText: obscureText,
                  onChanged: (value) {
                    input = value;
                    setDialogState(() {});
                  },
                  decoration: InputDecoration(
                    labelText: 'Vision APIキー',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: obscureText ? '表示する' : '隠す',
                      onPressed: () {
                        setDialogState(() => obscureText = !obscureText);
                      },
                      icon: Icon(
                        obscureText
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: input.trim().length < 20
                  ? null
                  : () => Navigator.pop(context, input.trim()),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (apiKey == null) {
      return false;
    }
    await widget.documentService.saveCloudOcrApiKey(apiKey);
    if (mounted && replaceExisting) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('手書きOCRのAPIキーを保存しました。')));
    }
    return true;
  }

  Future<void> _configureCloudOcr() async {
    try {
      await _ensureCloudOcrApiKey(replaceExisting: true);
    } catch (error) {
      if (mounted) {
        await _showError('APIキーを保存できませんでした', error);
      }
    }
  }

  Future<void> _open(CustomerDocument document) async {
    try {
      await widget.documentService.openDocument(document);
    } catch (error) {
      if (mounted) {
        await _showError('書類を開けませんでした', error);
      }
    }
  }

  Future<void> _delete(CustomerDocument document) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添付書類を削除しますか？'),
        content: Text(document.originalFileName),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await widget.documentService.deleteDocument(document);
      if (mounted) {
        _reload();
      }
    } catch (error) {
      if (mounted) {
        await _showError('書類を削除できませんでした', error);
      }
    }
  }

  Future<void> _showOcrReference(CustomerDocument document) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('保存済みOCR参考データ'),
        content: SizedBox(
          width: 760,
          height: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(document.originalFileName),
              const SizedBox(height: 10),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      document.ocrText?.trim().isNotEmpty == true
                          ? document.ocrText!
                          : '保存されたOCR参考データはありません。',
                    ),
                  ),
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
      ),
    );
  }

  Future<void> _showError(String title, Object error) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.customer.fullName}さんの添付書類'),
      content: SizedBox(
        width: 850,
        height: 540,
        child: Stack(
          children: [
            FutureBuilder<List<CustomerDocument>>(
              future: _documentsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: SelectableText('${snapshot.error}'));
                }
                final documents = snapshot.data ?? const <CustomerDocument>[];
                if (documents.isEmpty) {
                  return const Center(child: Text('画像またはPDFを添付してください。'));
                }
                return ListView.separated(
                  itemCount: documents.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final document = documents[index];
                    return ListTile(
                      leading: Icon(
                        document.mimeType == 'application/pdf'
                            ? Icons.picture_as_pdf_outlined
                            : Icons.image_outlined,
                      ),
                      title: Text(document.originalFileName),
                      subtitle: Text(
                        '${_formatDate(document.createdAt)}　'
                        '${_ocrStatusLabel(document.ocrStatus)}',
                      ),
                      onTap: () => _open(document),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _runOcr(
                                    document,
                                    mode: _CustomerOcrMode.local,
                                  ),
                            icon: const Icon(Icons.document_scanner_outlined),
                            label: const Text('標準OCR'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: _busy
                                ? null
                                : () => _runOcr(
                                    document,
                                    mode: _CustomerOcrMode.cloud,
                                  ),
                            icon: const Icon(Icons.cloud_outlined),
                            label: Text(
                              document.hasOcrText ? '手書きOCR再実行' : '手書きOCR',
                            ),
                          ),
                          if (document.hasOcrText)
                            IconButton(
                              tooltip: '保存済みOCR参考データを表示',
                              onPressed: _busy
                                  ? null
                                  : () => _showOcrReference(document),
                              icon: const Icon(Icons.notes_outlined),
                            ),
                          IconButton(
                            tooltip: '削除',
                            onPressed: _busy ? null : () => _delete(document),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
            if (_busy)
              Positioned.fill(
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.surface.withAlpha(210),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('処理中です…'),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _busy ? null : _configureCloudOcr,
          icon: const Icon(Icons.key_outlined),
          label: const Text('手書きOCR設定'),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('閉じる'),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _attach,
          icon: const Icon(Icons.attach_file),
          label: const Text('画像・PDFを追加'),
        ),
      ],
    );
  }

  static String _ocrStatusLabel(String status) {
    switch (status) {
      case 'processing':
        return 'OCR処理中';
      case 'completed':
        return 'OCR済み';
      case 'failed':
        return 'OCR失敗';
      default:
        return 'OCR未実行';
    }
  }
}

class _OcrReviewDialog extends StatefulWidget {
  const _OcrReviewDialog({required this.customer, required this.result});

  final Customer customer;
  final CustomerOcrResult result;

  @override
  State<_OcrReviewDialog> createState() => _OcrReviewDialogState();
}

class _OcrReviewDialogState extends State<_OcrReviewDialog> {
  int _selectedPageIndex = 0;
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _postalCodeController;
  late final TextEditingController _addressController;
  late final TextEditingController _countryController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: _preferExisting(widget.customer.fullName, widget.result.fullName),
    );
    _emailController = TextEditingController(
      text: _preferExisting(widget.customer.email, widget.result.email),
    );
    _phoneController = TextEditingController(
      text: _preferExisting(widget.customer.phone, widget.result.phone),
    );
    _postalCodeController = TextEditingController(
      text: _preferExisting(
        widget.customer.postalCode,
        widget.result.postalCode,
      ),
    );
    _addressController = TextEditingController(
      text: _preferExisting(widget.customer.address, widget.result.address),
    );
    _countryController = TextEditingController(
      text: _preferExisting(widget.customer.country, widget.result.country),
    );
  }

  CustomerOcrPageResult? get _selectedPage {
    final pages = widget.result.pages;
    if (pages.isEmpty || _selectedPageIndex >= pages.length) {
      return null;
    }
    return pages[_selectedPageIndex];
  }

  String? get _fullNameSuggestion =>
      _selectedPage?.fullName ?? widget.result.fullName;
  String? get _emailSuggestion => _selectedPage?.email ?? widget.result.email;
  String? get _phoneSuggestion => _selectedPage?.phone ?? widget.result.phone;
  String? get _postalCodeSuggestion =>
      _selectedPage?.postalCode ?? widget.result.postalCode;
  String? get _addressSuggestion =>
      _selectedPage?.address ?? widget.result.address;
  String? get _countrySuggestion =>
      _selectedPage?.country ?? widget.result.country;
  String get _rawText => _selectedPage?.rawText ?? widget.result.rawText;

  void _selectPage(int? index) {
    if (index == null || index == _selectedPageIndex) {
      return;
    }
    setState(() => _selectedPageIndex = index);
    _nameController.text = _preferExisting(
      widget.customer.fullName,
      _fullNameSuggestion,
    );
    _emailController.text = _preferExisting(
      widget.customer.email,
      _emailSuggestion,
    );
    _phoneController.text = _preferExisting(
      widget.customer.phone,
      _phoneSuggestion,
    );
    _postalCodeController.text = _preferExisting(
      widget.customer.postalCode,
      _postalCodeSuggestion,
    );
    _addressController.text = _preferExisting(
      widget.customer.address,
      _addressSuggestion,
    );
    _countryController.text = _preferExisting(
      widget.customer.country,
      _countrySuggestion,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _postalCodeController.dispose();
    _addressController.dispose();
    _countryController.dispose();
    super.dispose();
  }

  void _apply() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      return;
    }
    Navigator.pop(
      context,
      CustomerDraft(
        fullName: name,
        email: _emptyToNull(_emailController.text),
        phone: _emptyToNull(_phoneController.text),
        postalCode: _emptyToNull(_postalCodeController.text),
        address: _emptyToNull(_addressController.text),
        country: _emptyToNull(_countryController.text),
        notes: widget.customer.notes,
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    required TextEditingController controller,
    required String? suggestion,
    int helperMaxLines = 1,
  }) {
    final candidate = suggestion?.trim() ?? '';
    final hasCandidate = candidate.isNotEmpty;

    return InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      helperText: hasCandidate ? 'OCR候補: $candidate' : 'OCR候補: 読み取りなし',
      helperMaxLines: helperMaxLines,
      suffixIcon: hasCandidate
          ? IconButton(
              tooltip: 'OCR候補を入力欄へ反映',
              onPressed: () {
                controller
                  ..text = candidate
                  ..selection = TextSelection.collapsed(
                    offset: candidate.length,
                  );
              },
              icon: const Icon(Icons.arrow_upward),
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('OCR結果を確認'),
      content: SizedBox(
        width: 850,
        height: 620,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '入力欄は現在の顧客情報を優先しています。'
              '下に表示されるOCR候補と原本を確認し、必要な項目だけ修正してください。',
            ),
            if (widget.result.pages.length > 1) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.description_outlined, size: 20),
                  const SizedBox(width: 8),
                  const Text('確認するページ:'),
                  const SizedBox(width: 12),
                  DropdownButton<int>(
                    value: _selectedPageIndex,
                    onChanged: _selectPage,
                    items: [
                      for (
                        var index = 0;
                        index < widget.result.pages.length;
                        index++
                      )
                        DropdownMenuItem<int>(
                          value: index,
                          child: Text(
                            '${widget.result.pages[index].pageNumber}ページ目',
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  const Text('ページを切り替えると入力欄もリセットされます。'),
                ],
              ),
            ],
            if (widget.result.warning != null) ...[
              const SizedBox(height: 8),
              Text(
                widget.result.warning!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    decoration: _fieldDecoration(
                      label: '氏名',
                      controller: _nameController,
                      suggestion: _fullNameSuggestion,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 180,
                  child: TextField(
                    controller: _countryController,
                    decoration: _fieldDecoration(
                      label: '国名',
                      controller: _countryController,
                      suggestion: _countrySuggestion,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _phoneController,
                    decoration: _fieldDecoration(
                      label: '電話番号',
                      controller: _phoneController,
                      suggestion: _phoneSuggestion,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emailController,
              decoration: _fieldDecoration(
                label: 'メールアドレス',
                controller: _emailController,
                suggestion: _emailSuggestion,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 180,
                  child: TextField(
                    controller: _postalCodeController,
                    decoration: _fieldDecoration(
                      label: '郵便番号',
                      controller: _postalCodeController,
                      suggestion: _postalCodeSuggestion,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _addressController,
                    minLines: 2,
                    maxLines: 3,
                    decoration: _fieldDecoration(
                      label: '住所',
                      controller: _addressController,
                      suggestion: _addressSuggestion,
                      helperMaxLines: 2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'OCRが読み取った全文（参考）',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    _rawText.isEmpty ? '文字を認識できませんでした。' : _rawText,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('反映しない'),
        ),
        FilledButton.icon(
          onPressed: _apply,
          icon: const Icon(Icons.check),
          label: const Text('顧客情報へ反映'),
        ),
      ],
    );
  }

  static String _preferExisting(String? existing, String? suggestion) {
    final current = existing?.trim();
    if (current != null && current.isNotEmpty) {
      return current;
    }
    return suggestion?.trim() ?? '';
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
