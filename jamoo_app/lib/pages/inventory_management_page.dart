import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/inventory.dart';
import '../repositories/inventory_repository.dart';
import '../services/inventory_csv_service.dart';
import '../services/inventory_lan_server_service.dart';

class InventoryManagementPage extends StatefulWidget {
  const InventoryManagementPage({super.key, required this.facilityName});

  final String facilityName;

  @override
  State<InventoryManagementPage> createState() =>
      _InventoryManagementPageState();
}

class _InventoryManagementPageState extends State<InventoryManagementPage> {
  final InventoryRepository _repository = const InventoryRepository();
  late final InventoryCsvService _csvService = InventoryCsvService(
    repository: _repository,
  );
  final TextEditingController _searchController = TextEditingController();

  Future<InventoryDashboardData>? _future;
  StreamSubscription<void>? _inventoryChangeSubscription;
  InventoryLanServerStatus? _connectionStatus;
  bool _lowStockOnly = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
    _inventoryChangeSubscription = InventoryLanServerService.instance.changes
        .listen((_) {
          if (mounted) _reload();
        });
    if (InventoryLanServerService.instance.isRunning) {
      unawaited(_restoreConnectionStatus());
    }
  }

  @override
  void dispose() {
    _inventoryChangeSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _future = _repository.loadDashboard(
        searchText: _searchController.text,
        lowStockOnly: _lowStockOnly,
      );
    });
  }

  Future<void> _restoreConnectionStatus() async {
    final status = await InventoryLanServerService.instance.status();
    if (mounted) setState(() => _connectionStatus = status);
  }

  Future<void> _addOrEditItem([InventoryItem? existing]) async {
    final result = await _showItemDialog(existing);
    if (result == null) return;

    try {
      await _repository.saveItem(result);
      if (!mounted) return;
      _showSnackBar(existing == null ? '商品を登録しました。' : '商品情報を更新しました。');
      _reload();
    } catch (error) {
      if (!mounted) return;
      await _showError('商品を保存できませんでした', error);
    }
  }

  Future<void> _recordMovement(InventoryItem item) async {
    final request = await _showMovementDialog(item);
    if (request == null) return;

    try {
      await _repository.recordMovement(
        item: item,
        type: request.type,
        quantity: request.quantity,
        unitPriceYen: request.unitPriceYen,
        note: request.note,
      );
      if (!mounted) return;
      _showSnackBar('${request.type.label}を記録しました。');
      _reload();
    } catch (error) {
      if (!mounted) return;
      await _showError('${request.type.label}を記録できませんでした', error);
    }
  }

  Future<void> _deactivateItem(InventoryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('商品を一覧から外しますか？'),
        content: Text(
          '「${item.name}」を使用停止にします。\n'
          '過去の入出庫履歴は削除されません。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('使用停止'),
          ),
        ],
      ),
    );
    if (confirmed != true || item.id == null) return;

    try {
      await _repository.deactivateItem(item.id!);
      if (!mounted) return;
      _showSnackBar('商品を使用停止にしました。');
      _reload();
    } catch (error) {
      if (!mounted) return;
      await _showError('商品を使用停止にできませんでした', error);
    }
  }

  Future<void> _moveItem(InventoryItem item, int offset) async {
    final itemId = item.id;
    if (itemId == null || _busy) return;
    setState(() => _busy = true);
    try {
      await _repository.moveItem(itemId: itemId, offset: offset);
      if (!mounted) return;
      _reload();
    } catch (error) {
      if (!mounted) return;
      await _showError('商品を並び替えできませんでした', error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearTransactionHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('入出庫履歴をクリアしますか？'),
        content: const Text(
          'すべての入荷・販売・廃棄・棚卸調整の履歴を削除します。\n\n'
          '登録商品と現在庫は削除されません。'
          '削除した履歴は元に戻せません。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('履歴をクリア'),
          ),
        ],
      ),
    );
    if (confirmed != true || _busy) return;

    setState(() => _busy = true);
    try {
      final deleted = await _repository.clearTransactionHistory();
      if (!mounted) return;
      _showSnackBar('入出庫履歴を$deleted件削除しました。商品と現在庫は維持されています。');
      _reload();
    } catch (error) {
      if (!mounted) return;
      await _showError('入出庫履歴をクリアできませんでした', error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importCsv() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await _csvService.pickAndImport();
      if (!mounted || result == null) return;
      final detail = result.errors.isEmpty
          ? result.summary
          : '${result.summary}\n\n${result.errors.take(10).join('\n')}';
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('在庫表CSVを取り込みました'),
          content: SelectableText(detail),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('閉じる'),
            ),
          ],
        ),
      );
      _reload();
    } catch (error) {
      if (!mounted) return;
      await _showError('CSVを取り込めませんでした', error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportCsv() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final items = await _repository.loadItems();
      final path = await _csvService.exportCsv(items);
      if (!mounted || path == null) return;
      _showSnackBar('在庫表CSVを保存しました。');
    } catch (error) {
      if (!mounted) return;
      await _showError('CSVを保存できませんでした', error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showDeviceConnection() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final status = await InventoryLanServerService.instance.start(
        facilityName: widget.facilityName,
      );
      if (!mounted) return;
      setState(() => _connectionStatus = status);
      _showSnackBar('端末接続を開始しました。');
    } catch (error) {
      if (!mounted) return;
      await _showError('端末接続を開始できませんでした', error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showConnectionDetails() async {
    final status = _connectionStatus;
    if (status == null) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _InventoryDeviceConnectionDialog(
        status: status,
        onStop: () async {
          await InventoryLanServerService.instance.stop();
          if (dialogContext.mounted) Navigator.of(dialogContext).pop();
          if (mounted) {
            setState(() => _connectionStatus = null);
            _showSnackBar('端末接続を停止しました。');
          }
        },
      ),
    );
  }

  Future<void> _stopDeviceConnection() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await InventoryLanServerService.instance.stop();
      if (!mounted) return;
      setState(() => _connectionStatus = null);
      _showSnackBar('端末接続を停止しました。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showError(String title, Object error) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SelectableText(error.toString()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('在庫・販売管理'),
        actions: [
          OutlinedButton.icon(
            onPressed: _busy ? null : _showDeviceConnection,
            icon: const Icon(Icons.devices_outlined),
            label: Text(
              InventoryLanServerService.instance.isRunning ? '端末接続中' : '端末接続',
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _importCsv,
            icon: const Icon(Icons.file_upload_outlined),
            label: const Text('CSV取込'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _exportCsv,
            icon: const Icon(Icons.file_download_outlined),
            label: const Text('CSV出力'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _busy ? null : () => _addOrEditItem(),
            icon: const Icon(Icons.add),
            label: const Text('商品を追加'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_connectionStatus != null)
            _InventoryConnectionStatusCard(
              status: _connectionStatus!,
              onDetails: _showConnectionDetails,
              onStop: _stopDeviceConnection,
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onSubmitted: (_) => _reload(),
                    decoration: InputDecoration(
                      labelText: '商品を検索',
                      hintText: '商品名・分類・商品コード・バーコード',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        tooltip: '検索をクリア',
                        onPressed: () {
                          _searchController.clear();
                          _reload();
                        },
                        icon: const Icon(Icons.clear),
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilterChip(
                  selected: _lowStockOnly,
                  avatar: const Icon(Icons.warning_amber_rounded, size: 18),
                  label: const Text('在庫不足のみ'),
                  onSelected: (value) {
                    setState(() => _lowStockOnly = value);
                    _reload();
                  },
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '再読み込み',
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<InventoryDashboardData>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _InventoryErrorView(
                    error: snapshot.error,
                    onRetry: _reload,
                  );
                }
                final data = snapshot.data;
                if (data == null) return const SizedBox.shrink();
                return _InventoryBody(
                  data: data,
                  onEdit: _addOrEditItem,
                  onMovement: _recordMovement,
                  onDeactivate: _deactivateItem,
                  onClearHistory: _clearTransactionHistory,
                  onMoveItem: _moveItem,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<InventoryItem?> _showItemDialog(InventoryItem? existing) async {
    final formKey = GlobalKey<FormState>();
    final sku = TextEditingController(text: existing?.sku ?? '');
    final barcode = TextEditingController(text: existing?.barcode ?? '');
    final name = TextEditingController(text: existing?.name ?? '');
    final category = TextEditingController(text: existing?.category ?? '販売商品');
    final unit = TextEditingController(text: existing?.unit ?? '個');
    final initialStock = TextEditingController(
      text: existing == null
          ? '0'
          : formatInventoryQuantity(existing.currentStock),
    );
    final reorder = TextEditingController(
      text: formatInventoryQuantity(existing?.reorderLevel ?? 0),
    );
    final cost = TextEditingController(
      text: existing?.costPriceYen?.toString() ?? '',
    );
    final sale = TextEditingController(
      text: existing?.salePriceYen?.toString() ?? '',
    );
    final supplier = TextEditingController(text: existing?.supplier ?? '');
    final notes = TextEditingController(text: existing?.notes ?? '');
    var saleEnabled = existing?.saleEnabled ?? true;

    final result = await showDialog<InventoryItem>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? '商品を追加' : '商品情報を編集'),
          content: SizedBox(
            width: 680,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _DialogField(
                      controller: name,
                      label: '商品名（必須）',
                      width: 434,
                      validator: _requiredValidator,
                    ),
                    _DialogField(controller: unit, label: '単位', width: 180),
                    _DialogField(controller: sku, label: '商品コード', width: 210),
                    _DialogField(
                      controller: barcode,
                      label: 'バーコード・QRコード',
                      width: 404,
                    ),
                    _DialogField(controller: category, label: '分類', width: 210),
                    _DialogField(
                      controller: initialStock,
                      label: existing == null ? '初期在庫' : '現在庫',
                      width: 194,
                      enabled: existing == null,
                      numeric: true,
                    ),
                    _DialogField(
                      controller: reorder,
                      label: '最低在庫',
                      width: 194,
                      numeric: true,
                    ),
                    _DialogField(
                      controller: cost,
                      label: '仕入単価（円）',
                      width: 194,
                      numeric: true,
                    ),
                    _DialogField(
                      controller: sale,
                      label: '販売価格（円）',
                      width: 194,
                      numeric: true,
                    ),
                    _DialogField(
                      controller: supplier,
                      label: '仕入先',
                      width: 404,
                    ),
                    SizedBox(
                      width: 210,
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('販売対象'),
                        value: saleEnabled,
                        onChanged: (value) {
                          setDialogState(() => saleEnabled = value);
                        },
                      ),
                    ),
                    _DialogField(
                      controller: notes,
                      label: '備考',
                      width: 626,
                      maxLines: 2,
                    ),
                    if (existing != null)
                      const SizedBox(
                        width: 626,
                        child: Text('在庫数の変更は「入出庫・販売」ボタンから記録します。'),
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
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() != true) return;
                final stockValue = double.tryParse(initialStock.text.trim());
                final reorderValue = double.tryParse(reorder.text.trim());
                if (stockValue == null ||
                    stockValue < 0 ||
                    reorderValue == null ||
                    reorderValue < 0) {
                  return;
                }
                Navigator.of(context).pop(
                  InventoryItem(
                    id: existing?.id,
                    syncKey:
                        existing?.syncKey ??
                        InventoryRepository.createSyncKey(),
                    sku: _nullable(sku.text),
                    barcode: _nullable(barcode.text),
                    name: name.text.trim(),
                    category: category.text.trim(),
                    unit: unit.text.trim().isEmpty ? '個' : unit.text.trim(),
                    currentStock: existing?.currentStock ?? stockValue,
                    reorderLevel: reorderValue,
                    costPriceYen: _nullableInt(cost.text),
                    salePriceYen: _nullableInt(sale.text),
                    supplier: _nullable(supplier.text),
                    saleEnabled: saleEnabled,
                    active: existing?.active ?? true,
                    notes: _nullable(notes.text),
                    createdAt: existing?.createdAt,
                    updatedAt: existing?.updatedAt,
                  ),
                );
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );

    for (final controller in [
      sku,
      barcode,
      name,
      category,
      unit,
      initialStock,
      reorder,
      cost,
      sale,
      supplier,
      notes,
    ]) {
      controller.dispose();
    }
    return result;
  }

  Future<_InventoryMovementRequest?> _showMovementDialog(
    InventoryItem item,
  ) async {
    final quantity = TextEditingController(text: '1');
    final unitPrice = TextEditingController();
    final note = TextEditingController();
    var type = InventoryTransactionType.sale;
    if (!item.saleEnabled) type = InventoryTransactionType.purchase;

    void applyDefaultPrice() {
      final price = type == InventoryTransactionType.sale
          ? item.salePriceYen
          : type == InventoryTransactionType.purchase
          ? item.costPriceYen
          : null;
      unitPrice.text = price?.toString() ?? '';
    }

    applyDefaultPrice();
    final result = await showDialog<_InventoryMovementRequest>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('${item.name}：入出庫・販売'),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '現在庫：${formatInventoryQuantity(item.currentStock)} ${item.unit}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<InventoryTransactionType>(
                  initialValue: type,
                  decoration: const InputDecoration(
                    labelText: '処理',
                    border: OutlineInputBorder(),
                  ),
                  items: InventoryTransactionType.values
                      .where(
                        (value) =>
                            item.saleEnabled ||
                            value != InventoryTransactionType.sale,
                      )
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.label),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) return;
                    setDialogState(() {
                      type = value;
                      applyDefaultPrice();
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: quantity,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: type == InventoryTransactionType.adjustment
                        ? '調整後の実在庫'
                        : '数量',
                    suffixText: item.unit,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: unitPrice,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '単価（円・任意）',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: note,
                  decoration: const InputDecoration(
                    labelText: '備考（任意）',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () {
                final parsedQuantity = double.tryParse(quantity.text.trim());
                if (parsedQuantity == null || parsedQuantity < 0) return;
                Navigator.of(context).pop(
                  _InventoryMovementRequest(
                    type: type,
                    quantity: parsedQuantity,
                    unitPriceYen: _nullableInt(unitPrice.text),
                    note: _nullable(note.text),
                  ),
                );
              },
              child: const Text('記録'),
            ),
          ],
        ),
      ),
    );
    quantity.dispose();
    unitPrice.dispose();
    note.dispose();
    return result;
  }

  static String? _requiredValidator(String? value) =>
      value == null || value.trim().isEmpty ? '入力してください。' : null;

  static String? _nullable(String value) =>
      value.trim().isEmpty ? null : value.trim();

  static int? _nullableInt(String value) =>
      int.tryParse(value.replaceAll(',', '').replaceAll('¥', '').trim());
}

class _InventoryConnectionStatusCard extends StatelessWidget {
  const _InventoryConnectionStatusCard({
    required this.status,
    required this.onDetails,
    required this.onStop,
  });

  final InventoryLanServerStatus status;
  final VoidCallback onDetails;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final url = status.serverUrls.isEmpty
        ? '接続アドレスを取得できません'
        : status.serverUrls.first;
    final token = status.accessToken ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Card(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.devices_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '端末接続中',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SelectableText('$url    接続コード $token'),
                  ],
                ),
              ),
              IconButton(
                tooltip: '接続情報をコピー',
                onPressed: () => Clipboard.setData(
                  ClipboardData(text: '$url\n接続コード: $token'),
                ),
                icon: const Icon(Icons.copy_outlined),
              ),
              TextButton(onPressed: onDetails, child: const Text('詳細')),
              TextButton(onPressed: onStop, child: const Text('停止')),
            ],
          ),
        ),
      ),
    );
  }
}

class _InventoryDeviceConnectionDialog extends StatelessWidget {
  const _InventoryDeviceConnectionDialog({
    required this.status,
    required this.onStop,
  });

  final InventoryLanServerStatus status;
  final Future<void> Function() onStop;

  @override
  Widget build(BuildContext context) {
    final urls = status.serverUrls;
    final accessToken = status.accessToken ?? '';
    return AlertDialog(
      title: const Text('スマホ・Chromebookを接続'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Windows PCと端末を同じWi-Fiに接続し、'
                '端末のChromeまたはSafariで次のアドレスを開いてください。',
              ),
              const SizedBox(height: 16),
              Text('接続アドレス', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              if (urls.isEmpty)
                const Text('接続先を取得できません。Wi-Fi接続を確認してください。')
              else
                for (final url in urls)
                  Card(
                    child: ListTile(
                      title: SelectableText(url),
                      trailing: IconButton(
                        tooltip: 'コピー',
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: url));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('接続アドレスをコピーしました。')),
                            );
                          }
                        },
                        icon: const Icon(Icons.copy_outlined),
                      ),
                    ),
                  ),
              const SizedBox(height: 14),
              Text('接続コード', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              Row(
                children: [
                  SelectableText(
                    accessToken,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 5,
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    tooltip: 'コードをコピー',
                    onPressed: accessToken.isEmpty
                        ? null
                        : () => Clipboard.setData(
                            ClipboardData(text: accessToken),
                          ),
                    icon: const Icon(Icons.copy_outlined),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                '・Windowsの確認が出たら「プライベートネットワーク」のアクセスを許可\n'
                '・接続中はJamooManagerとWindows PCを起動したままにする\n'
                '・同じ館内Wi-Fi上でのみ利用でき、モバイル通信は不要',
              ),
              const SizedBox(height: 10),
              const Text(
                '「閉じる」で画面を閉じても接続は継続します。'
                '「接続を停止」した後は、再度「端末接続」を押し、'
                '端末のブラウザを更新してください。',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: onStop,
          icon: const Icon(Icons.link_off),
          label: const Text('接続を停止'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('閉じる'),
        ),
      ],
    );
  }
}

class _InventoryBody extends StatelessWidget {
  const _InventoryBody({
    required this.data,
    required this.onEdit,
    required this.onMovement,
    required this.onDeactivate,
    required this.onClearHistory,
    required this.onMoveItem,
  });

  final InventoryDashboardData data;
  final ValueChanged<InventoryItem> onEdit;
  final ValueChanged<InventoryItem> onMovement;
  final ValueChanged<InventoryItem> onDeactivate;
  final VoidCallback onClearHistory;
  final void Function(InventoryItem item, int offset) onMoveItem;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _SummaryCard(
              label: '登録商品',
              value: '${data.activeItemCount}件',
              icon: Icons.inventory_2_outlined,
            ),
            _SummaryCard(
              label: '在庫不足',
              value: '${data.lowStockCount}件',
              icon: Icons.warning_amber_rounded,
              warning: data.lowStockCount > 0,
            ),
            _SummaryCard(
              label: '在庫原価',
              value: _yen(data.stockValueYen),
              icon: Icons.warehouse_outlined,
            ),
            _SummaryCard(
              label: '本日の販売',
              value: _yen(data.todaySalesYen),
              icon: Icons.point_of_sale_outlined,
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text('商品一覧', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        if (data.items.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Center(child: Text('該当する商品がありません。商品を追加してください。')),
            ),
          )
        else
          for (final item in data.items)
            _InventoryItemCard(
              item: item,
              onEdit: () => onEdit(item),
              onMovement: () => onMovement(item),
              onDeactivate: () => onDeactivate(item),
              onMoveUp: () => onMoveItem(item, -1),
              onMoveDown: () => onMoveItem(item, 1),
            ),
        const SizedBox(height: 22),
        Row(
          children: [
            Text('最近の入出庫履歴', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(width: 8),
            Text('最大50件', style: Theme.of(context).textTheme.bodySmall),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: data.recentTransactions.isEmpty
                  ? null
                  : onClearHistory,
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('履歴をクリア'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (data.recentTransactions.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('入出庫履歴はまだありません。'),
            ),
          )
        else
          Card(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('日時')),
                  DataColumn(label: Text('商品')),
                  DataColumn(label: Text('処理')),
                  DataColumn(label: Text('増減'), numeric: true),
                  DataColumn(label: Text('処理後在庫'), numeric: true),
                  DataColumn(label: Text('金額'), numeric: true),
                  DataColumn(label: Text('備考')),
                ],
                rows: data.recentTransactions
                    .map((transaction) {
                      return DataRow(
                        cells: [
                          DataCell(
                            Text(_dateTime(transaction.occurredAt.toLocal())),
                          ),
                          DataCell(Text(transaction.itemName)),
                          DataCell(Text(transaction.type.label)),
                          DataCell(
                            Text(
                              '${transaction.quantityChange > 0 ? '+' : ''}${formatInventoryQuantity(transaction.quantityChange)}',
                            ),
                          ),
                          DataCell(
                            Text(
                              formatInventoryQuantity(transaction.stockAfter),
                            ),
                          ),
                          DataCell(
                            Text(
                              transaction.totalYen == null
                                  ? ''
                                  : _yen(transaction.totalYen!),
                            ),
                          ),
                          DataCell(Text(transaction.note ?? '')),
                        ],
                      );
                    })
                    .toList(growable: false),
              ),
            ),
          ),
      ],
    );
  }
}

class _InventoryItemCard extends StatelessWidget {
  const _InventoryItemCard({
    required this.item,
    required this.onEdit,
    required this.onMovement,
    required this.onDeactivate,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final InventoryItem item;
  final VoidCallback onEdit;
  final VoidCallback onMovement;
  final VoidCallback onDeactivate;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: item.isLowStock
                    ? colorScheme.errorContainer
                    : colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                item.isLowStock
                    ? Icons.warning_amber_rounded
                    : Icons.inventory_2_outlined,
                color: item.isLowStock
                    ? colorScheme.onErrorContainer
                    : colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (item.category.isNotEmpty) item.category,
                      if ((item.sku ?? '').isNotEmpty) '商品コード ${item.sku}',
                      if ((item.barcode ?? '').isNotEmpty)
                        'コード ${item.barcode}',
                    ].join('・'),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('現在庫', style: Theme.of(context).textTheme.bodySmall),
                  Text(
                    '${formatInventoryQuantity(item.currentStock)} ${item.unit}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: item.isLowStock ? colorScheme.error : null,
                    ),
                  ),
                  Text(
                    '最低 ${formatInventoryQuantity(item.reorderLevel)} ${item.unit}',
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '販売 ${item.salePriceYen == null ? '－' : _yen(item.salePriceYen!)}',
                  ),
                  Text(
                    '仕入 ${item.costPriceYen == null ? '－' : _yen(item.costPriceYen!)}',
                  ),
                  if (!item.saleEnabled) const Text('販売対象外'),
                ],
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: onMovement,
              icon: const Icon(Icons.swap_vert),
              label: const Text('入出庫・販売'),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: '商品情報を編集',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
            PopupMenuButton<String>(
              tooltip: 'その他',
              onSelected: (value) {
                if (value == 'deactivate') onDeactivate();
                if (value == 'move_up') onMoveUp();
                if (value == 'move_down') onMoveDown();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'move_up',
                  child: ListTile(
                    leading: Icon(Icons.arrow_upward),
                    title: Text('上へ移動'),
                  ),
                ),
                PopupMenuItem(
                  value: 'move_down',
                  child: ListTile(
                    leading: Icon(Icons.arrow_downward),
                    title: Text('下へ移動'),
                  ),
                ),
                PopupMenuItem(value: 'deactivate', child: Text('使用停止にする')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    this.warning = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: warning
            ? colorScheme.errorContainer
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: warning ? colorScheme.onErrorContainer : colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label),
              Text(
                value,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DialogField extends StatelessWidget {
  const _DialogField({
    required this.controller,
    required this.label,
    required this.width,
    this.enabled = true,
    this.numeric = false,
    this.maxLines = 1,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final double width;
  final bool enabled;
  final bool numeric;
  final int maxLines;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : null,
        maxLines: maxLines,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

class _InventoryMovementRequest {
  const _InventoryMovementRequest({
    required this.type,
    required this.quantity,
    this.unitPriceYen,
    this.note,
  });

  final InventoryTransactionType type;
  final double quantity;
  final int? unitPriceYen;
  final String? note;
}

class _InventoryErrorView extends StatelessWidget {
  const _InventoryErrorView({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            const Text('在庫データを読み込めませんでした。'),
            const SizedBox(height: 8),
            SelectableText(error.toString()),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('再試行'),
            ),
          ],
        ),
      ),
    );
  }
}

String _yen(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return '${value < 0 ? '-' : ''}¥$buffer';
}

String _dateTime(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/'
      '${value.day.toString().padLeft(2, '0')} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}
