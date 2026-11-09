// 제품안전정보센터(국가기술표준원 SafetyKorea) Open API — 국내리콜정보 조회.
// 공공데이터포털 15116894(「제품 안전인증 및 리콜 정보」)는 제공형태가 LINK라
// 실제 호출은 제품안전정보센터로 간다. 「Open API 인터페이스 설계서」 v2.1
// (2026-10-16, www.safetykorea.kr/release/openapi에서 받음):
//
//   GET https://www.safetykorea.kr/openapi/api/recall/recallList.json
//       ?conditionKey=recallProductName&conditionValue=<제품명>
//   머리(Header) `AuthKey: <서비스 ID>` — 공공데이터포털 키가 아니다. 신청서를
//   safetykorea@korea.kr로 보내 승인되면 메일로 온다(사장님 몫).
//   설계서는 조회 목록 최대 1,000줄. 결과코드 2000 성공 · 2004 자료 없음 · 4000 키
//   틀림 · 4001 IP 틀림 · 4005 인자 틀림 · 5000 서버 오류. 키 없이 부르면
//   `…/openapi/api/error/accessDeniedByKey.json`으로 넘긴다(2026-11-08 확인).
//
//   실제 키로 본 것(2026-11-09): `conditionKey=all`은 값이 「all」이어야 전체가
//   온다(4,299건·5.7MB, 1,000줄 제한 없음). 「전체」는 그 말을 찾아 0줄, 빈 값은
//   4005. 제품명 검색은 부분 일치(「유모차」 29건). 자료가 없으면 2004가 아니라
//   2000에 빈 목록.
//
// 키는 환경변수 SAFETYKOREA_KEY로만. 오류 글에서 키를 가린다. Claude는 키를
// 다루지 않는다(CLAUDE.md).

import 'dart:convert';
import 'dart:io';

/// 키가 거절됐다(결과코드 4000·4001, 또는 키 없음 쪽으로 넘김).
class RecallKeyRejected implements Exception {
  RecallKeyRejected(this.code);

  final String code;

  @override
  String toString() => 'RecallKeyRejected($code)';
}

/// 국내리콜 조회 답(`recallList.json`)을 읽는다. 자료 없음(2004)은 빈 목록.
List<Map<String, Object?>> parseRecallList(String body) {
  final root = jsonDecode(body);
  if (root is! Map) throw const FormatException('리콜 답 모양');
  final code = '${root['resultCode'] ?? ''}';
  if (code == '4000' || code == '4001') throw RecallKeyRejected(code);
  if (code == '2004') return const [];
  if (code != '2000') {
    throw HttpException('리콜 결과코드 $code ${root['resultMsg'] ?? ''}');
  }
  final data = root['resultData'];
  if (data == null) return const [];
  if (data is! List) throw const FormatException('리콜 resultData 모양');
  return [
    for (final row in data)
      if (row is Map) row.cast<String, Object?>(),
  ];
}

class SafetyKoreaClient {
  SafetyKoreaClient(this._key, {HttpClient? client, void Function(String)? log})
    : _client =
          client ??
          (HttpClient()
            ..connectionTimeout = const Duration(seconds: 20)
            ..userAgent = 'birthprep-recall'),
      _log = log ?? print;

  static const base = 'https://www.safetykorea.kr/openapi/api/recall';

  final String _key;
  final HttpClient _client;
  final void Function(String) _log;

  /// 오류 글에서 키를 가린다.
  String hide(Object e) => e.toString().replaceAll(_key, '***');

  /// 전체조회에 검색어마다 제품명으로 찾은 것을 더해 겹침 없이.
  ///
  /// 전체조회만으로 다 오지만, 1,000줄 제한이 설계서에 있어 언제 잘릴지 모른다 —
  /// 검색어 것을 같이 받아 둘 중 하나만 맞아도 빠지지 않게 했다. 전체조회가 인자
  /// 오류(4005)면 검색어 것만 쓴다. 검색어 하나라도 끝내 못 받으면 던진다(반쯤 받은
  /// 목록으로 지난 값을 덮지 않게).
  Future<List<Map<String, Object?>>> fetch(List<String> terms) async {
    final byId = <String, Map<String, Object?>>{};
    void add(List<Map<String, Object?>> rows) {
      for (final r in rows) {
        byId.putIfAbsent('${r['recallUid']}', () => r);
      }
    }

    try {
      // 값이 「all」이어야 전체가 온다 — 「전체」는 0줄(2026-11-09, 맨 위 주석).
      final recent = await _list('all', 'all');
      _log('  리콜 전체조회 ${recent.length}줄');
      add(recent);
    } on RecallKeyRejected {
      rethrow;
    } on HttpException catch (e) {
      _log('  리콜 전체조회는 건너뜁니다: ${hide(e)}');
    }
    for (final term in terms) {
      final rows = await _list('recallProductName', term);
      _log('  리콜 「$term」 ${rows.length}줄');
      add(rows);
      // 설계서: 서비스 운영에 지장을 주는 방식이면 이용이 제한될 수 있다.
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    return byId.values.toList();
  }

  Future<List<Map<String, Object?>>> _list(String key, String value) async {
    final uri = Uri.parse(
      '$base/recallList.json',
    ).replace(queryParameters: {'conditionKey': key, 'conditionValue': value});
    for (var attempt = 1; ; attempt++) {
      try {
        final req = await _client.getUrl(uri);
        req.followRedirects = false;
        req.headers.set('AuthKey', _key);
        final res = await req.close().timeout(const Duration(seconds: 90));
        final body = await res
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 90));
        // 키가 없거나 틀리면 오류 쪽으로 넘긴다(302).
        final location = res.headers.value(HttpHeaders.locationHeader) ?? '';
        if (res.isRedirect || location.contains('accessDenied')) {
          throw RecallKeyRejected(
            location.contains('accessDenied') ? '4000' : '${res.statusCode}',
          );
        }
        if (res.statusCode != 200) {
          throw HttpException('리콜 HTTP ${res.statusCode}');
        }
        return parseRecallList(body);
      } on RecallKeyRejected {
        rethrow;
      } on HttpException catch (e) {
        // 인자 오류는 다시 해도 같다.
        if (e.message.contains('4005') || attempt >= 4) rethrow;
        _log('  다시 시도합니다($attempt/4): ${hide(e)}');
        await Future<void>.delayed(Duration(seconds: 5 * attempt));
      } catch (e) {
        if (attempt >= 4) throw HttpException('리콜 받기 실패: ${hide(e)}');
        _log('  다시 시도합니다($attempt/4): ${hide(e)}');
        await Future<void>.delayed(Duration(seconds: 5 * attempt));
      }
    }
  }

  void close() => _client.close(force: true);
}
