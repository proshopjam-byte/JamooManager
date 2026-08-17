import 'dart:async';
import 'dart:convert';
import 'dart:io';

class PostalCodeLookupCandidate {
  const PostalCodeLookupCandidate({
    required this.postalCode,
    required this.prefecture,
    required this.city,
    required this.town,
  });

  final String postalCode;
  final String prefecture;
  final String city;
  final String town;

  String get formattedPostalCode {
    final digits = postalCode.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length != 7) {
      return postalCode;
    }
    return '${digits.substring(0, 3)}-${digits.substring(3)}';
  }

  String get displayAddress => '$prefecture$city$town';
}

class PostalCodeLookupService {
  const PostalCodeLookupService();

  static const _host = 'geoapi.heartrails.com';
  static const _path = '/api/json';

  Future<List<PostalCodeLookupCandidate>> findByAddress(String address) async {
    final keyword = _lookupKeyword(address);
    if (keyword.isEmpty) {
      throw const PostalCodeLookupException('都道府県・市区町村・町名を含む日本の住所を入力してください。');
    }

    final uri = Uri.https(_host, _path, {
      'method': 'suggest',
      'matching': 'like',
      'keyword': keyword,
    });
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);

    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 12));
      request.headers.set(HttpHeaders.userAgentHeader, 'JamooManager/1.0');
      final response = await request.close().timeout(
        const Duration(seconds: 12),
      );
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != HttpStatus.ok) {
        throw PostalCodeLookupException(
          '郵便番号検索サービスからエラーが返されました（${response.statusCode}）。',
        );
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const PostalCodeLookupException('郵便番号検索の応答を読み取れませんでした。');
      }
      final responseData = decoded['response'];
      if (responseData is! Map<String, dynamic>) {
        return const <PostalCodeLookupCandidate>[];
      }
      final error = responseData['error']?.toString().trim();
      if (error != null && error.isNotEmpty) {
        return const <PostalCodeLookupCandidate>[];
      }

      final rawLocations = responseData['location'];
      final locations = rawLocations is List
          ? rawLocations
          : rawLocations is Map<String, dynamic>
          ? [rawLocations]
          : const <dynamic>[];
      final candidates = <PostalCodeLookupCandidate>[];
      final seen = <String>{};

      for (final rawLocation in locations) {
        if (rawLocation is! Map) {
          continue;
        }
        final postalCode = _text(rawLocation['postal']);
        if (postalCode == null) {
          continue;
        }
        final candidate = PostalCodeLookupCandidate(
          postalCode: postalCode,
          prefecture: _text(rawLocation['prefecture']) ?? '',
          city: _text(rawLocation['city']) ?? '',
          town: _text(rawLocation['town']) ?? '',
        );
        final key = '${candidate.postalCode}|${candidate.displayAddress}';
        if (seen.add(key)) {
          candidates.add(candidate);
        }
        if (candidates.length >= 20) {
          break;
        }
      }

      return candidates;
    } on PostalCodeLookupException {
      rethrow;
    } on TimeoutException {
      throw const PostalCodeLookupException('郵便番号検索がタイムアウトしました。通信状態を確認してください。');
    } on SocketException {
      throw const PostalCodeLookupException(
        '郵便番号検索へ接続できません。インターネット接続を確認してください。',
      );
    } on FormatException {
      throw const PostalCodeLookupException('郵便番号検索の応答を読み取れませんでした。');
    } finally {
      client.close(force: true);
    }
  }

  static String _lookupKeyword(String address) {
    var value = address.trim();
    value = value.replaceFirst(
      RegExp(r'^〒?\s*[0-9０-９]{3}[-ー−－]?\s*[0-9０-９]{4}\s*'),
      '',
    );
    value = value.replaceAll(RegExp(r'[\s　]+'), '');

    final buildingNumber = value.indexOf(RegExp(r'[0-9０-９]'));
    if (buildingNumber > 0) {
      value = value.substring(0, buildingNumber);
    }

    return value.replaceAll(RegExp(r'[、,]+$'), '');
  }

  static String? _text(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}

class PostalCodeLookupException implements Exception {
  const PostalCodeLookupException(this.message);

  final String message;

  @override
  String toString() => message;
}
