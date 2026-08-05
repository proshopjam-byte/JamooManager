import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../repositories/settings_repository.dart';
import '../services/environment_check_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.initialSettings,
  });

  final AppSettings initialSettings;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final SettingsRepository _repository =
      const SettingsRepository();

  late final TextEditingController _appNameController;
  late final TextEditingController _facilityNameController;
  late final TextEditingController _bookingSourceController;
  late final TextEditingController _timeZoneController;
  late final TextEditingController _managerRootPathController;

  late bool _showPrice;
  late bool _showReservationNumber;
  late bool _showArrivalTime;

  bool _isSaving = false;
  bool _isCheckingEnvironment = false;

  @override
  void initState() {
    super.initState();

    final settings = widget.initialSettings;

    _appNameController = TextEditingController(
      text: settings.appName,
    );
    _facilityNameController = TextEditingController(
      text: settings.facilityName,
    );
    _bookingSourceController = TextEditingController(
      text: settings.bookingSourceName,
    );
    _timeZoneController = TextEditingController(
      text: settings.timeZone,
    );
    _managerRootPathController = TextEditingController(
      text: settings.managerRootPath ?? '',
    );

    _showPrice = settings.showPrice;
    _showReservationNumber =
        settings.showReservationNumber;
    _showArrivalTime = settings.showArrivalTime;
  }

  @override
  void dispose() {
    _appNameController.dispose();
    _facilityNameController.dispose();
    _bookingSourceController.dispose();
    _timeZoneController.dispose();
    _managerRootPathController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) {
      return;
    }

    final appName = _appNameController.text.trim();
    final facilityName =
        _facilityNameController.text.trim();
    final bookingSourceName =
        _bookingSourceController.text.trim();
    final timeZone = _timeZoneController.text.trim();
    final managerRootPath =
        _managerRootPathController.text.trim();

    if (appName.isEmpty ||
        facilityName.isEmpty ||
        bookingSourceName.isEmpty ||
        timeZone.isEmpty) {
      await _showMessage(
        title: '入力を確認してください',
        message: 'アプリ名、施設名、予約サイト名、'
            'タイムゾーンを入力してください。',
      );
      return;
    }

    final settings = AppSettings(
      appName: appName,
      facilityName: facilityName,
      bookingSourceName: bookingSourceName,
      timeZone: timeZone,
      showPrice: _showPrice,
      showReservationNumber:
          _showReservationNumber,
      showArrivalTime: _showArrivalTime,
      managerRootPath:
          managerRootPath.isEmpty ? null : managerRootPath,
    );

    setState(() {
      _isSaving = true;
    });

    try {
      await _repository.save(settings);

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(settings);
    } on SettingsRepositoryException catch (error) {
      if (!mounted) {
        return;
      }

      await _showMessage(
        title: '設定を保存できませんでした',
        message: error.message,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      await _showMessage(
        title: '予期しないエラーが発生しました',
        message: error.toString(),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _reset() async {
    final shouldReset = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('初期設定に戻しますか？'),
          content: const Text(
            '施設名や表示設定をJamooManagerの初期状態に戻します。',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              child: const Text('初期設定に戻す'),
            ),
          ],
        );
      },
    );

    if (shouldReset != true) {
      return;
    }

    final defaults = AppSettings.defaults;

    setState(() {
      _appNameController.text = defaults.appName;
      _facilityNameController.text =
          defaults.facilityName;
      _bookingSourceController.text =
          defaults.bookingSourceName;
      _timeZoneController.text = defaults.timeZone;
      _managerRootPathController.text =
          defaults.managerRootPath ?? '';
      _showPrice = defaults.showPrice;
      _showReservationNumber =
          defaults.showReservationNumber;
      _showArrivalTime = defaults.showArrivalTime;
    });
  }

  void _useCurrentProjectPath() {
    setState(() {
      _managerRootPathController.text =
          r'C:\work\JamooManager';
    });
  }

  Future<void> _runEnvironmentCheck() async {
    if (_isCheckingEnvironment) {
      return;
    }

    final enteredPath =
        _managerRootPathController.text.trim();

    setState(() {
      _isCheckingEnvironment = true;
    });

    try {
      final service = EnvironmentCheckService(
        projectRootPath:
            enteredPath.isEmpty ? null : enteredPath,
      );

      final report = await service.run();

      if (!mounted) {
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (context) {
          return _EnvironmentCheckDialog(
            report: report,
          );
        },
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      await _showMessage(
        title: '環境診断を実行できませんでした',
        message: error.toString(),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingEnvironment = false;
        });
      }
    }
  }

  Future<void> _showMessage({
    required String title,
    required String message,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: SelectableText(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('閉じる'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final controlsDisabled =
        _isSaving || _isCheckingEnvironment;

    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
        actions: [
          TextButton.icon(
            onPressed: controlsDisabled ? null : _save,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(
              _isSaving ? '保存中' : '保存',
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          20,
          16,
          20,
          32,
        ),
        children: [
          _SectionCard(
            title: '施設情報',
            icon: Icons.hotel_outlined,
            children: [
              TextField(
                controller: _appNameController,
                enabled: !controlsDisabled,
                decoration: const InputDecoration(
                  labelText: 'アプリ名',
                  hintText: 'JamooManager',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _facilityNameController,
                enabled: !controlsDisabled,
                decoration: const InputDecoration(
                  labelText: '施設名',
                  hintText: 'Vegetarian House Jamoo',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _bookingSourceController,
                enabled: !controlsDisabled,
                decoration: const InputDecoration(
                  labelText: '予約サイト名',
                  hintText: 'Booking.com',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _timeZoneController,
                enabled: !controlsDisabled,
                decoration: const InputDecoration(
                  labelText: 'タイムゾーン',
                  hintText: 'Asia/Tokyo',
                  helperText:
                      '日本の施設はAsia/Tokyoのままで大丈夫です。',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'データ保存場所',
            icon: Icons.folder_outlined,
            children: [
              TextField(
                controller: _managerRootPathController,
                enabled: !controlsDisabled,
                decoration: const InputDecoration(
                  labelText: 'JamooManager保存場所',
                  hintText: r'C:\work\JamooManager',
                  helperText:
                      '空欄の場合はアプリが自動で探します。',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(
                    Icons.folder_open_outlined,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: controlsDisabled
                      ? null
                      : _useCurrentProjectPath,
                  icon: const Icon(Icons.home_work_outlined),
                  label: const Text(
                    r'C:\work\JamooManager を入力',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '別のPCや別の宿へ配布する場合は、'
                'そのPCに保存したJamooManagerフォルダを入力します。',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: '環境診断',
            icon: Icons.health_and_safety_outlined,
            children: [
              const Text(
                'Node.js、Playwright、booking.js、'
                '予約JSONなど、動作に必要な環境を確認します。',
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: controlsDisabled
                    ? null
                    : _runEnvironmentCheck,
                icon: _isCheckingEnvironment
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(
                        Icons.fact_check_outlined,
                      ),
                label: Text(
                  _isCheckingEnvironment
                      ? '診断中'
                      : '環境を診断',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: '予約カードの表示項目',
            icon: Icons.visibility_outlined,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('予約金額を表示'),
                subtitle: const Text(
                  '予約カードと合計金額に料金を表示します。',
                ),
                value: _showPrice,
                onChanged: controlsDisabled
                    ? null
                    : (value) {
                        setState(() {
                          _showPrice = value;
                        });
                      },
              ),
              const Divider(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('予約番号を表示'),
                subtitle: const Text(
                  '予約カードにBooking.comの予約番号を表示します。',
                ),
                value: _showReservationNumber,
                onChanged: controlsDisabled
                    ? null
                    : (value) {
                        setState(() {
                          _showReservationNumber = value;
                        });
                      },
              ),
              const Divider(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('到着予定時刻を表示'),
                subtitle: const Text(
                  '予約カードにお客様の到着予定時刻を表示します。',
                ),
                value: _showArrivalTime,
                onChanged: controlsDisabled
                    ? null
                    : (value) {
                        setState(() {
                          _showArrivalTime = value;
                        });
                      },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  const Icon(Icons.restore),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          '初期設定に戻す',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '入力内容をVegetarian House Jamooの初期状態へ戻します。',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed:
                        controlsDisabled ? null : _reset,
                    child: const Text('戻す'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EnvironmentCheckDialog extends StatelessWidget {
  const _EnvironmentCheckDialog({
    required this.report,
  });

  final EnvironmentCheckReport report;

  @override
  Widget build(BuildContext context) {
    final summary = report.hasErrors
        ? 'エラー ${report.errorCount}件'
        : report.hasWarnings
            ? '注意 ${report.warningCount}件'
            : 'すべて正常です';

    return AlertDialog(
      title: const Text('環境診断結果'),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _EnvironmentSummary(
                report: report,
                summary: summary,
              ),
              const SizedBox(height: 14),
              for (final item in report.items) ...[
                _EnvironmentCheckRow(item: item),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('閉じる'),
        ),
      ],
    );
  }
}

class _EnvironmentSummary extends StatelessWidget {
  const _EnvironmentSummary({
    required this.report,
    required this.summary,
  });

  final EnvironmentCheckReport report;
  final String summary;

  @override
  Widget build(BuildContext context) {
    final status = report.hasErrors
        ? EnvironmentCheckStatus.error
        : report.hasWarnings
            ? EnvironmentCheckStatus.warning
            : EnvironmentCheckStatus.ok;

    final presentation =
        _statusPresentation(context, status);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: presentation.backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            presentation.icon,
            color: presentation.foregroundColor,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              summary,
              style: TextStyle(
                color: presentation.foregroundColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EnvironmentCheckRow extends StatelessWidget {
  const _EnvironmentCheckRow({
    required this.item,
  });

  final EnvironmentCheckItem item;

  @override
  Widget build(BuildContext context) {
    final presentation =
        _statusPresentation(context, item.status);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(
          color: presentation.foregroundColor
              .withValues(alpha: 0.35),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Icon(
            presentation.icon,
            color: presentation.foregroundColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(item.message),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

_StatusPresentation _statusPresentation(
  BuildContext context,
  EnvironmentCheckStatus status,
) {
  final colorScheme =
      Theme.of(context).colorScheme;

  switch (status) {
    case EnvironmentCheckStatus.ok:
      return _StatusPresentation(
        icon: Icons.check_circle_outline,
        foregroundColor: colorScheme.primary,
        backgroundColor:
            colorScheme.primaryContainer,
      );
    case EnvironmentCheckStatus.warning:
      return _StatusPresentation(
        icon: Icons.warning_amber_rounded,
        foregroundColor:
            colorScheme.onTertiaryContainer,
        backgroundColor:
            colorScheme.tertiaryContainer,
      );
    case EnvironmentCheckStatus.error:
      return _StatusPresentation(
        icon: Icons.error_outline,
        foregroundColor:
            colorScheme.onErrorContainer,
        backgroundColor:
            colorScheme.errorContainer,
      );
  }
}

class _StatusPresentation {
  const _StatusPresentation({
    required this.icon,
    required this.foregroundColor,
    required this.backgroundColor,
  });

  final IconData icon;
  final Color foregroundColor;
  final Color backgroundColor;
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  color: Theme.of(context)
                      .colorScheme
                      .primary,
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 18),
            ...children,
          ],
        ),
      ),
    );
  }
}
