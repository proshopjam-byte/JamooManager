import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class WindowsPdfFonts {
  const WindowsPdfFonts({
    required this.regular,
    required this.bold,
    required this.fallback,
  });

  final pw.Font regular;
  final pw.Font bold;
  final List<pw.Font> fallback;

  pw.Font get korean => fallback.first;

  pw.Font? fontFor(String value) {
    return containsHangul([value]) ? korean : null;
  }

  bool containsHangul(Iterable<String> values) {
    return _hangulPattern.hasMatch(values.join('\n'));
  }

  static final RegExp _hangulPattern = RegExp(
    r'[\u1100-\u11ff\u3130-\u318f\uac00-\ud7af]',
  );
}

class WindowsPdfFontService {
  const WindowsPdfFontService._();

  static Future<WindowsPdfFonts>? _cached;

  static Future<WindowsPdfFonts> load() => _cached ??= _load();

  static Future<WindowsPdfFonts> _load() async {
    final koreanFallback = await _loadKoreanFallback();

    // Bundle the print fonts so Japanese printing also works offline.
    try {
      final regular = await rootBundle.load(
        'assets/fonts/ZenMaruGothic-Regular.ttf',
      );
      final medium = await rootBundle.load(
        'assets/fonts/ZenMaruGothic-Medium.ttf',
      );
      return WindowsPdfFonts(
        regular: pw.Font.ttf(regular),
        bold: pw.Font.ttf(medium),
        fallback: koreanFallback,
      );
    } catch (_) {
      // Retain the existing fallback for older bundles and non-asset tests.
    }

    if (Platform.isWindows) {
      final regular = await _loadFirst(const [
        r'C:\Windows\Fonts\YuGothM.ttc',
        r'C:\Windows\Fonts\YuGothR.ttc',
        r'C:\Windows\Fonts\meiryo.ttc',
        r'C:\Windows\Fonts\msgothic.ttc',
      ]);
      final bold = await _loadFirst(const [
        r'C:\Windows\Fonts\YuGothB.ttc',
        r'C:\Windows\Fonts\meiryob.ttc',
        r'C:\Windows\Fonts\YuGothM.ttc',
        r'C:\Windows\Fonts\msgothic.ttc',
      ]);
      if (regular != null) {
        return WindowsPdfFonts(
          regular: regular,
          bold: bold ?? regular,
          fallback: koreanFallback,
        );
      }
    }

    return WindowsPdfFonts(
      regular: await PdfGoogleFonts.notoSansJPRegular(),
      bold: await PdfGoogleFonts.notoSansJPBold(),
      fallback: koreanFallback,
    );
  }

  static Future<List<pw.Font>> _loadKoreanFallback() async {
    try {
      final korean = await rootBundle.load(
        'assets/fonts/NanumGothic-Regular.ttf',
      );
      return [pw.Font.ttf(korean)];
    } catch (_) {
      // Retain the installed-font fallback for older application bundles.
    }

    if (Platform.isWindows) {
      final korean = await _loadFirst(const [
        r'C:\Windows\Fonts\malgun.ttf',
        r'C:\Windows\Fonts\malgunsl.ttf',
        r'C:\Windows\Fonts\batang.ttc',
        r'C:\Windows\Fonts\gulim.ttc',
      ]);
      if (korean != null) return [korean];
    }

    return [await PdfGoogleFonts.notoSansKRRegular()];
  }

  static Future<pw.Font?> _loadFirst(List<String> paths) async {
    for (final path in paths) {
      final file = File(path);
      if (!await file.exists()) continue;
      try {
        final source = await file.readAsBytes();
        final fontBytes = extractFirstFont(source);
        return pw.Font.ttf(ByteData.sublistView(fontBytes));
      } catch (_) {
        // Try the next installed Japanese font.
      }
    }
    return null;
  }

  /// Converts the first font in a TrueType Collection into a standalone sfnt.
  /// The pdf package accepts TTF/OTF data but not the Windows TTC container.
  static Uint8List extractFirstFont(Uint8List source) {
    if (source.length < 12) {
      throw const FormatException('フォントファイルが短すぎます。');
    }
    final data = ByteData.sublistView(source);
    const ttcTag = 0x74746366; // ttcf
    if (data.getUint32(0) != ttcTag) return source;

    final fontCount = data.getUint32(8);
    if (fontCount == 0 || source.length < 16) {
      throw const FormatException('TTCにフォントが含まれていません。');
    }
    final fontOffset = data.getUint32(12);
    if (fontOffset + 12 > source.length) {
      throw const FormatException('TTCのフォント位置が正しくありません。');
    }
    final tableCount = data.getUint16(fontOffset + 4);
    final directoryEnd = fontOffset + 12 + tableCount * 16;
    if (directoryEnd > source.length) {
      throw const FormatException('TTCのテーブル一覧が正しくありません。');
    }

    final tables = <_TtcTable>[];
    var targetOffset = 12 + tableCount * 16;
    for (var index = 0; index < tableCount; index++) {
      final record = fontOffset + 12 + index * 16;
      final sourceOffset = data.getUint32(record + 8);
      final length = data.getUint32(record + 12);
      if (sourceOffset + length > source.length) {
        throw const FormatException('TTCのテーブル位置が正しくありません。');
      }
      targetOffset = _align4(targetOffset);
      tables.add(
        _TtcTable(
          tag: data.getUint32(record),
          checksum: data.getUint32(record + 4),
          sourceOffset: sourceOffset,
          length: length,
          targetOffset: targetOffset,
        ),
      );
      targetOffset += length;
    }

    final output = Uint8List(_align4(targetOffset));
    final outputData = ByteData.sublistView(output);
    for (var offset = 0; offset < 12; offset++) {
      output[offset] = source[fontOffset + offset];
    }
    for (var index = 0; index < tables.length; index++) {
      final table = tables[index];
      final record = 12 + index * 16;
      outputData.setUint32(record, table.tag);
      outputData.setUint32(record + 4, table.checksum);
      outputData.setUint32(record + 8, table.targetOffset);
      outputData.setUint32(record + 12, table.length);
      output.setRange(
        table.targetOffset,
        table.targetOffset + table.length,
        source,
        table.sourceOffset,
      );
    }
    return output;
  }

  static int _align4(int value) => (value + 3) & ~3;
}

class _TtcTable {
  const _TtcTable({
    required this.tag,
    required this.checksum,
    required this.sourceOffset,
    required this.length,
    required this.targetOffset,
  });

  final int tag;
  final int checksum;
  final int sourceOffset;
  final int length;
  final int targetOffset;
}
