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

/// 목록을 다 받지 못했다 — 받은 수가 정부24가 말한 전체 수보다 적다.
class Gov24Incomplete implements Exception {
  Gov24Incomplete(this.op, this.got, this.total);

  final String op;
  final int got;
  final int total;

  @override
  String toString() => '정부24 $op을 다 받지 못했습니다($got/$total)';
}

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

  /// 한 오퍼레이션(`serviceList` 등)의 모든 쪽을 받는다. 다 받지 못하면
  /// [Gov24Incomplete]를 던진다 — 반쯤 빈 목록을 올리지 않게.
  Future<List<Map<String, Object?>>> all(String op) {
    return collectPages(op, (page) async {
      final uri = Uri.parse('$base/$op').replace(
        queryParameters: {
          'page': '$page',
          'perPage': '$_perPage',
          'returnType': 'JSON',
        },
      );
      return jsonDecode(await _get(uri));
    }, log: _log);
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
        final body = await res
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 90));
        if (res.statusCode == 401 || res.statusCode == 403) {
          if (!_keyInQuery) {
            _keyInQuery = true;
            attempt--;
            continue;
          }
          throw Gov24KeyRejected(res.statusCode, body);
        }
        // 응답 본문은 싣지 않는다 — 알림과 status.json은 공개다.
        if (res.statusCode != 200) {
          throw HttpException('정부24 HTTP ${res.statusCode}');
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

/// 쪽마다 받아 모은다. 전체 수(`totalCount`)를 처음 쪽에서 읽고, 빈 쪽이 오면
/// 한 번 다시 받는다. 끝에 받은 수가 전체 수보다 적으면 [Gov24Incomplete].
/// 검사에서 가짜 쪽을 넣으려고 따로 뺐다.
Future<List<Map<String, Object?>>> collectPages(
  String op,
  Future<Object?> Function(int page) fetch, {
  void Function(String)? log,
  int maxPages = 100,
}) async {
  final out = <Map<String, Object?>>[];
  int? total;
  for (var page = 1; page <= maxPages; page++) {
    var rows = const <Object?>[];
    for (var attempt = 1; attempt <= 2; attempt++) {
      final root = await fetch(page);
      if (root is! Map) throw const FormatException('답이 JSON 객체가 아닙니다');
      if (total == null && root['totalCount'] is int) {
        total = root['totalCount'] as int;
      }
      final data = root['data'];
      rows = data is List ? data : const [];
      if (rows.isNotEmpty || total == null || out.length >= total) break;
    }
    for (final r in rows) {
      if (r is Map) out.add(r.cast<String, Object?>());
    }
    log?.call('  $op $page쪽 — ${out.length}/${total ?? '?'}');
    if (total == null) throw Gov24Incomplete(op, out.length, -1);
    if (out.length >= total) return out;
    if (rows.isEmpty) break;
  }
  throw Gov24Incomplete(op, out.length, total ?? -1);
}

/// 긴 글은 앞부분만.
String clip(String s) => s.length > 300 ? '${s.substring(0, 300)}…' : s;
