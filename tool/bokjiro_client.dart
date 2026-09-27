// 한국사회보장정보원 「지자체복지서비스」 오픈API — 대국민 복지포털 복지로가
// 보여 주는 지자체(시·도, 시·군·구) 복지사업. data.go.kr/data/15108347,
// 이용허락 제한 없음, 개발계정 하루 1,000번.
//
// **정부24 공공서비스 목록에 없는 지자체 사업이 여기 있다** — 2026-09-27
// 창원시 「임산부 진료비 플러스 사업」은 정부24에 없고 복지로에만 있었다.
// 사장님 같은 날 「api로 내용을 받고 있었는데 그것만으로는 시군구 단위는 못
// 보는 것 같아」.
//
// 키는 정부24와 같은 공공데이터포털 인증키(환경변수 DATA_GO_KR_KEY)다 —
// 포털에서 이 API도 「활용신청」해 두어야 받힌다. 답은 XML뿐이라 dart 기본
// 라이브러리만으로 칸을 뽑는다(공개 저장소 tool/에 그대로 복사해 돈다).
// Claude는 키를 다루지 않는다(CLAUDE.md).

import 'dart:convert';
import 'dart:io';

import 'gov24_client.dart' show Gov24Incomplete, Gov24KeyRejected;

class BokjiroClient {
  BokjiroClient(this._key, {HttpClient? client, void Function(String)? log})
    : _client =
          client ??
          (HttpClient()
            ..connectionTimeout = const Duration(seconds: 20)
            ..userAgent = 'birthprep-bokjiro'),
      _log = log ?? print;

  static const base =
      'https://apis.data.go.kr/B554287/LocalGovernmentWelfareInformations';
  static const _perPage = 500;

  final String _key;
  final HttpClient _client;
  final void Function(String) _log;

  /// 오류 글에서 키를 가린다.
  String hide(Object e) => e
      .toString()
      .replaceAll(_key, '***')
      .replaceAll(Uri.encodeQueryComponent(_key), '***');

  /// 목록 전체(조건 없이). 다 받지 못하면 [Gov24Incomplete].
  Future<List<Map<String, String>>> list() async {
    final out = <Map<String, String>>[];
    int? total;
    for (var page = 1; page <= 100; page++) {
      final body = await _get('LcgvWelfarelist', {
        'pageNo': '$page',
        'numOfRows': '$_perPage',
      });
      total ??= int.tryParse(xmlText(body, 'totalCount') ?? '');
      final rows = xmlBlocks(body, 'servList');
      out.addAll(rows);
      _log('  복지로 목록 $page쪽 — ${out.length}/${total ?? '?'}');
      if (total == null) throw Gov24Incomplete('복지로 목록', out.length, -1);
      if (out.length >= total || rows.isEmpty) break;
    }
    if (total == null || out.length < total) {
      throw Gov24Incomplete('복지로 목록', out.length, total ?? -1);
    }
    return out;
  }

  /// 한 서비스의 상세 — 지원대상·선정기준·급여서비스·신청방법·문의처.
  Future<Map<String, Object?>> detail(String servId) async {
    final body = await _get('LcgvWelfaredetailed', {'servId': servId});
    return parseDetail(body);
  }

  Future<String> _get(String op, Map<String, String> params) async {
    final uri = Uri.parse(
      '$base/$op',
    ).replace(queryParameters: {'serviceKey': _key, ...params});
    for (var attempt = 1; ; attempt++) {
      try {
        final req = await _client.getUrl(uri);
        final res = await req.close().timeout(const Duration(seconds: 90));
        final body = await res
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 90));
        // 공공데이터포털은 등록 안 된 키에도 200과 XML 오류를 돌려준다.
        if (res.statusCode == 401 ||
            res.statusCode == 403 ||
            body.contains('SERVICE_KEY_IS_NOT_REGISTERED') ||
            body.contains('SERVICE ACCESS DENIED')) {
          throw Gov24KeyRejected(res.statusCode, _headerOf(body));
        }
        if (res.statusCode != 200) {
          throw HttpException('복지로 HTTP ${res.statusCode}');
        }
        final code = xmlText(body, 'resultCode');
        if (code != null && code != '0' && code != '00') {
          throw HttpException(
            '복지로 결과코드 $code ${xmlText(body, 'resultMessage') ?? ''}',
          );
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

/// 오류 XML에서 머리말만(키가 섞이지 않는 칸).
String _headerOf(String body) =>
    xmlText(body, 'returnAuthMsg') ??
    xmlText(body, 'errMsg') ??
    xmlText(body, 'resultMessage') ??
    '';

/// `<name>…</name>` 첫 글. 없으면 null.
String? xmlText(String xml, String name) {
  final m = RegExp('<$name>(.*?)</$name>', dotAll: true).firstMatch(xml);
  if (m == null) return null;
  final t = unescapeXml(m.group(1)!).trim();
  return t.isEmpty ? null : t;
}

/// `<name>` 덩어리마다 안의 칸들 — 덩어리 안은 한 겹짜리 칸만 있다고 본다.
List<Map<String, String>> xmlBlocks(String xml, String name) => [
  for (final m in RegExp('<$name>(.*?)</$name>', dotAll: true).allMatches(xml))
    xmlFields(m.group(1)!),
];

/// 한 겹짜리 칸들 `<a>x</a><b>y</b>` → {a: x, b: y}. 빈 칸은 뺀다.
Map<String, String> xmlFields(String inner) => {
  for (final m in RegExp(r'<([A-Za-z][\w]*)>([^<]*)</\1>').allMatches(inner))
    if (unescapeXml(m.group(2)!).trim() case final v when v.isNotEmpty)
      m.group(1)!: v,
};

/// XML 글자 되돌리기 — `&amp;`·`&lt;`·`&#10;` 들.
String unescapeXml(String s) {
  var t = s;
  final cdata = RegExp(r'^\s*<!\[CDATA\[(.*)\]\]>\s*$', dotAll: true);
  if (cdata.firstMatch(t) case final m?) return m.group(1)!;
  t = t.replaceAllMapped(
    RegExp(r'&#(x?)([0-9A-Fa-f]+);'),
    (m) =>
        String.fromCharCode(int.parse(m[2]!, radix: m[1]!.isEmpty ? 10 : 16)),
  );
  return t
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}

/// 상세 XML → 칸들. 문의처·관련 누리집은 목록으로.
Map<String, Object?> parseDetail(String xml) {
  final out = <String, Object?>{};
  for (final k in [
    'servId',
    'servNm',
    'enfcBgngYmd',
    'enfcEndYmd',
    'bizChrDeptNm',
    'ctpvNm',
    'sggNm',
    'servDgst',
    'lifeNmArray',
    'trgterIndvdlNmArray',
    'intrsThemaNmArray',
    'sprtCycNm',
    'srvPvsnNm',
    'aplyMtdNm',
    'sprtTrgtCn',
    'slctCritCn',
    'alwServCn',
    'aplyMtdCn',
    'lastModYmd',
  ]) {
    if (xmlText(xml, k) case final v?) out[k] = v;
  }
  out['inqpl'] = xmlBlocks(xml, 'inqplCtadrList');
  out['homepages'] = xmlBlocks(xml, 'inqplHmpgReldList');
  return out;
}
