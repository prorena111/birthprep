// 시·도가 따로 여는 데이터 — 정부24·복지로에 없는 시·도 사업을 더한다.
//
//   · 서울 「탄생육아 몽땅정보통 사업정보」(서울 열린데이터광장 OA-22188,
//     서비스 VwSmpBizInfo, 공공누리 1유형) — 서울시·중앙부처 사업 약 320개.
//     35세 이상 임산부 의료비·산후우울 정신건강 서비스처럼 정부24·복지로에 없는
//     서울시 사업이 여기에만 있다(2026-09-28 사장님 마포구 목록으로 대조).
//   · 경기 「시군별 출산장려 및 양육비 지원현황」(경기데이터드림,
//     BrthspprtMnychldprvtrtbz, 상업적 이용·변경 허용) — 31개 시군 출산지원금을
//     첫째~다섯째별 금액으로.
//
// 키는 환경변수 SEOUL_OPENAPI_KEY·GG_OPENAPI_KEY로만(GitHub 비밀값). Claude는
// 키를 다루지 않는다(CLAUDE.md).
//
// dart 기본 라이브러리만 쓴다(공개 저장소 tool/에 그대로 복사해 돈다).

import 'dart:convert';
import 'dart:io';

import 'bokjiro_pick.dart';
import 'gov24_pick.dart';

// ── 받기 ──────────────────────────────────────────────────────────────

/// 서울 열린데이터광장 — 주소에 키가 들어간다(서울 API 규칙). 오류 글에서 가린다.
Future<List<Map<String, String>>> fetchSeoul(
  String key, {
  void Function(String)? log,
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  String hide(Object e) => '$e'.replaceAll(key, '***');
  try {
    final out = <Map<String, String>>[];
    int? total;
    for (var start = 1; total == null || start <= total; start += 1000) {
      final body = await _getText(
        client,
        Uri.parse(
          'http://openapi.seoul.go.kr:8088/$key/json/VwSmpBizInfo/$start/${start + 999}/',
        ),
        hide,
        log,
      );
      final root = (jsonDecode(body) as Map)['VwSmpBizInfo'];
      if (root is! Map) {
        throw FormatException(
          '서울 답 모양이 다릅니다: ${hide(body.length > 200 ? body.substring(0, 200) : body)}',
        );
      }
      total = root['list_total_count'] as int;
      for (final r in root['row'] as List) {
        out.add({
          for (final e in (r as Map).entries)
            if (e.value != null) '${e.key}': '${e.value}',
        });
      }
    }
    return out;
  } finally {
    client.close(force: true);
  }
}

/// 경기데이터드림 — 키는 주소의 KEY.
Future<List<Map<String, String>>> fetchGyeonggi(
  String key, {
  void Function(String)? log,
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  String hide(Object e) => '$e'.replaceAll(key, '***');
  try {
    final out = <Map<String, String>>[];
    for (var page = 1; page <= 20; page++) {
      final body = await _getText(
        client,
        Uri.parse('https://openapi.gg.go.kr/BrthspprtMnychldprvtrtbz').replace(
          queryParameters: {
            'KEY': key,
            'Type': 'json',
            'pIndex': '$page',
            'pSize': '1000',
          },
        ),
        hide,
        log,
      );
      final root = (jsonDecode(body) as Map)['BrthspprtMnychldprvtrtbz'];
      if (root is! List) throw FormatException('경기 답 모양이 다릅니다');
      final total =
          ((root[0] as Map)['head'] as List).first['list_total_count'] as int;
      for (final r in (root[1] as Map)['row'] as List) {
        out.add({
          for (final e in (r as Map).entries)
            if (e.value != null) '${e.key}': '${e.value}',
        });
      }
      if (out.length >= total) return out;
    }
    return out;
  } finally {
    client.close(force: true);
  }
}

Future<String> _getText(
  HttpClient client,
  Uri uri,
  String Function(Object) hide,
  void Function(String)? log,
) async {
  for (var attempt = 1; ; attempt++) {
    try {
      final req = await client.getUrl(uri);
      final res = await req.close().timeout(const Duration(seconds: 90));
      final body = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 90));
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      return body;
    } catch (e) {
      if (attempt >= 5) throw HttpException(hide(e));
      log?.call('  다시 시도합니다($attempt/5): ${hide(e)}');
      await Future<void>.delayed(Duration(seconds: 5 * attempt));
    }
  }
}

// ── 서울 ──────────────────────────────────────────────────────────────

/// 서울 데이터의 글 — HTML 꼬리표(`<b class=…>`)와 글자 표시를 걷는다.
String seoulText(String? raw) {
  if (raw == null) return '';
  var t = raw
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');
  t = t.replaceAll(RegExp(r'[ \t ]+'), ' ');
  return t
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .join('\n');
}

/// 끝났거나 아직 정해지지 않은 사업 — 「(사업종료)」·「협의중」·「추후 안내」.
/// 몽땅정보통에는 2024년 글이 지금 글과 나란히 남아 있다(35세 이상 임산부
/// 의료비가 세 줄 — 옛 금액 50만원 · 「협의중」 100만원 · 지금 글).
bool isSeoulStale(Map<String, String> row) {
  final name = row['BIZ_NM'] ?? '';
  final body = row['BIZ_CN'] ?? '';
  if (RegExp(r'사업\s*종료|\(종료\)').hasMatch(name)) return true;
  return RegExp(r'협의\s?중|추후\s?안내|확정\s?시\s?재안내').hasMatch(body);
}

/// 대상 나이가 만 6세까지에 걸치는지 — 「연령무관」·「임신·출산」·「0세 ~ 5세」는
/// 걸치고 「10세 이상」은 아니다.
bool seoulAgeFits(String? age) {
  final a = (age ?? '').trim();
  if (a.isEmpty || a.contains('무관') || a.contains('임신')) return true;
  final nums = RegExp(r'(\d+)\s*세').allMatches(a).map((m) => int.parse(m[1]!));
  if (nums.isEmpty) return true;
  return nums.reduce((x, y) => x < y ? x : y) <= 6;
}

/// 분류가 곧 임신·출산인 칸. **분류만 믿지는 않는다** — 「서울시 소상공인
/// 휴업손실비용 지원사업」이 「출산」 칸에 있었다(2026-09-28).
const _seoulBirthCats = {'임신', '임신준비', '임신(준비)', '출산', '건강힐링'};

/// 분류가 임신·출산이어도 빼는 것 — 가게·회사·청년·결혼·집·행사.
const _seoulAdult = [
  '소상공인',
  '중소기업',
  '청년',
  '결혼',
  '대출',
  '주택',
  '전세',
  '공모',
  '축제',
  '콘서트',
  '포인트제',
];

/// 서울 사업이 이 앱(임신 준비~만 6세) 이야기인지.
///
/// **이름으로 본다**(복지로와 같은 까닭 — 본문에는 저출산 문구가 흔하다). 이름에
/// 임신·출산·육아 말이 있으면 넣되, 임신·출산 칸이 아니면 대상 나이가 만 6세까지에
/// 걸쳐야 한다. 이름이 모호하면(「B형 간염 수직감염 예방」·「우울증 자가진단 검사」)
/// 임신·출산 칸일 때만, 가게·청년·결혼·집 이야기가 아닐 때만.
bool isSeoulAboutBirth(Map<String, String> row) {
  final name = seoulText(row['BIZ_NM']);
  final cat = (row['BIZ_LCLSF_NM'] ?? '').replaceAll(' ', '');
  if (name.isEmpty || hasNotBirthWord(name)) return false;
  if (isOffTopic(name, null)) return false;
  final birthCat = _seoulBirthCats.contains(cat);
  if (isAboutBirth(name, null)) {
    return birthCat || seoulAgeFits(row['TRGT_CHILD_AGE']);
  }
  return birthCat && !_seoulAdult.any(name.contains);
}

/// 원문 — 앱의 「정보 출처」 목록에 있는 곳이면 그 주소, 아니면 몽땅정보통.
///
/// 서울 데이터의 링크는 서울시 여러 누리집·네이버 블로그까지 섞여 있다. 출처
/// 주소 목록(스토어 설명과 같아야 한다 — 심사 이력)에 없는 곳으로 보내지 않는다.
String seoulUrl(Map<String, String> row) {
  for (final k in ['DEVIW_SITE_ADDR', 'APLY_SITE_ADDR']) {
    final u = (row[k] ?? '').trim().replaceFirst(
      RegExp(r'^http://'),
      'https://',
    );
    final host = Uri.tryParse(u)?.host ?? '';
    if (u.startsWith('https://') && seoulLinkHosts.contains(host)) return u;
  }
  return seoulHome;
}

/// 서울 항목이 원문으로 쓸 수 있는 곳.
const seoulLinkHosts = {
  'umppa.seoul.go.kr', // 탄생육아 몽땅정보통
  'seoul-agi.seoul.go.kr', // 서울시 임신·출산 정보센터
  'www.bokjiro.go.kr',
  'www.easylaw.go.kr',
  'www.childcare.go.kr',
  'www.gov.kr',
};

const seoulHome = 'https://umppa.seoul.go.kr/hmpg/main.do';

/// 서울 한 줄 → 앱 항목.
Map<String, String> seoulItem(Map<String, String> row) {
  final name = seoulText(row['BIZ_NM']);
  final body = seoulText(row['BIZ_CN']);
  final how = seoulText(row['UTZTN_MTHD_CN']);
  return {
    'id': 'seoul:${_hash(name)}',
    'org': '서울특별시',
    'name': name,
    'url': seoulUrl(row),
    'source': 'seoul',
    ...?_opt('summary', body.split('\n').first),
    ...?_opt('content', body),
    ...?_opt('target', seoulText(row['UTZTN_TRPR_CN'])),
    ...?_opt('howText', how),
    ...?_opt('how', _howCodesOf(how)),
    ...?_opt('phone', seoulText(row['AREF_CN'])),
  };
}

// ── 경기 ──────────────────────────────────────────────────────────────

/// 경기 금액 칸은 천 원 단위다 — 「500」은 50만원, 「10000(분할지급)」은
/// 1,000만원(분할지급), 「1000(심한 장애인)/700(…)」은 둘 다 바꾼다.
String ggAmount(String raw) => raw.replaceAllMapped(
  // 「(20회분할)」·「36개월」의 수는 금액이 아니다.
  RegExp(r'(\d[\d,]*)(?![\d,]|\s*(?:회|개월|년|세|%|일|차|명|개))'),
  (m) => wonShortOf(int.parse(m[1]!.replaceAll(',', '')) * 1000),
);

/// 「50만원」·「1,000만원」·「5천원」.
String wonShortOf(int won) {
  if (won % 10000 == 0) {
    final man = won ~/ 10000;
    final s = man.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (m) => '${m[1]},',
    );
    return '$s만원';
  }
  return '${won ~/ 1000}천원';
}

/// 경기 한 줄 → 앱 항목. 원문은 경기도청의 「출산장려금 및 양육비 지원현황」.
Map<String, String> ggItem(Map<String, String> row) {
  final sigun = row['SIGUN_NM']!.trim();
  final biz = row['BIZ_NM']!.trim();
  const order = ['첫째', '둘째', '셋째', '넷째', '다섯째 이상'];
  const keys = [
    'CHILD_1_SPORTAMT_DTLS',
    'CHILD_2_SPORTAMT_DTLS',
    'CHILD_3_SPORTAMT_DTLS',
    'CHILD_4_SPORTAMT_DTLS',
    'CHILD_5_ABOVE_SPORTAMT_DTLS',
  ];
  final lines = [
    for (var i = 0; i < 5; i++)
      if ((row[keys[i]] ?? '').trim() case final v
          when v.isNotEmpty && v != '0')
        '${order[i]} ${ggAmount(v)}',
    if ((row['SPORT_PERD'] ?? '').trim() case final p when p.isNotEmpty)
      '지급: $p',
    if ((row['BASIS_CONT'] ?? '').trim() case final b when b.isNotEmpty)
      '근거: $b',
  ];
  return {
    'id': 'gg:${row['SIGUN_CD'] ?? sigun}:${_hash(biz)}',
    'org': '경기도 $sigun',
    'name': biz.startsWith(sigun) ? biz : '$sigun $biz',
    'url': ggHome,
    'source': 'gg',
    'summary': '$sigun $biz — 자녀 순서별 금액',
    'content': lines.join('\n'),
    ...?_opt('criteria', (row['PAYMNT_STD_CONT'] ?? '').trim()),
    'type': '현금',
  };
}

const ggHome =
    'https://www.gg.go.kr/contents/contents.do?ciIdx=987110&menuId=266074';

// ── 합치기 ────────────────────────────────────────────────────────────

/// 시·도 데이터에서 이미 있는 것([known] — 정부24·복지로 항목)과 같은 사업을
/// 빼고 남는 것. 같은 기관(서울은 서울특별시와 나라 기관)끼리 [sameService]로
/// 견준다. 나라 큰 제도(첫만남이용권 등)도 뺀다.
List<Map<String, String>> addNew(
  List<Map<String, String>> items,
  List<Map<String, String>> known, {
  bool againstNation = false,
}) {
  final keys = <String, List<String>>{};
  for (final k in known) {
    final org = isNationOrg(k['org']!) ? '(나라)' : k['org']!;
    (keys[org] ??= []).add(serviceKey(k['name']!, k['org']!));
  }
  final out = <Map<String, String>>[];
  for (final i in items) {
    final name = i['name']!;
    if (isCuratedCopy(name) ||
        curatedPrograms.any(
          (p) => p.names.any((w) => squash(name).contains(squash(w))),
        )) {
      continue;
    }
    final key = serviceKey(name, i['org']!);
    final pool = [...?keys[i['org']], if (againstNation) ...?keys['(나라)']];
    if (pool.any((k) => sameService(k, key))) continue;
    (keys[i['org']!] ??= []).add(key);
    out.add(i);
  }
  return out;
}

String? _howCodesOf(String how) {
  final codes = <String>{
    if (RegExp('방문|보건소|주민센터|동주민|행정복지센터').hasMatch(how)) '방문신청',
    if (RegExp('온라인|홈페이지|누리집|몽땅|앱|정부24|복지로').hasMatch(how)) '기타 온라인신청',
  };
  return codes.isEmpty ? null : codes.join('||');
}

Map<String, String>? _opt(String k, String? v) =>
    v == null || v.trim().isEmpty ? null : {k: v.trim()};

/// 이름으로 만든 짧은 번호 — 서울·경기 데이터에는 사업 번호가 없다.
String _hash(String s) => contentRev([
  {'n': s},
]).substring(0, 12);
