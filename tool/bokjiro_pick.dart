// 복지로 「지자체복지서비스」 목록에서 이 앱에 더할 것을 고른다 — 정부24
// 공공서비스 목록에 **없는** 지자체의 임신·출산·육아 지원.
//
// 사장님 2026-09-27 「시군구 단위의 모든 지원서비스를 담아야 되는데」, 「api로
// 내용을 받고 있었는데 그것만으로는 시군구 단위는 못 보는 것 같아」. 같은 날
// 두 목록을 견주니 복지로에만 있는 것이 수백 건이었다(군포시 임신축하금,
// 하남·칠곡 산후조리비, 성동구 미숙아 RSV 접종비…). 반대로 같은 사업이 두
// 곳에 이름만 조금 달리 올라온 것도 많다(태백시 「출산양육비 지원」 ↔
// 「출산양육 지원금 지원」) — 앱에 같은 돈이 두 번 보이면 안 되니 정부24 것을
// 남기고 복지로 것은 뺀다([sameService]).
//
// 거르는 낱말은 정부24와 같다(gov24_pick.dart의 [isAboutBirth] 들) — 두 목록이
// 다르게 걸러지면 한 지역 안에서 어떤 것은 들고 어떤 것은 빠진다.
//
// dart 기본 라이브러리만 쓴다(공개 저장소 tool/에 그대로 복사해 돈다).

import 'gov24_pick.dart';

/// 복지로 한 줄의 기관 이름 — 「서울특별시 마포구」·「경기도」. 앱의 기관
/// 이름 꼴(정부24 소관기관명)에 맞춘다. 지자체가 아니면(교육청 등) null.
String? bokjiroOrg(Map<String, String> row) {
  final ctpv = row['ctpvNm']?.trim();
  if (ctpv == null || !sidoNames.contains(ctpv)) return null;
  final sgg = row['sggNm']?.trim();
  if (sgg == null || sgg.isEmpty || sgg == '-' || sgg == ctpv) return ctpv;
  if (sgg.endsWith('교육청') || sgg.endsWith('교육지원청')) return null;
  return '$ctpv $sgg';
}

/// 복지로 제공유형 → 정부24 지원유형 꼴(앱의 [SupportSide]가 이것으로 가른다).
/// 여럿이면 `||`로 잇는다.
String? bokjiroType(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  String one(String t) => switch (t.trim()) {
    '현금지급' || '지역화폐' => '현금',
    '감면' => '현금(감면)',
    '전자바우처(바우처)' || '실물바우처' => '이용권',
    '현물지급' || '현물대여' => '현물',
    '시설입소' => '시설',
    '프로그램/서비스(서비스)' => '서비스',
    _ => '기타',
  };
  return {for (final t in raw.split(',')) one(t)}.join('||');
}

/// 이름을 견주기 좋게 — 괄호 속 말(「(기준중위소득 150% 이하)」·「(수지구)」)을
/// 걷고, 띄어쓰기·기호, 기관 이름(「마포구」·「마포」·「서울시」), 꾸밈말(본인부담금·
/// 추가·확대·자체·모든…)과 흔한 꼬리말(지원·사업·지급·금·비…)을 뗀다.
String serviceKey(String name, String org) {
  var n = name.replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]|〔[^〕]*〕'), '');
  n = squash(n).replaceAll(RegExp(r'[「」<>〈〉\-_,.:·~]'), '');
  for (final token in org.split(RegExp(r'\s+'))) {
    for (final v in {
      token,
      if (token.length > 2) token.substring(0, token.length - 1),
      if (token.endsWith('특별시') || token.endsWith('광역시'))
        '${token.substring(0, 2)}시',
      token.length >= 2 ? token.substring(0, 2) : token,
    }) {
      if (v.length >= 2) n = n.replaceAll(v, '');
    }
  }
  for (final w in _filler) {
    n = n.replaceAll(w, '');
  }
  const tails = [
    '지원사업',
    '지원금',
    '지원',
    '사업',
    '지급',
    '서비스',
    '운영',
    '신청',
    '안내',
    '제공',
    '금',
    '비',
  ];
  var changed = true;
  while (changed && n.length > 2) {
    changed = false;
    for (final t in tails) {
      if (n.endsWith(t) && n.length - t.length >= 2) {
        n = n.substring(0, n.length - t.length);
        changed = true;
        break;
      }
    }
  }
  return n;
}

/// 사업을 가르지 않는 꾸밈말 — 두 목록이 같은 사업을 달리 적을 때 붙는 것.
/// 「저소득」·「셋째아」·「다자녀」처럼 **대상을 가르는 말은 넣지 않는다.**
const _filler = [
  '본인부담금',
  '본인부담',
  '추가',
  '확대',
  '자체',
  '모든',
  '기존',
  '쿠폰',
  '발급',
  '이용',
  '및',
];

/// 시군구가 출산하면 주는 돈 — 「출산장려금」·「출산지원금」·「출산양육지원금」·
/// 「출생축하금」·「신생아 출산지원금」. 한 시군구에 대개 하나라, 두 목록에서
/// 이름이 달라도 같은 사업으로 본다(2026-09-27 두 목록을 견줘 보니 울산 중구
/// 「출산지원금」↔「출산양육지원금」, 경주 「출산축하금 및 출산장려금」↔
/// 「출산장려금」이 같은 것이었다).
bool isBirthBonus(String key) {
  if (key.isEmpty) return false;
  var rest = key;
  for (final w in [
    '출산',
    '출생',
    '입양',
    '신생아',
    '양육',
    '장려',
    '축하',
    '지원',
    '금',
    '아이',
  ]) {
    rest = rest.replaceAll(w, '');
  }
  return rest.isEmpty && (key.contains('출산') || key.contains('출생'));
}

/// 두 글자씩 끊은 조각의 겹침(다이스 계수) — 0~1.
double bigramDice(String a, String b) {
  List<String> grams(String s) => [
    for (var i = 0; i + 1 < s.length; i++) s.substring(i, i + 2),
  ];
  final x = grams(a), y = grams(b);
  if (x.isEmpty || y.isEmpty) return a == b ? 1 : 0;
  final pool = [...y];
  var common = 0;
  for (final g in x) {
    if (pool.remove(g)) common++;
  }
  return 2 * common / (x.length + y.length);
}

/// 같은 기관의 두 이름이 같은 사업인지([serviceKey]로 걷은 것끼리).
///
/// 같거나, 둘 다 출산 축하 현금([isBirthBonus])이거나, 두 글자 조각이 6할 넘게
/// 겹치거나, 한쪽이 다른 쪽을 품는데 **덧붙은 말이 대상을 가르지 않을 때**
/// (「국내 입양가정 입양축하금」 ⊃ 「입양축하금」, 「임산부를 위한 마더박스」 ⊃
/// 「마더박스」). 「저소득층 산후조리비」 ⊃ 「산후조리비」처럼 덧붙은 말이 따로
/// 있으면 다른 사업으로 둔다 — 사장님 「빠지는 게 있어서는 안 돼」. 애매하면 둘 다
/// 남긴다(두 번 보이는 것이 빠지는 것보다 낫다).
bool sameService(String keyA, String keyB) {
  if (keyA.isEmpty || keyB.isEmpty) return false;
  if (keyA == keyB) return true;
  if (isBirthBonus(keyA) && isBirthBonus(keyB)) return true;
  final (short, long) = keyA.length <= keyB.length
      ? (keyA, keyB)
      : (keyB, keyA);
  // 한쪽이 다른 쪽을 품으면 덧붙은 말로만 가른다 — 조각 겹침으로 보면
  // 「저소득층 산후조리비」와 「산후조리비」가 6할 겹쳐 같은 것이 된다.
  if (short.length < 3 || !long.contains(short)) {
    return bigramDice(keyA, keyB) >= 0.6;
  }
  var extra = long.replaceFirst(short, '');
  for (final w in _harmless) {
    extra = extra.replaceAll(w, '');
  }
  return extra.length <= 2;
}

/// 덧붙어도 사업을 가르지 않는 말.
const _harmless = [
  '국내',
  '관내',
  '가정',
  '가구',
  '임산부',
  '를',
  '위한',
  '첫째',
  '아이',
  '부터',
  '신규',
  '전체',
  '우리',
  '행복',
  '희망',
  '사랑',
  '건강한',
];

/// 복지로 한 줄이 임신·출산·육아 이야기인지.
///
/// **이름으로 본다**([isAboutBirth]에 요약을 안 넘긴다). 복지로 요약에는
/// 「저출산 극복」 같은 말이 흔해서 요약까지 보면 신혼부부 전세 대출이자·
/// 결혼장려금·캠핑장 감면이 수십 건 들어왔다(2026-09-27).
///
/// 이름이 모호하면(「천사지원금」·「행복키움수당」·「(BIG3) 1천만원+HAPPY I」)
/// 복지로가 붙인 분류를 본다 — 생애주기가 영유아·아동·임신·출산**뿐**이거나
/// 관심주제가 임신·출산일 때만, 그리고 주택·대출·결혼 사업이 아닐 때만.
bool isBokjiroAboutBirth(Map<String, String> row) {
  final name = row['servNm']?.trim() ?? '';
  if (name.isEmpty) return false;
  if (isOffTopic(name, row['servDgst'])) return false;
  if (isAboutBirth(name, null)) return true;
  if (hasNotBirthWord(name)) return false;
  List<String> tags(String? raw) => [
    for (final t in (raw ?? '').split(','))
      if (t.trim().isNotEmpty) t.replaceAll(' ', '').trim(),
  ];
  final life = tags(row['lifeNmArray']);
  final theme = tags(row['intrsThemaNmArray']);
  final kidOnly =
      life.isNotEmpty && life.every(const {'영유아', '아동', '임신·출산'}.contains);
  if (!kidOnly && !theme.contains('임신·출산')) return false;
  return !_adultWords.any(name.contains);
}

/// 분류만 보고 들일 때 빼는 것 — 신혼부부 집·대출과 결혼.
const _adultWords = [
  '주택',
  '주거',
  '전세',
  '월세',
  '임차',
  '대출',
  '이자',
  '보금자리',
  '신혼집',
  '결혼',
  '웨딩',
  '청년',
];

/// 고른 결과.
class BokjiroPick {
  BokjiroPick({required this.rows, required this.duplicates});

  /// 더할 것 — 복지로 목록 줄 그대로(상세는 따로 받는다).
  final List<Map<String, String>> rows;

  /// 정부24 것과 같아서 뺀 수.
  final int duplicates;
}

/// 복지로 목록에서 정부24 것([gov] — [pickSupports]의 항목)에 없는 지자체의
/// 임신·출산·육아 지원을 고른다. 복지로 안에서 겹친 것도 하나만.
BokjiroPick pickBokjiro(
  List<Map<String, String>> rows,
  List<Map<String, String>> gov,
) {
  final keysByOrg = <String, List<String>>{};
  for (final g in gov) {
    (keysByOrg[g['org']!] ??= []).add(serviceKey(g['name']!, g['org']!));
  }
  final out = <Map<String, String>>[];
  final seen = <String>{};
  var duplicates = 0;
  for (final r in rows) {
    final id = r['servId'];
    final name = r['servNm']?.trim();
    final url = r['servDtlLink']?.trim();
    if (id == null || name == null || url == null || !seen.add(id)) continue;
    if (!url.startsWith('https://www.bokjiro.go.kr/')) continue;
    final org = bokjiroOrg(r);
    if (org == null) continue;
    if (!isBokjiroAboutBirth(r)) continue;
    if (isCuratedCopy(name)) continue;
    final key = serviceKey(name, org);
    final known = keysByOrg[org] ??= [];
    if (known.any((k) => sameService(k, key))) {
      duplicates++;
      continue;
    }
    known.add(key);
    out.add({...r, 'org': org});
  }
  return BokjiroPick(rows: out, duplicates: duplicates);
}

/// 복지로 한 가지를 앱 모양으로 — 정부24 항목과 같은 칸 이름.
/// [detail]이 없으면 목록 줄의 요약만 든다(다음 달에 상세를 채운다).
Map<String, String> bokjiroItem(
  Map<String, String> row,
  Map<String, Object?>? detail,
) {
  String? d(String k) {
    final v = detail?[k];
    final t = v is String ? cleanText(v) : null;
    return t == null ? null : restoreLines(t);
  }

  // 신청 방법은 정부24 꼴의 짧은 말로(앱이 칩으로 보인다) — 「방문신청||기타
  // 온라인신청」. 복지로의 긴 설명은 howText로 따로.
  final how = {
    for (final m in (row['aplyMtdNm'] ?? '').split(',')) ?_howCodes[m.trim()],
  }.join('||');
  final inq = detail?['inqpl'];
  final phones = <String>[
    if (inq is List)
      for (final e in inq)
        if (e is Map)
          [
            ?cleanText(e['wlfareInfoReldNm'] as String?),
            ?cleanText(e['wlfareInfoReldCn'] as String?),
          ].join(' '),
  ].where((s) => s.isNotEmpty).toList();
  return {
    'id': 'bokjiro:${row['servId']}',
    'org': row['org']!,
    'name': cleanText(row['servNm'])!,
    'url': row['servDtlLink']!.trim(),
    'source': 'bokjiro',
    ...?_opt('summary', cleanText(row['servDgst'])),
    ...?_opt('target', d('sprtTrgtCn')),
    ...?_opt('criteria', d('slctCritCn')),
    ...?_opt('content', d('alwServCn')),
    ...?_opt('how', how.isEmpty ? null : how),
    ...?_opt('howText', d('aplyMtdCn')),
    ...?_opt('phone', phones.isEmpty ? null : phones.join('||')),
    ...?_opt('type', bokjiroType(row['srvPvsnNm'])),
    ...?_opt('modified', cleanText(row['lastModYmd'])),
  };
}

const _howCodes = {
  '방문': '방문신청',
  '인터넷': '기타 온라인신청',
  '모바일': '기타 온라인신청',
  '전화': '전화신청',
  '우편': '우편신청',
  'E-mail': '이메일신청',
};

Map<String, String>? _opt(String k, String? v) => v == null || v.isEmpty
    ? null
    : {k: v.replaceAll(RegExp(r'\n{3,}'), '\n\n')};

/// 복지로 받기 — 검사에서 가짜로 바꿔 끼운다.
class BokjiroSource {
  const BokjiroSource({required this.list, required this.detail});

  final Future<List<Map<String, String>>> Function() list;
  final Future<Map<String, Object?>> Function(String servId) detail;
}

/// 한 달치 복지로 결과.
class BokjiroRun {
  BokjiroRun({
    required this.items,
    required this.cache,
    required this.listed,
    required this.duplicates,
    required this.fetchedDetails,
    required this.missingDetails,
    this.error,
  });

  /// 앱 모양 항목([bokjiroItem]).
  final List<Map<String, String>> items;

  /// 상세 저장분 — {servId: {modified, detail}}. 다음 달엔 바뀐 것만 받는다.
  final Map<String, Object?> cache;

  /// 복지로 목록 전체 수(0이면 못 받은 것).
  final int listed;
  final int duplicates;

  /// 이번에 새로 받은 상세 수(하루 한도 [detailBudget] 안).
  final int fetchedDetails;

  /// 상세가 아직 없는 항목 수 — 다음 달에 받는다.
  final int missingDetails;

  /// 목록을 못 받았으면 까닭. 그때 [items]는 지난달 것 그대로다.
  final String? error;
}

/// 한 번에 받는 상세 수 — 개발계정 하루 1,000번에서 목록 쪽(10번 안팎)과
/// 여유를 뺐다.
const detailBudget = 900;

/// 복지로 목록을 받아 정부24 것([gov])에 없는 것을 고르고, 상세를 채운다.
///
/// 상세는 [cache]에 있고 최종수정일이 같으면 다시 안 받는다. 목록을 못 받으면
/// 지난달 파일의 복지로 항목([previous])을 그대로 쓴다 — 한 달 사고로 수백 건이
/// 앱에서 사라지지 않게.
Future<BokjiroRun> runBokjiro({
  required BokjiroSource source,
  required List<Map<String, String>> gov,
  required Map<String, Object?> cache,
  required List<Map<String, String>> previous,
  String Function(Object)? hide,
  int budget = detailBudget,
}) async {
  String safe(Object e) => hide == null ? '$e' : hide(e);
  final List<Map<String, String>> rows;
  try {
    rows = await source.list();
  } catch (e) {
    return BokjiroRun(
      items: previous,
      cache: cache,
      listed: 0,
      duplicates: 0,
      fetchedDetails: 0,
      missingDetails: 0,
      error: safe(e),
    );
  }
  final pick = pickBokjiro(rows, gov);
  final next = <String, Object?>{};
  var fetched = 0;
  var missing = 0;
  var stop = false;
  final items = <Map<String, String>>[];
  for (final row in pick.rows) {
    final id = row['servId']!;
    final modified = row['lastModYmd'] ?? '';
    var saved = cache[id] is Map ? cache[id] as Map : null;
    if ((saved == null || saved['modified'] != modified) &&
        !stop &&
        fetched < budget) {
      try {
        final detail = await source.detail(id);
        fetched++;
        saved = {'modified': modified, 'detail': detail};
      } catch (e) {
        // 한도가 찼거나 키가 막히면 나머지는 다음 달에.
        stop = true;
      }
    }
    if (saved != null) next[id] = saved;
    final detail = saved?['detail'];
    if (detail is! Map) missing++;
    items.add(
      bokjiroItem(row, detail is Map ? detail.cast<String, Object?>() : null),
    );
  }
  return BokjiroRun(
    items: items,
    cache: next,
    listed: rows.length,
    duplicates: pick.duplicates,
    fetchedDetails: fetched,
    missingDetails: missing,
  );
}

/// 복지로 상세 글의 줄을 되살린다 — 복지로 API는 줄바꿈을 모두 지워서 보낸다
/// (2026-09-27 받은 689건 전부 한 줄). 「지원대상출산(유·사산)한 … 임산부자격요건①
/// 고용노동부…② 신청일 기준…」처럼 붙어 나와 앱의 「누가」 줄이 읽히지 않았다.
///
/// 글머리(①~⑳·○·●·■·□·▶·◆·※·「- 」) 앞에서, 그리고 제목 말(지원대상·자격요건·
/// 선정기준·지원내용…)이 글머리나 쌍점 앞에 붙어 있으면 그 앞뒤에서 줄을 나눈다.
String restoreLines(String text) {
  var t = text;
  // 제목 말 — 글 맨 앞이거나, 바로 뒤가 글머리·쌍점일 때만.
  final heads = RegExp(
    r'(지원\s?대상|자격\s?요건|선정\s?기준|지원\s?내용|지원\s?기준|지원\s?금액|'
    r'신청\s?방법|신청\s?기간|제출\s?서류|구비\s?서류|유의\s?사항|대상자|지원\s?조건)'
    r'(?=\s*[:：]|\s*[①-⑳○●■□▶◆❍※]|\s*-\s)',
  );
  t = t.replaceAllMapped(heads, (m) => '\n${m[1]}\n');
  if (RegExp(r'^\s*(지원\s?대상|지원\s?내용|선정\s?기준)(?=\S)').firstMatch(t)
      case final m?) {
    t = '${m[1]}\n${t.substring(m.end)}';
  }
  // 글머리 앞 — 「(※ …)」처럼 괄호 안의 것은 두고.
  t = t.replaceAllMapped(
    RegExp(r'(?<=[^\s(\n])\s*([①-⑳○●■□▶◆❍]|※(?!\))|-\s)'),
    (m) => '\n${m[1]}',
  );
  return t
      // 글머리만 남은 줄(「○」)은 다음 줄과 잇는다.
      .replaceAllMapped(
        RegExp(r'(^|\n)([①-⑳○●■□▶◆❍※-])[ \t]*\n'),
        (m) => '${m[1]}${m[2]} ',
      )
      .replaceAll(RegExp(r'\n\s*[:：]\s*'), '\n')
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n{2,}'), '\n')
      .trim();
}
