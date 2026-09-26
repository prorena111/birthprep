// 행정안전부 「대한민국 공공서비스(혜택) 정보」 오픈API(정부24가 보여 주는
// 서비스 글과 같은 것). data.go.kr/data/15113968 — 이용허락 제한 없음, 하루 1만 번.
//
// 키는 **환경변수 DATA_GO_KR_KEY**로만 받는다. 명령줄 인자는 작업 관리자와
// 셸 기록에 남는다. 오류 글에 키가 섞여 나오지 않게 [Gov24Client.hide]로
// 가린다. Claude는 키를 다루지 않는다(CLAUDE.md).
//
// dart:io만 쓴다 — 공개 저장소의 tool/에 그대로 복사해 GitHub Actions에서 돈다.

import 'dart:convert';
import 'dart:io';

/// 키가 거절됐다(401·403).
class Gov24KeyRejected implements Exception {
  Gov24KeyRejected(this.status, this.body);

  final int status;
  final String body;

  @override
  String toString() => 'Gov24KeyRejected($status)';
}

class Gov24Client {
  Gov24Client(this._key, {HttpClient? client, void Function(String)? log})
    : _client =
          client ??
          (HttpClient()
            ..connectionTimeout = const Duration(seconds: 20)
            ..userAgent = 'birthprep-gov24'),
      _log = log ?? print;

  static const base = 'https://api.odcloud.kr/api/gov24/v3';
  static const _perPage = 1000;

  final String _key;
  final HttpClient _client;
  final void Function(String) _log;

  /// 키를 주소에 싣는지. 처음에는 머리글로 보내고, 머리글이 거절되면 한 번만
  /// 주소(serviceKey)로 바꿔 본다 — 오픈API는 둘 다 받는다고 적혀 있다.
  var _keyInQuery = false;

  /// 오류 글에서 키를 가린다(주소에 실릴 때를 대비).
  String hide(Object e) => e
      .toString()
      .replaceAll(_key, '***')
      .replaceAll(Uri.encodeQueryComponent(_key), '***');

  /// 한 오퍼레이션(`serviceList` 등)의 모든 쪽을 받는다.
  Future<List<Map<String, Object?>>> all(String op) async {
    final out = <Map<String, Object?>>[];
    for (var page = 1; page <= 100; page++) {
      final uri = Uri.parse('$base/$op').replace(
        queryParameters: {
          'page': '$page',
          'perPage': '$_perPage',
          'returnType': 'JSON',
        },
      );
      final root = jsonDecode(await _get(uri));
      if (root is! Map) throw const FormatException('답이 JSON 객체가 아닙니다');
      final data = root['data'];
      final rows = data is List ? data : const [];
      for (final r in rows) {
        if (r is Map) out.add(r.cast<String, Object?>());
      }
      final total = root['totalCount'] is int ? root['totalCount'] as int : 0;
      _log('  $op $page쪽 — ${out.length}/$total');
      if (rows.isEmpty || out.length >= total) break;
    }
    return out;
  }

  /// 받기. 키는 **머리글**로 먼저 보낸다 — 주소에 실으면 오류 글에 찍힐 수
  /// 있다(찍혀도 [hide]가 가린다). 잠깐의 실패는 세 번까지 다시 한다.
  Future<String> _get(Uri uri) async {
    for (var attempt = 1; ; attempt++) {
      try {
        final target = _keyInQuery
            ? uri.replace(
                queryParameters: {...uri.queryParameters, 'serviceKey': _key},
              )
            : uri;
        final req = await _client.getUrl(target);
        if (!_keyInQuery) {
          req.headers.set(HttpHeaders.authorizationHeader, 'Infuser $_key');
        }
        req.headers.set(HttpHeaders.acceptHeader, 'application/json');
        final res = await req.close().timeout(const Duration(seconds: 90));
        final body = await res.transform(utf8.decoder).join();
        if (res.statusCode == 401 || res.statusCode == 403) {
          if (!_keyInQuery) {
            _keyInQuery = true;
            attempt--;
            continue;
          }
          throw Gov24KeyRejected(res.statusCode, body);
        }
        if (res.statusCode != 200) {
          throw HttpException('HTTP ${res.statusCode}: ${clip(body)}');
        }
        return body;
      } on Gov24KeyRejected {
        rethrow;
      } catch (e) {
        if (attempt >= 3) rethrow;
        _log('  다시 시도합니다($attempt/3): ${hide(e)}');
        await Future<void>.delayed(Duration(seconds: 3 * attempt));
      }
    }
  }

  void close() => _client.close(force: true);
}

/// 긴 글은 앞부분만.
String clip(String s) => s.length > 300 ? '${s.substring(0, 300)}…' : s;
