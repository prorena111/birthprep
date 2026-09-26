// 정부24 공공서비스 목록에서 이 앱에 넣을 것을 고른다 — 나라(중앙부처·
// 공공기관)와 지자체(시·도, 시·군·구)의 임신·출산·육아 지원.
//
// 두 도구가 같이 쓴다.
//   · 바탕화면 exe → tool/make_local_supports.dart → 앱에 굽기
//   · 매달 1일 자동 작업 → tool/monthly/monthly.dart → GitHub Pages에 올리기
// **거르는 규칙은 여기만 고친다.** 둘이 다르게 거르면 앱에 든 목록과
// 내려받은 목록이 어긋난다.
//
// 이 파일은 dart:core만 쓴다 — 공개 저장소(prorena111/birthprep)의 tool/에
// 그대로 복사해 GitHub Actions에서 돌린다.

/// 시·도 이름(옛 이름 포함). 소관기관명이 이것으로 시작해야 지자체로 본다.
/// 앱의 `Region`·`placeOf`와 같은 목록이어야 한다 — 검사가 대조한다.
const sidoNames = [
  '서울특별시',
  '부산광역시',
  '대구광역시',
  '인천광역시',
  '광주광역시',
  '대전광역시',
  '울산광역시',
  '세종특별자치시',
  '경기도',
  '강원특별자치도',
  '강원도',
  '충청북도',
  '충청남도',
  '전북특별자치도',
  '전라북도',
  '전라남도',
  '전남광주통합특별시',
  '경상북도',
  '경상남도',
  '제주특별자치도',
];

/// 지자체 기관 이름인지 — 「서울특별시」 또는 「서울특별시 강남구」 꼴.
///
/// 「서울특별시강동구도시관리공단」·「충청남도천안의료원」·「○○교육청」처럼
/// 시·도 이름에 붙여 쓴 공단·의료원·교육청은 뺀다.
bool isLocalOrg(String org) =>
    sidoNames.any((s) => org == s || org.startsWith('$s '));

/// 나라 기관인지 — 중앙행정기관(○○부·○○처·○○청·○○위원회)과 나라
/// 공공기관(국민·국립·한국·대한·근로복지…로 시작).
///
/// 처음(2026-09-26)에는 「시·도 이름으로 시작하지 않으면 나라」로 봤더니
/// 「용산구시설관리공단」·「구리도시공사」·「재단법인목포인재육성재단」 같은 지역
/// 공단·재단이 나라 칸에 섞였다. 그래서 나라인 것만 이름 꼴로 고른다.
/// 「인천국제공항공사」처럼 도시 이름으로 시작하는 나라 공기업은 빠지지만,
/// 지역 것이 나라로 보이는 것보다 낫다. 교육(지원)청은 지역이다.
///
/// **앱의 `isNationOrg`(lib/data/catalog/local_supports.dart)와 같은 규칙이다** —
/// 검사가 대조한다.
bool isNationOrg(String org) {
  final t = org.trim();
  if (sidoNames.any(t.startsWith)) return false;
  if (t.endsWith('교육청') || t.endsWith('교육지원청')) return false;
  return nationOrgSuffixes.any(t.endsWith) ||
      nationOrgPrefixes.any(t.startsWith);
}

/// 중앙행정기관 이름 끝 — 보건복지부·인사혁신처·질병관리청·금융위원회.
const nationOrgSuffixes = ['부', '처', '청', '위원회'];

/// 나라 공공기관 이름 머리 — 국민건강보험공단·국립중앙의료원·한국전력공사·
/// 대한법률구조공단·근로복지공단.
const nationOrgPrefixes = ['국민', '국립', '한국', '대한', '근로복지'];

/// 나라 것이 임신·출산·육아 이야기인지 — **이름**으로만 본다.
///
/// 목적 요약까지 보면 「상병급여」·「체불임금 소송대리」·「공무원 응시수수료
/// 면제」처럼 요약에 임산부가 한 번 나오는 나라 서비스가 걸렸다(2026-09-26 첫
/// 실행). 나라 것은 제도 이름이 곧 무엇인지 말해 준다. 입양·선천성 검사·
/// 해산급여·모자보건·보육료도 이 앱 사람들이 받는 것이라 더한다.
bool isNationAboutBirth(String name) {
  if (_notBirthWords.any(name.contains)) return false;
  final n = _falseFriends(name);
  return _birthWords.any(n.contains) || _nationNameWords.any(n.contains);
}

/// 「보육」은 홀로는 넓다(「스마트팜 청년창업 보육센터」·「보육교직원 마음성장」) —
/// 부모가 받는 보육료·시간제보육만.
const _nationNameWords = ['입양', '선천성', '해산', '모자', '보육료', '시간제보육', '맘편한'];

/// 임신·출산·육아 이야기인지 — 서비스 이름과 목적 요약으로 본다.
///
/// 정부24의 「임산부·출산/입양」 표시는 안전보험·수도요금 감면·독거노인
/// 돌봄처럼 누구나 받는 서비스에도 붙어 있다. 지원대상 글도 「임산부,
/// 장애인, 국가유공자…」를 늘어놓는 감면이 많아 쓰지 않는다.
bool isAboutBirth(String name, String? summary) {
  // 「가정위탁 양육보조금」·「장수수당(1922년 이전 출생)」·「유기동물 입양」은
  // 낱말이 겹쳐도 이 앱 이야기가 아니다.
  if (_notBirthWords.any(name.contains)) return false;
  final text = _falseFriends('$name ${summary ?? ''}');
  return _birthWords.any(text.contains);
}

/// 낱말 속에 우연히 든 것을 걷는다 — 「아이디어」의 「아이」, 「체불임금」의
/// 「불임」(체불임금 소송 지원이 난임으로 걸렸다, 2026-09-26).
String _falseFriends(String text) =>
    text.replaceAll('아이디어', '').replaceAll('체불임금', '');

const _birthWords = [
  '임신', '임산부', '임부', '출산', '산모', '산후', '산전', '분만', '산부인과',
  '신생아', '영아', '영유아', '난임', '불임', '보조생식', '난자', '태아',
  '기형아', '풍진', '엽산', '모유', '수유', '유축', '아기', '아이', '육아',
  '다둥', '쌍둥', '다태아', '첫만남', '기저귀', '분유', '조리원', '예비부모',
  '예비부부', '엄마', '아빠', '생애초기', '북스타트', '다자녀', '가임',
  // 「출생」·「양육」·「입양」은 홀로는 넓다(어르신 장수수당, 가정위탁,
  // 유기동물 입양). 이 꼴일 때만.
  '출생아', '출생축하', '출생 축하', '출생기본소득', '출생장려', '출생신고',
  '출생·입양', '출생가정', '양육수당',
];

/// 이름에 이 낱말이 있으면 뺀다.
const _notBirthWords = ['위탁', '장수수당', '어르신', '노인', '반려', '동물'];

/// 사람(개인·가구)이 받는 것인지. 소상공인·법인·시설에 주는 지원은 뺀다.
/// 칸이 비어 있으면 넣는다 — 모르는 것을 버리지 않는다.
bool isForPeople(Object? userType) {
  if (userType is! String || userType.trim().isEmpty) return true;
  return userType.contains('개인') || userType.contains('가구');
}

/// 앱이 금액까지 크게 보여 주는 나라 제도 여덟 가지(`SupportPrograms`).
///
/// 「그 밖에 나라에서 주는 것」 목록에서는 뺀다 — 같은 제도가 두 번 나온다.
/// 매달 작업은 이 표로 정부24 글을 찾아 바뀌었는지 지켜본다
/// (`central_watch.dart`).
class CuratedProgram {
  const CuratedProgram(
    this.id, {
    required this.serviceIds,
    required this.names,
    this.watched = true,
  });

  /// 앱의 제도 번호(S01…).
  final String id;

  /// 정부24 서비스ID. 비어 있으면 [names]로 찾는다.
  final List<String> serviceIds;

  /// 서비스 이름에 들어 있는 말(띄어쓰기·가운뎃점은 무시하고 본다).
  final List<String> names;

  /// 정부24 글을 매달 지켜보는지. 정부24 공공서비스 목록에 나라 쪽 글이 없는
  /// 제도는 못 지켜본다 — 사람의 1년 대조(tool/support_update.md)로 챙긴다.
  /// 이름([names])은 그래도 「그 밖에」 목록에서 빼는 데 쓴다.
  final bool watched;

  /// 나라 기관의 이 서비스가 이 제도인지.
  bool matches(String serviceId, String name) {
    if (serviceIds.contains(serviceId)) return true;
    final n = squash(name);
    return names.any((w) => n.contains(squash(w)));
  }
}

/// 서비스ID는 2026-09-26 정부24 원문과 첫 자동 실행으로 확인했다.
/// **부모급여는 정부24 공공서비스 목록에 나라 쪽 글이 없다**(지역판 「충청북도
/// 보은군 부모급여 지원」 하나뿐) — 지켜보지 않는다. 도시가스는 첫 실행이 이름으로
/// 찾은 「사회적 배려대상자 도시가스요금 경감」(한국가스공사).
const curatedPrograms = [
  CuratedProgram('S01', serviceIds: ['SD0000007672'], names: ['임신·출산 진료비']),
  CuratedProgram('S02', serviceIds: ['135200005015'], names: ['첫만남이용권']),
  CuratedProgram('S03', serviceIds: [], names: ['부모급여'], watched: false),
  CuratedProgram('S04', serviceIds: ['135200000120'], names: ['아동수당']),
  CuratedProgram('S05', serviceIds: ['B41000200003'], names: ['전기 요금 복지할인']),
  CuratedProgram('S06', serviceIds: ['PTR000050390'], names: ['산모·신생아 건강관리']),
  CuratedProgram('S07', serviceIds: ['999000000008'], names: ['육아휴직급여']),
  CuratedProgram('S08', serviceIds: ['B55121000003'], names: ['도시가스']),
  // 2026-09-26 큰 제도에 올렸다(정부24 글에 한도가 없어 목록에선 금액이 안 보였다).
  CuratedProgram('S09', serviceIds: ['135200000114'], names: ['고위험 임산부 의료비']),
];

/// 띄어쓰기·가운뎃점을 걷은 이름 — 「임신ㆍ출산 진료비」와 「임신·출산진료비」를
/// 같은 것으로 본다.
String squash(String s) => s.replaceAll(RegExp(r'[\s·ㆍ・]'), '');

/// 고른 결과.
class Gov24Pick {
  Gov24Pick({
    required this.items,
    required this.perSido,
    required this.nation,
    required this.curated,
    required this.noUrl,
  });

  /// 앱 모양으로 추린 것 — 기관·이름 순.
  final List<Map<String, String>> items;

  /// 시·도별 지자체 지원 수.
  final Map<String, int> perSido;

  /// 나라 지원 수(큰 제도 여덟 가지는 빼고).
  final int nation;

  /// 큰 제도라서 뺀 나라 서비스 수.
  final int curated;

  /// 정부24 원문 주소가 없어 뺀 수.
  final int noUrl;
}

/// 정부24 서비스 목록에서 나라·지자체의 임신·출산·육아 지원을 추린다.
Gov24Pick pickSupports(List<Map<String, Object?>> services) {
  final items = <Map<String, String>>[];
  final perSido = <String, int>{};
  var nation = 0;
  var curated = 0;
  var noUrl = 0;
  for (final row in services) {
    final id = cleanText(row['서비스ID']);
    final org = cleanText(row['소관기관명']);
    final name = cleanText(row['서비스명']);
    if (id == null || org == null || name == null) continue;
    final local = isLocalOrg(org);
    if (!local && !isNationOrg(org)) continue;
    final field = cleanText(row['서비스분야']) ?? '';
    final summary = cleanText(row['서비스목적요약']);
    // 지자체는 이름·목적으로, 나라는 이름으로 본다([isNationAboutBirth]).
    final aboutBirth = local
        ? isAboutBirth(name, summary)
        : isNationAboutBirth(name);
    if (!aboutBirth && !field.contains('임신')) continue;
    if (!isForPeople(row['사용자구분'])) continue;
    if (!local && curatedPrograms.any((p) => p.matches(id, name))) {
      curated++;
      continue;
    }
    final url = govUrl(cleanText(row['상세조회URL']));
    if (url == null) {
      noUrl++;
      continue;
    }
    if (local) {
      final sido = sidoNames.firstWhere(
        (s) => org == s || org.startsWith('$s '),
      );
      perSido[sido] = (perSido[sido] ?? 0) + 1;
    } else {
      nation++;
    }
    items.add({
      'id': id,
      'org': org,
      'name': name,
      'url': url,
      ...?_field('summary', row['서비스목적요약']),
      ...?_field('target', row['지원대상']),
      ...?_field('criteria', row['선정기준']),
      ...?_field('content', row['지원내용']),
      ...?_field('how', row['신청방법']),
      ...?_field('deadline', row['신청기한']),
      ...?_field('phone', row['전화문의']),
    });
  }
  items.sort((a, b) {
    final byOrg = a['org']!.compareTo(b['org']!);
    return byOrg != 0 ? byOrg : a['name']!.compareTo(b['name']!);
  });
  return Gov24Pick(
    items: items,
    perSido: perSido,
    nation: nation,
    curated: curated,
    noUrl: noUrl,
  );
}

/// 앱에 굽거나 Pages에 올리는 파일 한 장. 키 차례가 곧 파일 차례다 —
/// 앱은 머리의 `checked`만 먼저 읽는다(`LocalSupportsStore.bundledChecked`).
Map<String, Object?> supportsFile({
  required List<Map<String, String>> items,
  required String checked,
}) => {
  'schema': 1,
  'source': '행정안전부 대한민국 공공서비스(혜택) 정보',
  'checked': checked,
  'count': items.length,
  'items': items,
};

/// 글 칸의 값 — 줄 끝을 맞추고 앞뒤 공백을 걷는다. 빈 칸은 null.
String? cleanText(Object? v) {
  if (v is! String) return null;
  final t = v.replaceAll('\r\n', '\n').trim();
  return t.isEmpty ? null : t;
}

/// 글 칸 하나. 빈 칸은 안 적는다. 세 줄 넘는 빈 줄은 한 줄로.
Map<String, String>? _field(String name, Object? v) {
  final t = cleanText(v)?.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return t == null ? null : {name: t};
}

/// 정부24 원문만. http는 https로 올린다.
String? govUrl(String? url) {
  if (url == null) return null;
  final u = url.replaceFirst(RegExp(r'^http://'), 'https://');
  return u.startsWith('https://www.gov.kr/') ? u : null;
}

/// 한국 시각의 오늘 — GitHub의 컴퓨터는 세계 표준시로 돈다. 매달 1일
/// 09시(한국)에 도는데 그때 세계 표준시는 1일 0시라 날짜는 같지만, 손으로
/// 밤늦게 돌리면 하루가 어긋난다.
DateTime koreaNow([DateTime? now]) =>
    (now ?? DateTime.now()).toUtc().add(const Duration(hours: 9));

/// 「2026-10-01」.
String dayOf(DateTime at) => '${at.year}-${_two(at.month)}-${_two(at.day)}';

/// 「2026-10」.
String monthOf(DateTime at) => '${at.year}-${_two(at.month)}';

String _two(int v) => v.toString().padLeft(2, '0');
