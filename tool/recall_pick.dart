// 리콜 소식 — 제품안전정보센터(국가기술표준원) 국내리콜 공표에서 육아·어린이
// 품목만 골라 앱 품목(subId)과 짝 짓는다(2026-11-08, `docs/history/2026-11-08_리콜.md`).
//
// **짝은 보수적으로 짓는다.** 짝을 잘못 지으면 멀쩡한 물건 화면에 「이 종류 리콜」이
// 선다. 그래서 낱말 표([recallRules])에 적은 것만, 그것도 다음 셋 가운데 하나일 때만
// 짝이다 — 확신이 낮으면 버린다.
//   1) 제품명 끝 괄호 안의 **법정 품목 이름**이 표와 같다(「유모차(유모차)」,
//      「유아용 부스터 의자(유아용 의자)」). 괄호가 없으면 제품명 전체가 같다.
//   2) 괄호 앞 제품명이 표의 **이름과 같다**(「블록완구(완구)」).
//   3) 괄호 앞 제품명이 표의 **끝말로 끝난다**(「스토케 요요3 (Stokke YoYo3) 유모차」).
//      끝말은 아기 물건에만 쓰는 낱말만 적는다 — 「캐리어」가 아니라 「유아용캐리어」.
// 그리고 제품명·모델명에 [recallBlockWords](반려·성인·전동…)나 그 줄의 빼는 말이 있으면
// 버린다. 「여행용 캐리어」·「전동킥보드」·「전기침대」·「카시트 어댑터」·「노리개젖꼭지
// 걸이」가 여기서 빠진다(`test/recall_pick_test.dart`).
//
// 앱은 이 파일을 보지 않는다. 결과는 `v1/data.json`의 `recalls`로 올라가고, 앱은
// 원문 칸을 그대로 보여 줄 뿐 판정하지 않는다(「모델명을 직접 확인하세요」).

/// 낱말 표 한 줄 — 이 줄에 걸린 공표는 [subs] 품목 모두에 붙는다.
class RecallRule {
  const RecallRule({
    required this.subs,
    required this.search,
    this.categories = const [],
    this.names = const [],
    this.endings = const [],
    this.modelHas = const [],
    this.exclude = const [],
  });

  /// 앱 품목 id(`CategoryCatalog`). 같은 법정 품목이면 여럿(유모차 넷).
  final List<String> subs;

  /// 국내리콜 조회(제품명)에 넣을 검색어.
  final List<String> search;

  /// 법정 품목 이름 — 제품명 끝 괄호 안(괄호가 없으면 제품명 전체)과 같아야 짝.
  final List<String> categories;

  /// 괄호 앞 제품명과 같아야 짝.
  final List<String> names;

  /// 괄호 앞 제품명이 이 말로 끝나면 짝. 아기 물건에만 쓰는 낱말만.
  final List<String> endings;

  /// 있으면 제품명·모델명에 이 가운데 하나가 있어야 짝 — 법정 품목이 넓을 때
  /// (어린이용 장신구 가운데 머리핀만).
  final List<String> modelHas;

  /// 제품명·모델명에 이 말이 있으면 버린다.
  final List<String> exclude;
}

/// 낱말 표. 줄을 더할 때는 `test/recall_pick_test.dart`에 짝이 되는 예와 안 되는
/// 예를 같이 적는다. 옷(유아용 섬유제품)·완구 전체·가습기 같은 전기용품은
/// 품목과 1:1로 안 맞아 넣지 않았다.
const recallRules = <RecallRule>[
  RecallRule(
    subs: ['C4-01', 'C4-02', 'C4-11', 'C4-26'], // 유모차 넷
    search: ['유모차'],
    categories: ['유모차'],
    endings: ['유모차'],
    exclude: ['어댑터'],
  ),
  RecallRule(
    subs: ['C4-03', 'C4-09', 'C4-15'], // 카시트·바구니 카시트·주니어 카시트
    // 요즘 공표의 법정 품목은 「자동차용 어린이 보호장치」(유아용좌석·부스터 좌석).
    search: ['카시트', '보호장치'],
    categories: ['어린이용 카시트', '자동차용 어린이 보호장치'],
    endings: ['카시트'],
    exclude: ['어댑터'],
  ),
  RecallRule(
    subs: ['C3-01'], // 아기침대
    search: ['침대', '요람'],
    categories: ['유아용 침대', '가정용 유아용침대 및 요람'],
    endings: ['유아용침대', '아기침대', '요람'],
    exclude: ['전기'],
  ),
  RecallRule(
    subs: ['C3-13'], // 아기 병풍·가드
    search: ['가드', '병풍'],
    endings: ['침대가드', '침대안전가드', '아기병풍'],
  ),
  RecallRule(
    subs: ['C4-04', 'C4-05'], // 아기띠·힙시트(법정 품목 「유아용 캐리어」)
    search: ['캐리어', '아기띠', '힙시트'],
    categories: ['유아용 캐리어'],
    endings: ['유아용캐리어', '아기띠', '힙시트'],
  ),
  RecallRule(
    subs: ['C8-02', 'C8-15'], // 아기의자·부스터 의자(법정 품목 「유아용 의자」)
    search: ['의자', '하이체어'],
    categories: ['유아용 의자'],
    endings: ['유아용의자', '아기의자', '하이체어', '부스터의자'],
    exclude: ['목욕'],
  ),
  RecallRule(
    subs: ['C2-04'], // 아기욕조
    search: ['욕조'],
    endings: ['아기욕조', '유아욕조', '유아용욕조'],
  ),
  RecallRule(
    subs: ['C7-07'], // 보행기
    search: ['보행기'],
    categories: ['보행기', '유아용 보행기'],
    endings: ['보행기'],
  ),
  RecallRule(
    subs: ['C7-42'], // 세발자전거(법정 품목 「유아용 삼륜차」)
    search: ['삼륜차', '세발'],
    categories: ['유아용 삼륜차'],
    endings: ['유아용삼륜차', '세발자전거'],
  ),
  RecallRule(
    subs: ['C4-16'], // 킥보드 — 「어린이용 킥보드」만(「킥보드(킥보드)」는 어른 것과 안 갈린다)
    search: ['킥보드'],
    categories: ['어린이용 킥보드'],
    endings: ['어린이용킥보드', '어린이킥보드', '유아킥보드'],
    exclude: ['전동'],
  ),
  RecallRule(
    subs: ['C7-20'], // 보조바퀴 자전거
    search: ['자전거'],
    categories: ['어린이용 자전거'],
    endings: ['어린이용자전거', '어린이자전거', '아동자전거'],
    exclude: ['전기', '전동'],
  ),
  RecallRule(
    subs: ['C7-18'], // 밸런스바이크
    search: ['밸런스'],
    endings: ['밸런스바이크'],
  ),
  RecallRule(
    subs: ['C4-18'], // 유아 우산
    search: ['우산'],
    categories: ['어린이용 우산 및 양산', '어린이용 우산'],
    endings: ['어린이우산', '어린이용우산', '아동우산', '유아우산'],
  ),
  RecallRule(
    subs: ['C5-25'], // 여아 머리핀·머리끈 — 어린이용 장신구 가운데 머리에 하는 것만
    search: ['장신구', '머리핀'],
    categories: ['어린이용 장신구'],
    modelHas: ['머리핀', '머리끈', '헤어핀', '헤어끈', '똑딱핀'],
  ),
  RecallRule(
    subs: ['C7-10'], // 쪽쪽이 — 젖꼭지 걸이(클립)는 안 붙는다
    search: ['노리개', '쪽쪽이'],
    endings: ['노리개젖꼭지', '쪽쪽이'],
  ),
  RecallRule(
    subs: ['C7-02'], // 치발기
    search: ['치발기', '치아발육기'],
    endings: ['치발기', '치아발육기'],
  ),
  RecallRule(
    subs: ['C7-27'], // 딸랑이
    search: ['딸랑이'],
    endings: ['딸랑이'],
  ),
  RecallRule(
    subs: ['C7-12'], // 블록·쌓기 장난감
    search: ['블록'],
    names: ['블록완구', '쌓기완구'],
  ),
  RecallRule(
    subs: ['C7-35'], // 자석 블록 — 자석완구 가운데 블록만
    search: ['자석'],
    names: ['자석완구'],
    endings: ['자석블록'],
    modelHas: ['블록'],
  ),
  RecallRule(
    subs: ['C7-01'], // 모빌
    search: ['모빌'],
    endings: ['아기모빌', '유아모빌', '침대모빌'],
  ),
  RecallRule(
    subs: ['C7-04'], // 놀이매트 — 공표 이름은 「바닥매트(합성수지제 어린이용품)」, 전기매트는 안 붙는다
    search: ['바닥매트', '놀이매트'],
    names: ['바닥매트', '놀이매트', '놀이방매트'],
  ),
  RecallRule(
    subs: ['C7-03'], // 아기체육관
    search: ['체육관', '플레이짐'],
    endings: ['아기체육관', '플레이짐'],
  ),
  RecallRule(subs: ['C7-05'], search: ['점퍼루'], endings: ['점퍼루']),
  RecallRule(subs: ['C7-41'], search: ['쏘서'], endings: ['쏘서']),
  RecallRule(subs: ['C7-25'], search: ['바운서'], endings: ['바운서']),
  RecallRule(
    subs: ['C1-03'], // 젖병소독기
    search: ['젖병'],
    endings: ['젖병소독기'],
  ),
  RecallRule(
    subs: ['C10-01'], // 안전문 — 「안전문」만으로는 현관 방범문과 안 갈려 아기 낱말을 붙인다
    search: ['안전문'],
    endings: ['유아안전문', '아기안전문', '베이비게이트'],
  ),
];

/// 제품명·모델명에 있으면 어느 줄이든 버리는 말 — 반려동물·어른·의료 용품.
const recallBlockWords = ['반려', '애완', '강아지', '고양이', '성인', '노인', '고령자', '의료용'];

/// 이보다 오래된 공표는 안 싣는다(5년). 중고로 오가는 기간은 넉넉히 덮고,
/// 오래된 공표로 줄이 길어지지 않게.
const recallYears = 5;

/// 품목 하나에 싣는 공표 수 — 최근 것부터. 어린이 우산처럼 한 해에 열 건 넘게
/// 나오는 품목이 데이터 파일을 키우지 않게.
const recallsPerItem = 12;

/// 원문 칸 하나의 최대 글자 수. 넘으면 그 공표를 싣지 않는다(자르면 원문이 아니다).
const recallMaxText = 4000;

/// 국내리콜 조회에 넣을 검색어 전부(겹침 없이).
List<String> get recallSearchTerms =>
    {for (final r in recallRules) ...r.search}.toList();

String _squash(String s) => s.replaceAll(RegExp(r'\s+'), '');

/// 「유아용 부스터 의자(유아용 의자)」 → (`유아용부스터의자`, `유아용의자`).
/// 끝이 괄호가 아니면 괄호 안은 없다(제품명 전체가 법정 품목일 수 있다).
(String base, String? category) splitRecallName(String name) {
  final m = RegExp(r'^(.*\S)\s*\(([^()]+)\)\s*$').firstMatch(name.trim());
  if (m == null) return (_squash(name), null);
  return (_squash(m.group(1)!), _squash(m.group(2)!));
}

/// 공표 하나가 짝 지어지는 품목 id들. 없으면 빈 집합.
Set<String> matchRecall(Map<String, Object?> row) {
  final name = _text(row['recallProductName']);
  if (name == null) return const {};
  final model = _text(row['recallModelName']) ?? '';
  final all = _squash('$name $model');
  if (recallBlockWords.any((w) => all.contains(_squash(w)))) return const {};
  final (base, category) = splitRecallName(name);
  final out = <String>{};
  for (final rule in recallRules) {
    if (rule.exclude.any((w) => all.contains(_squash(w)))) continue;
    final byCategory = rule.categories.any((c) {
      final want = _squash(c);
      return category == want || (category == null && base == want);
    });
    final byName = rule.names.any((n) => base == _squash(n));
    final byEnding = rule.endings.any((e) => base.endsWith(_squash(e)));
    if (!byCategory && !byName && !byEnding) continue;
    if (rule.modelHas.isNotEmpty &&
        !rule.modelHas.any((w) => all.contains(_squash(w)))) {
      continue;
    }
    out.addAll(rule.subs);
  }
  return out;
}

/// 고른 결과.
class RecallPick {
  RecallPick(this.items, {required this.unmatched, required this.tooOld});

  /// data.json `recalls.items` 한 줄씩 — 최근 공표부터.
  final List<Map<String, Object?>> items;

  /// 받았지만 짝이 없어 버린 수(어른 물건·전기용품·확신 낮은 것).
  final int unmatched;

  /// 짝은 있지만 [recallYears]보다 오래돼 버린 수.
  final int tooOld;

  /// 리콜이 붙은 품목 수.
  int get subCount =>
      {for (final i in items) ...(i['subs'] as List).cast<String>()}.length;
}

/// 받은 공표([rows], 국내리콜 조회 칸 이름 그대로)에서 육아 품목과 짝이 되는 것만
/// 골라 data.json 모양으로 바꾼다. 같은 공표가 여러 검색어로 와도 한 번만.
RecallPick pickRecalls(List<Map<String, Object?>> rows, DateTime now) {
  final since = DateTime(now.year - recallYears, now.month, now.day);
  final seen = <String>{};
  final matched = <Map<String, Object?>>[];
  var unmatched = 0;
  var tooOld = 0;
  for (final row in rows) {
    final id = _text('${row['recallUid'] ?? ''}');
    if (id == null || !RegExp(r'^\d{1,12}$').hasMatch(id) || !seen.add(id)) {
      continue;
    }
    final subs = matchRecall(row);
    if (subs.isEmpty) {
      unmatched++;
      continue;
    }
    final date = _day(row['publishDate']);
    if (date == null) {
      unmatched++;
      continue;
    }
    if (DateTime.parse(date).isBefore(since)) {
      tooOld++;
      continue;
    }
    final item = _item(id, subs, date, row);
    if (item == null) {
      unmatched++;
      continue;
    }
    matched.add(item);
  }
  // 최근 공표부터, 같은 날이면 번호 큰 것부터 — 품목마다 [recallsPerItem]건까지.
  matched.sort((a, b) {
    final byDate = (b['date'] as String).compareTo(a['date'] as String);
    return byDate != 0
        ? byDate
        : int.parse(b['id'] as String).compareTo(int.parse(a['id'] as String));
  });
  final perSub = <String, int>{};
  final items = <Map<String, Object?>>[];
  for (final item in matched) {
    final keep = [
      for (final s in item['subs'] as List<String>)
        if ((perSub[s] ?? 0) < recallsPerItem) s,
    ];
    if (keep.isEmpty) continue;
    for (final s in keep) {
      perSub[s] = (perSub[s] ?? 0) + 1;
    }
    items.add({...item, 'subs': keep});
  }
  return RecallPick(items, unmatched: unmatched, tooOld: tooOld);
}

/// data.json에 넣을 묶음.
Map<String, Object?> recallsSection(
  List<Map<String, Object?>> items,
  String checked,
) => {'checked': checked, 'source': 'safetykorea', 'items': items};

/// 지난 data.json의 리콜 건수(없으면 0).
int recallCountOf(Object? section) {
  final items = section is Map ? section['items'] : null;
  return items is List ? items.length : 0;
}

/// 앱(`RecallNotices.read`)과 같은 규칙으로 본다. 문제가 없으면 빈 목록.
///
/// 앱은 깨진 공표를 한 건씩 버린다. 여기서는 **한 건이라도 깨졌으면 올리지
/// 않는다** — 매달 작업이 만든 것이 깨졌다면 코드가 틀린 것이다.
List<String> validateRecalls(Object? section) {
  if (section == null) return const [];
  if (section is! Map) return ['recalls 모양'];
  final problems = <String>[];
  final checked = section['checked'];
  if (checked != null &&
      (checked is! String ||
          !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(checked))) {
    problems.add('recalls checked');
  }
  final items = section['items'];
  if (items is! List) return [...problems, 'recalls items'];
  if (items.length > 600) problems.add('recalls 600건 초과');
  final subId = RegExp(r'^C\d{1,2}-\d{2}$');
  for (final i in items) {
    final id = i is Map ? i['id'] : null;
    String where(String what) => 'recall $id $what';
    if (i is! Map || id is! String || !RegExp(r'^\d{1,12}$').hasMatch(id)) {
      problems.add('recall id');
      continue;
    }
    final subs = i['subs'];
    if (subs is! List ||
        subs.isEmpty ||
        subs.any((s) => s is! String || !subId.hasMatch(s))) {
      problems.add(where('subs'));
    }
    for (final k in ['product', 'model', 'company']) {
      final v = i[k];
      if (v is! String || v.trim().isEmpty || v.length > 1000) {
        problems.add(where(k));
      }
    }
    final date = i['date'];
    if (date is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) {
      problems.add(where('date'));
    }
    for (final k in ['companyKind', 'kind', 'defect', 'hazard', 'action']) {
      final v = i[k];
      if (v != null &&
          (v is! String || v.trim().isEmpty || v.length > recallMaxText)) {
        problems.add(where(k));
      }
    }
  }
  return problems;
}

Map<String, Object?>? _item(
  String id,
  Set<String> subs,
  String date,
  Map<String, Object?> row,
) {
  final product = _text(row['recallProductName']);
  final model = _text(row['recallModelName']);
  final company = _text(row['recallCmpnyName']) ?? _text(row['makerName']);
  if (product == null || model == null || company == null) return null;
  final defect = _text(row['harmDscr']);
  final texts = {
    'defect': defect,
    // 앱은 사유 칸에 제품 결함을, 없을 때만 위해 정보를 쓴다 — 결함이 있으면 위해
    // 정보는 싣지 않는다(앱이 날마다 받는 파일을 작게).
    'hazard': defect == null ? _text(row['accidentCaseDscr']) : null,
    'action': _text(row['publishActionDscr']) ?? _text(row['recallMeans']),
  };
  if (texts.values.any((t) => t != null && t.length > recallMaxText)) {
    return null;
  }
  return {
    'id': id,
    'subs': (subs.toList()..sort()),
    'product': product,
    'model': model,
    'company': company,
    'companyKind': ?_text(row['recallCmpnyDivName']),
    'kind': ?_text(row['recallTypeName']),
    'date': date,
    for (final e in texts.entries)
      if (e.value != null) e.key: e.value,
  };
}

/// 원문 글을 그대로 두되 모양만 고른다 — 줄바꿈 태그·`\r\n`은 줄바꿈으로, 줄
/// 앞뒤 빈칸·빈 줄은 뺀다. 비었거나 「-」·「없음」뿐이면 null.
String? _text(Object? raw) {
  if (raw is! String) return null;
  var s = raw
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');
  s = [
    for (final line in s.split('\n'))
      if (line.trim().isNotEmpty)
        line.replaceAll(RegExp(r'[ \t ]+'), ' ').trim(),
  ].join('\n');
  if (s.isEmpty || s == '-' || s == '없음') return null;
  return s;
}

/// `20251030` → `2025-10-30`. 모양이 다르거나 없는 날이면 null.
String? _day(Object? raw) {
  final s = raw is String ? raw.trim() : (raw is int ? '$raw' : '');
  final m = RegExp(r'^(\d{4})-?(\d{2})-?(\d{2})$').firstMatch(s);
  if (m == null) return null;
  final y = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  final d = int.parse(m.group(3)!);
  final date = DateTime(y, mo, d);
  if (y < 2000 || date.month != mo || date.day != d) return null;
  return '${m.group(1)}-${m.group(2)}-${m.group(3)}';
}
