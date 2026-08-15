import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/customer.dart';
import '../repositories/customer_repository.dart';

class CustomerDocumentService {
  const CustomerDocumentService({
    this.repository = const CustomerRepository(),
  });

  final CustomerRepository repository;

  Future<CustomerDocument?> pickAndAttach(int customerId) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'pdf',
        'jpg',
        'jpeg',
        'png',
        'bmp',
        'tif',
        'tiff',
      ],
      allowMultiple: false,
      dialogTitle: '顧客の宿帳・チェックインカードを選択',
    );
    if (result == null || result.files.isEmpty) {
      return null;
    }
    final selected = result.files.single;
    final sourcePath = selected.path;
    if (sourcePath == null || sourcePath.trim().isEmpty) {
      throw const CustomerDocumentException('選択したファイルの場所を取得できませんでした。');
    }

    final source = File(sourcePath);
    if (!await source.exists()) {
      throw CustomerDocumentException('選択したファイルが見つかりません。\n$sourcePath');
    }
    final supportDirectory = await getApplicationSupportDirectory();
    final destinationDirectory = Directory(
      p.join(
        supportDirectory.path,
        'JamooManager',
        'customer_documents',
        customerId.toString(),
      ),
    );
    await destinationDirectory.create(recursive: true);
    final safeName = _safeFileName(selected.name);
    final storedName = '${DateTime.now().microsecondsSinceEpoch}_$safeName';
    final destination = File(p.join(destinationDirectory.path, storedName));
    await source.copy(destination.path);

    try {
      return await repository.addCustomerDocument(
        customerId: customerId,
        originalFileName: selected.name,
        storedFilePath: destination.path,
        mimeType: _mimeTypeFor(selected.extension ?? p.extension(selected.name)),
      );
    } catch (_) {
      if (await destination.exists()) {
        await destination.delete();
      }
      rethrow;
    }
  }

  Future<CustomerOcrResult> runOcr(
    CustomerDocument document, {
    bool useCloud = false,
  }) async {
    await repository.updateDocumentOcr(
      documentId: document.id,
      status: 'processing',
    );
    try {
      final script = await _prepareOcrScript();
      final process = await _runPython(
        script,
        document.storedFilePath,
        useCloud: useCloud,
      );
      final output = process.stdout.toString().trim();
      Map<String, dynamic>? decoded;
      if (output.isNotEmpty) {
        final value = jsonDecode(output);
        if (value is Map<String, dynamic>) {
          decoded = value;
        }
      }
      if (process.exitCode != 0 || decoded == null || decoded['ok'] != true) {
        final errorMessage = decoded?['error']?.toString().trim();
        final stderr = process.stderr.toString().trim();
        throw CustomerDocumentException(
          errorMessage?.isNotEmpty == true
              ? errorMessage!
              : stderr.isNotEmpty
              ? stderr
              : 'OCRを実行できませんでした。',
        );
      }
      final result = CustomerOcrResult.fromJson(decoded);
      await repository.updateDocumentOcr(
        documentId: document.id,
        status: 'completed',
        ocrText: result.rawText,
      );
      return result;
    } catch (error) {
      await repository.updateDocumentOcr(
        documentId: document.id,
        status: 'failed',
      );
      if (error is CustomerDocumentException) {
        rethrow;
      }
      throw CustomerDocumentException(error.toString());
    }
  }

  Future<void> openDocument(CustomerDocument document) async {
    final file = File(document.storedFilePath);
    if (!await file.exists()) {
      throw const CustomerDocumentException('保存した添付ファイルが見つかりません。');
    }
    await Process.start('explorer.exe', [document.storedFilePath]);
  }

  Future<void> deleteDocument(CustomerDocument document) async {
    final storedPath = await repository.deleteCustomerDocument(document.id);
    if (storedPath == null) {
      return;
    }
    final file = File(storedPath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<bool> hasCloudOcrApiKey() async {
    final file = await _cloudOcrApiKeyFile();
    if (!await file.exists()) {
      return false;
    }
    return (await file.readAsString()).trim().isNotEmpty;
  }

  Future<void> saveCloudOcrApiKey(String value) async {
    final apiKey = value.trim();
    if (apiKey.length < 20) {
      throw const CustomerDocumentException('Google Cloud Vision APIキーが短すぎます。');
    }
    final file = await _cloudOcrApiKeyFile();
    await file.writeAsString(apiKey, flush: true);
  }

  Future<File> _prepareOcrScript() async {
    final directory = await _ocrDirectory();
    final script = File(p.join(directory.path, 'customer_ocr.py'));
    final bundled = await rootBundle.loadString('assets/ocr/customer_ocr.py');
    if (!await script.exists() || await script.readAsString() != bundled) {
      await script.writeAsString(bundled, flush: true);
    }
    return script;
  }

  Future<File> _cloudOcrApiKeyFile() async {
    final directory = await _ocrDirectory();
    return File(p.join(directory.path, 'vision_api_key.txt'));
  }

  Future<Directory> _ocrDirectory() async {
    final supportDirectory = await getApplicationSupportDirectory();
    final directory = Directory(
      p.join(supportDirectory.path, 'JamooManager', 'ocr'),
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<ProcessResult> _runPython(
    File script,
    String inputPath, {
    required bool useCloud,
  }) async {
    final arguments = [
      script.path,
      '--input',
      inputPath,
      '--engine',
      useCloud ? 'cloud' : 'local',
    ];
    try {
      return await Process.run(
        'py',
        arguments,
        environment: const {'PYTHONUTF8': '1'},
        runInShell: true,
      );
    } on ProcessException {
      try {
        return await Process.run(
          'python',
          arguments,
          environment: const {'PYTHONUTF8': '1'},
          runInShell: true,
        );
      } on ProcessException {
        throw const CustomerDocumentException(
          'Pythonを起動できませんでした。OCRセットアップを確認してください。',
        );
      }
    }
  }

  static String _safeFileName(String value) {
    final cleaned = value.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
    return cleaned.isEmpty ? 'document' : cleaned;
  }

  static String _mimeTypeFor(String extension) {
    switch (extension.toLowerCase().replaceFirst('.', '')) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'bmp':
        return 'image/bmp';
      case 'tif':
      case 'tiff':
        return 'image/tiff';
      default:
        return 'image/jpeg';
    }
  }
}

class CustomerDocumentException implements Exception {
  const CustomerDocumentException(this.message);

  final String message;

  @override
  String toString() => message;
}
