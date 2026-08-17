import 'package:flutter/material.dart';

import '../services/postal_code_lookup_service.dart';

class PostalCodeLookupButton extends StatefulWidget {
  const PostalCodeLookupButton({
    super.key,
    required this.addressController,
    required this.postalCodeController,
  });

  final TextEditingController addressController;
  final TextEditingController postalCodeController;

  @override
  State<PostalCodeLookupButton> createState() => _PostalCodeLookupButtonState();
}

class _PostalCodeLookupButtonState extends State<PostalCodeLookupButton> {
  static const _service = PostalCodeLookupService();
  bool _lookingUp = false;

  Future<void> _lookup() async {
    final address = widget.addressController.text.trim();
    if (address.isEmpty) {
      _showMessage('先に住所を入力してください。');
      return;
    }

    setState(() => _lookingUp = true);
    try {
      final candidates = await _service.findByAddress(address);
      if (!mounted) return;
      if (candidates.isEmpty) {
        _showMessage('郵便番号を見つけられませんでした。町名までの住所を確認してください。');
        return;
      }

      final selected = candidates.length == 1
          ? candidates.first
          : await _selectCandidate(candidates);
      if (!mounted || selected == null) return;

      final postalCode = selected.formattedPostalCode;
      widget.postalCodeController
        ..text = postalCode
        ..selection = TextSelection.collapsed(offset: postalCode.length);
      _showMessage('郵便番号 $postalCode を入力しました。');
    } on PostalCodeLookupException catch (error) {
      if (mounted) {
        _showMessage(error.message);
      }
    } catch (error) {
      if (mounted) {
        _showMessage('郵便番号を検索できませんでした。$error');
      }
    } finally {
      if (mounted) {
        setState(() => _lookingUp = false);
      }
    }
  }

  Future<PostalCodeLookupCandidate?> _selectCandidate(
    List<PostalCodeLookupCandidate> candidates,
  ) {
    return showDialog<PostalCodeLookupCandidate>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('郵便番号を選択'),
        content: SizedBox(
          width: 520,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: candidates.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final candidate = candidates[index];
              return ListTile(
                leading: const Icon(Icons.markunread_mailbox_outlined),
                title: Text(candidate.formattedPostalCode),
                subtitle: Text(candidate.displayAddress),
                onTap: () => Navigator.of(context).pop(candidate),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: _lookingUp ? null : _lookup,
          icon: _lookingUp
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.manage_search),
          label: Text(_lookingUp ? '検索中…' : '住所から郵便番号を検索'),
        ),
        const SizedBox(height: 3),
        Text(
          '検索時のみ住所をHeartRails Geo APIへ送信します。'
          '出典：「位置参照情報ダウンロードサービス」（国土交通省）を加工して作成',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
