import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/reservation.dart';

class CheckinCardPrintService {
  const CheckinCardPrintService();

  Future<void> previewCard(
    BuildContext context,
    Reservation reservation,
  ) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text('チェックインカード - ${reservation.displayGuestName}'),
          ),
          body: PdfPreview(
            initialPageFormat: PdfPageFormat.a5.landscape,
            build: (_) => _buildPdf(reservation),
            allowPrinting: false,
            allowSharing: false,
            canChangePageFormat: false,
            canChangeOrientation: false,
            actions: [
              IconButton(
                tooltip: 'A5で印刷',
                onPressed: () => _printCard(reservation),
                icon: const Icon(Icons.print_outlined),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _printCard(Reservation reservation) async {
    await Printing.layoutPdf(
      name: 'checkin_card_${reservation.displayGuestName}.pdf',
      format: PdfPageFormat.a5.landscape,
      dynamicLayout: false,
      usePrinterSettings: false,
      forceCustomPrintPaper: true,
      windowsModernDialog: false,
      onLayout: (_) => _buildPdf(reservation),
    );
  }

  Future<Uint8List> _buildPdf(Reservation reservation) async {
    final document = pw.Document();
    final regular = await PdfGoogleFonts.notoSansJPRegular();
    final bold = await PdfGoogleFonts.notoSansJPBold();

    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5.landscape,
        margin: const pw.EdgeInsets.all(14),
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              '宿泊者名簿　Guest Registration Card',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.Container(
              decoration: pw.BoxDecoration(border: pw.Border.all(width: 1.2)),
              child: pw.Column(
                children: [
                  _standardRow(
                    leftJapanese: '氏名',
                    leftEnglish: 'Name',
                    leftValue: reservation.displayGuestName,
                    rightJapanese: '性別',
                    rightEnglish: 'Gender',
                    rightValue: '□ 男 Male　　□ 女 Female',
                  ),
                  _standardRow(
                    leftJapanese: '住所',
                    leftEnglish: 'Address',
                    leftValue: _displayAddress(reservation),
                    leftValueFontSize: _addressFontSize(reservation),
                    leftValueMaxLines: 2,
                    rightJapanese: '電話番号',
                    rightEnglish: 'Telephone',
                    rightValue: reservation.phone ?? '',
                  ),
                  _standardRow(
                    leftJapanese: '職業',
                    leftEnglish: 'Occupation',
                    leftValue: '',
                    rightJapanese: '年齢',
                    rightEnglish: 'Age',
                    rightValue: '',
                  ),
                  _standardRow(
                    leftJapanese: '到着日',
                    leftEnglish: 'Check-in',
                    leftValue: _formatDate(reservation.checkIn),
                    rightJapanese: '出発日',
                    rightEnglish: 'Check-out',
                    rightValue: _formatDate(reservation.checkOut),
                  ),
                  _standardRow(
                    leftJapanese: '国籍（外国の方）',
                    leftEnglish: 'Nationality',
                    leftValue: '',
                    rightJapanese: '旅券番号',
                    rightEnglish: 'Passport No.',
                    rightValue: '',
                  ),
                  _standardRow(
                    leftJapanese: 'メール',
                    leftEnglish: 'Email address',
                    leftValue: reservation.email ?? '',
                    rightJapanese: '人数',
                    rightEnglish: 'Guests',
                    rightValue: _guestCount(reservation),
                  ),
                  _wideRow(
                    japanese: 'ジャムーを何で\n知りましたか',
                    english: 'How did you find Jamoo?',
                    value: _discoverySource(reservation),
                    height: 58,
                    valueFontSize: 8.5,
                  ),
                  _standardRow(
                    leftJapanese: '同行者氏名',
                    leftEnglish: 'Family names',
                    leftValue: '',
                    rightJapanese: '代表者署名',
                    rightEnglish: 'Signature',
                    rightValue: '',
                  ),
                  _wideRow(
                    japanese: '施設利用欄',
                    english: 'Facility Use',
                    value: _facilityUse(reservation),
                    height: 40,
                    isLast: true,
                    valueFontSize: 8.5,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return document.save();
  }

  static pw.Widget _standardRow({
    required String leftJapanese,
    required String leftEnglish,
    required String leftValue,
    required String rightJapanese,
    required String rightEnglish,
    required String rightValue,
    double leftValueFontSize = 9,
    int? leftValueMaxLines,
  }) {
    return pw.Container(
      height: 38,
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(width: 0.7)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _labelCell(leftJapanese, leftEnglish),
          pw.Expanded(
            child: _valueCell(
              leftValue,
              showRightBorder: true,
              fontSize: leftValueFontSize,
              maxLines: leftValueMaxLines,
            ),
          ),
          _labelCell(rightJapanese, rightEnglish),
          pw.Expanded(child: _valueCell(rightValue)),
        ],
      ),
    );
  }

  static pw.Widget _wideRow({
    required String japanese,
    required String english,
    required String value,
    required double height,
    bool isLast = false,
    double valueFontSize = 9,
  }) {
    return pw.Container(
      height: height,
      decoration: pw.BoxDecoration(
        border: isLast
            ? null
            : const pw.Border(bottom: pw.BorderSide(width: 0.7)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _labelCell(japanese, english),
          pw.Expanded(child: _valueCell(value, fontSize: valueFontSize)),
        ],
      ),
    );
  }

  static pw.Widget _labelCell(String japanese, String english) {
    return pw.Container(
      width: 86,
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: const pw.BoxDecoration(
        color: PdfColors.grey200,
        border: pw.Border(right: pw.BorderSide(width: 0.7)),
      ),
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            japanese,
            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 1),
          pw.Text(english, style: const pw.TextStyle(fontSize: 7.2)),
        ],
      ),
    );
  }

  static pw.Widget _valueCell(
    String value, {
    bool showRightBorder = false,
    double fontSize = 9,
    int? maxLines,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      alignment: pw.Alignment.centerLeft,
      decoration: pw.BoxDecoration(
        border: showRightBorder
            ? const pw.Border(right: pw.BorderSide(width: 0.7))
            : null,
      ),
      child: pw.Text(
        value,
        maxLines: maxLines,
        style: pw.TextStyle(fontSize: fontSize),
      ),
    );
  }

  static double _addressFontSize(Reservation reservation) {
    final length = _displayAddress(reservation).runes.length;

    if (length <= 24) {
      return 9;
    }
    if (length <= 40) {
      return 8;
    }
    if (length <= 56) {
      return 7;
    }

    return 6;
  }

  static String _displayAddress(Reservation reservation) {
    final address = reservation.address?.trim() ?? '';
    var postalCode = reservation.postalCode?.trim() ?? '';

    postalCode = postalCode.replaceFirst(RegExp(r'^〒\s*'), '');
    final digits = postalCode.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.length == 7) {
      postalCode = '${digits.substring(0, 3)}-${digits.substring(3)}';
    }

    if (postalCode.isEmpty) {
      return address;
    }
    if (address.isEmpty) {
      return '〒$postalCode';
    }

    return '〒$postalCode　$address';
  }

  static String _discoverySource(Reservation reservation) {
    final source = reservation.source.trim().toLowerCase();
    final isPortal =
        source.contains('booking') ||
        source.contains('rakuten') ||
        source.contains('jalan');
    final isOfficialWebsite = source.contains('chillnn');

    final portalBox = isPortal ? '■' : '□';
    final officialWebsiteBox = isOfficialWebsite ? '■' : '□';

    return '$portalBox Booking.comなどのポータルサイト　　'
        '$officialWebsiteBox Jamoo公式HP\n'
        '□ SNS（Instagram・Facebook）　　□ その他\n'
        '□ ご紹介　お名前：　　　　　　　　　　　　　　　　　　　　　　';
  }

  static String _facilityUse(Reservation reservation) {
    final configuredGuests = reservation.breakfastGuestCount;
    final totalGuests =
        reservation.totalGuests ??
        ((reservation.adults ?? 0) + reservation.children);
    final breakfastGuests = configuredGuests != null && configuredGuests > 0
        ? configuredGuests
        : totalGuests;

    final registeredNights = reservation.nights;
    final dateNights =
        reservation.checkIn != null && reservation.checkOut != null
        ? reservation.checkOut!.difference(reservation.checkIn!).inDays
        : 1;
    final nights = registeredNights != null && registeredNights > 0
        ? registeredNights
        : dateNights > 0
        ? dateNights
        : 1;

    final hasBreakfast = reservation.hasBreakfast == true;
    final breakfastPrice = hasBreakfast ? 2200 * breakfastGuests * nights : 0;

    final totalPrice = reservation.priceYen;
    final lodgingPrice = totalPrice == null
        ? null
        : totalPrice - breakfastPrice;

    final lodging = lodgingPrice == null
        ? '未設定'
        : _formatYen(lodgingPrice < 0 ? 0 : lodgingPrice);

    final breakfast = reservation.hasBreakfast == null
        ? '未設定'
        : hasBreakfast
        ? 'あり（$breakfastGuests名×$nights回・${_formatYen(breakfastPrice)}）'
        : 'なし';

    final dinner = reservation.hasDinner == null
        ? '未設定'
        : reservation.hasDinner == true
        ? 'あり'
        : 'なし';

    final room = reservation.roomName?.trim() ?? '';
    final roomLine = room.isEmpty ? '' : '部屋：$room\n';

    return '$roomLine宿泊料金：$lodging　朝食：$breakfast　夕食：$dinner　その他：';
  }

  static String _formatYen(int value) {
    final digits = value.toString();
    final parts = <String>[];

    for (var end = digits.length; end > 0; end -= 3) {
      final start = end - 3 < 0 ? 0 : end - 3;
      parts.insert(0, digits.substring(start, end));
    }

    return '${parts.join(',')}円';
  }

  static String _guestCount(Reservation reservation) {
    final count =
        reservation.totalGuests ??
        ((reservation.adults ?? 0) + reservation.children);
    return count > 0 ? '$count名' : '';
  }

  static String _formatDate(DateTime? value) {
    if (value == null) {
      return '';
    }

    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year / $month / $day';
  }
}
