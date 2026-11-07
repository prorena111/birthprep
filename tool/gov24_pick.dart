// 정부24 공공서비스 목록에서 이 앱에 넣을 것을 고른다 — 나라(중앙부처·
// 공공기관)와 지자체(시·도, 시·군·구)의 임신·출산·육아 지원.
//
// 두 도구가 같이 쓴다.
//   · 바탕화면 exe → tool/make_local_supports.dart → 앱에 굽기
//   · 매달 1일 자동 작업 → tool/monthly/monthly.dart → GitHub Pages에 올리기
// **거르는 규칙은 여기만 고친다.** 둘이 다르게 거르면 앱에 든 목록과
// 내려받은 목록이 어긋난다.
//
// 이 파일은 dart 기본 라이브러리만 쓴다 — 공개 저장소(prorena111/birthprep)의
// tool/에 그대로 복사해 GitHub Actions에서 돌린다.

import 'dart:convert';

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
  if (hasNotBirthWord(name)) return false;
  if (isOffTopic(name, null)) return false;
  final n = _falseFriends(name);
  return _birthWords.any(n.contains) ||
      _nationNameWords.any(n.contains) ||
      _childNameWords.any(n.contains);
}

/// **이름에** 있으면 아이 키우는 집이 받는 것 — 이름으로만 본다(목적 요약에는
/// 「아동」이 「노인·장애인·아동」처럼 늘 섞여 나온다).
///
/// 사장님 2026-09-27 「사소한 것들이라도 빠지는 게 있어서는 안 돼. 나라, 도
/// 단위, 시 단위 등」. 점검(probe)으로 정부24 원본을 뒤져 보니 「미혼모부 양육비
/// 지원」·「장애인가정 양육지원금」·「서울시 어린이 눈건강 지킴이」·「아동치과
/// 치료지원」·「어린이 불소 도포」·「꿈나래통장」이 「임신·출산 낱말이 없다」로
/// 빠지고 있었다.
const _childNameWords = [
  '아동',
  '어린이',
  '한부모',
  '미혼모',
  '미혼부',
  '양육비',
  '양육지원',
  '장애아',
  '발달재활',
  '언어발달',
  '육아휴직',
  '육아기',
  '배우자출산',
  '배우자 출산',
  '꿈나래',
  '다함께',
  '키즈',
  '유아',
  // 2026-09-27 밤 원본 전체(10,941건)를 뒤져 더 찾은 것 — 다자녀 진료비·가족사진,
  // 손주 돌봄 수당, 입양 축하금, 부모부담 보육료.
  '세 자녀',
  '세자녀',
  '두 자녀',
  '두자녀',
  '자녀 이상',
  '손주돌봄',
  '손자녀',
  '입양축하',
  '입양 축하',
  '입양장려',
  '입양가정',
  '보육료',
  // 해산급여·해산비(수급자 출산) — 기초생활보장 요약에 「해산급여」가 나열돼
  // 있어 이름에서만 본다.
  '해산',
];

/// 「보육」은 홀로는 넓다(「스마트팜 청년창업 보육센터」·「보육교직원 마음성장」) —
/// 부모가 받는 보육료·시간제보육만.
///
/// 돌봄·대여(2026-09-27 사장님 「돈 외적인 지원 서비스까지 다」): 아이돌봄·
/// 다함께돌봄·지역아동센터·늘봄(정부24 「온종일 돌봄」 묶음), 장난감 대여,
/// 육아종합지원센터, 어린이집·유치원 학비.
const _nationNameWords = [
  '입양',
  '선천성',
  '해산',
  '모자',
  '보육료',
  '시간제보육',
  '맘편한',
  ..._careWords,
];

/// 돈이 아닌 육아 지원 — 돌봄·대여·보육. 「돌봄」 홀로는 노인·장애인 돌봄도
/// 걸려서 아이 돌봄인 꼴만.
const _careWords = [
  '아이돌봄',
  '아동돌봄',
  '초등돌봄',
  '다함께돌봄',
  '돌봄교실',
  '늘봄',
  '지역아동센터',
  '장난감',
  '육아종합지원',
  '공동육아',
  '어린이집',
  '유치원',
  '유아학비',
  '누리과정',
  '가정양육',
  '영유아',
];

/// 임신·출산·육아 이야기인지 — 서비스 이름과 목적 요약으로 본다.
///
/// 정부24의 「임산부·출산/입양」 표시는 안전보험·수도요금 감면·독거노인
/// 돌봄처럼 누구나 받는 서비스에도 붙어 있다. 지원대상 글도 「임산부,
/// 장애인, 국가유공자…」를 늘어놓는 감면이 많아 쓰지 않는다.
bool isAboutBirth(String name, String? summary) {
  // 「가정위탁 양육보조금」·「장수수당(1922년 이전 출생)」·「유기동물 입양」은
  // 낱말이 겹쳐도 이 앱 이야기가 아니다.
  if (hasNotBirthWord(name)) return false;
  if (isOffTopic(name, summary)) return false;
  final text = _falseFriends('$name ${summary ?? ''}');
  return _birthWords.any(text.contains) ||
      _childNameWords.any(_falseFriends(name).contains) ||
      isSchoolEntry(name);
}

/// 초등학교에 들어갈 때 주는 돈 — 「초등학교 입학축하금」·「초·중·고 입학준비금」.
/// 만 6세 아이가 받는다(이 앱은 만 6세까지). 중·고·대학만 주는 것은 뺀다.
bool isSchoolEntry(String name) {
  final n = squash(name).replaceAll(RegExp(r'[,·ㆍ]'), '');
  if (!n.contains('입학')) return false;
  // 「전입학생 지원」은 전학 온 학생에게 주는 것이다.
  if (n.contains('대학') || n.contains('전입학')) return false;
  return n.contains('초등') || n.contains('초중');
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
  // 2026-09-27 밤 원본 전체에서 — 미숙아 RSV 접종비, 0세아 의료비, 정관·난관
  // 복원 시술비(임신 준비), 생후 36개월 이하 자녀 가정 요금 감면, 맘편한 택시.
  '미숙아', '0세아', '정관', '난관 복원', '난관복원', '생후', '맘편한',
  // 「예비·신혼부부 건강검진」.
  '예비 신혼', '예비,신혼', '예비신혼',
  ..._careWords,
];

/// 이름에 이 낱말이 있으면 뺀다.
///
/// 돌봄·보육 낱말을 더하며(2026-09-27) 어린이집·유치원 **일하는 사람**에게
/// 주는 것(교원 처우개선·보육교직원 수당·종사자 교육)을 같이 뺀다.
const _notBirthWords = [
  '위탁',
  '장수수당',
  '어르신',
  '노인',
  '반려',
  '동물',
  '교원',
  '교직원',
  '종사자',
  '보육교사',
  '운영비',
  '인건비',
  // 아이돌보미(일하는 사람)의 건강검진비, 치매 환자 물품, 기관 대상 환경
  // 교육 — 2026-09-27 돌봄 칸을 만들며 드러났다.
  '아이돌보미 건강',
  '치매',
  '환경교육',
  // 아이 키우는 집이 아니라 보호가 필요한 아동·시설·학대 대응.
  '보호대상아동',
  '아동보호',
  '학대',
  '자립준비',
  '아동양육시설',
  '그룹홈',
  '아동복지시설',
  '시설아동',
  '보호아동',
  '요보호',
  '가출',
  '실종',
  '성매매',
  '아동안전지킴이',
  // 사람이 아니라 시설·약국·공무원에게 주는 것, 어른 것 — 2026-09-27 복지로
  // 목록을 붙이며 드러났다(복지로에는 정부24의 「사용자구분」 칸이 없다).
  '공무원',
  '협력약국',
  '교재교구',
  '성인용',
  '급식도우미',
  '안내책자',
  '센터 냉난방',
  '센터냉난방',
  // 2026-10-31 점검 — 만 18세 보호종료 아동 자립정착금(최대 1,500만원)이 「많이
  // 받는 것」 위쪽에 섰고, 학교 다니는 아이 급식·어린이날 행사 예산·어린이병원
  // 운영비(4,200만원)가 지원금처럼 보였다. 한부모가족복지시설 퇴소자 자립금은
  // 아기 키우는 한부모 것이라 남긴다.
  '보호종료',
  '보호종결',
  '퇴소아동',
  '소년소녀가정',
  '결식',
  '아동급식',
  '노숙인',
  '행사',
  '달빛어린이병원',
  '심야어린이병원',
];

/// 이름에 빼는 낱말([_notBirthWords])이 있거나 중·고등학생만 받는 것인지 —
/// 복지로·서울 고르기도 같이 쓴다.
bool hasNotBirthWord(String name) =>
    _notBirthWords.any(name.contains) || isOlderSchoolOnly(name);

/// 중·고등학생만 받는 것 — 「고등학교 입학축하금」·「중학생 입학준비금」·
/// 「고교생 수업료」. 이 앱은 만 6세까지라 초등학교가 같이 든 것(「초·중·고
/// 입학축하금」)만 남긴다([isSchoolEntry]).
bool isOlderSchoolOnly(String name) {
  final n = squash(name);
  if (n.contains('초')) return false;
  return n.contains('중학') || n.contains('고등') || n.contains('고교');
}

/// 가축·농사와 대학 학비 — 낱말이 겹쳐도 이 앱(임신부터 만 6세까지) 이야기가
/// 아니다. 이름이나 목적에 있으면 뺀다.
///
/// 2026-09-27 점검에서 「한우 조기 임신 진단」·「가축살처분(임신 감정비)」·
/// 「칡소 다산장려금(송아지 출산)」·「볍씨발아기」(「발아기」 속 「아기」)와
/// 다자녀 대학 장학금(나라 칸 둘째 줄에 「최대 610만원」)이 목록에 있었다.
/// 「장학」 홀로는 「현장학습비」에 걸려 쓰지 않는다.
bool isOffTopic(String name, String? summary) {
  final text = '$name ${summary ?? ''}';
  return _offTopicWords.any(text.contains);
}

const _offTopicWords = [
  '한우',
  '가축',
  '양돈',
  '칡소',
  '번식우',
  '송아지',
  '사육농가',
  '사육 농가',
  '볍씨',
  '장학금',
  '장학생',
  '장학재단',
  '장학회',
  '등록금',
  '학자금',
  '대학생',
];

/// 지자체가 나라 제도를 제 이름으로 올린 것 — 「첫만남이용권」·「부모급여 지원」·
/// 「고위험 임산부 의료비 지원」. 앱의 나라 카드와 같은 돈이라 「우리 구가 따로
/// 주는 것」에 또 보이면 두 번 받는 것처럼 읽힌다(2026-09-27 점검).
///
/// 이름이 곧 제도 이름일 때만 뺀다 — 「첫만남이용권 추가 지원」처럼 덧붙인 말이
/// 있으면 지자체가 더 주는 것이라 남긴다. 산모·신생아 건강관리는 지자체 것이
/// 대부분 본인부담금 추가 지원이라 여기 넣지 않는다.
/// 끝난 사업 — 앱 항목 id(정부24는 서비스ID, 복지로는 `bokjiro:…`, 서울은
/// `seoul:…`)와 끝난 날. 원문 글이 늦게 내려가도 이 날부터 뺀다.
/// 앱도 같은 표를 갖는다(`LocalSupportBook.ended`) — 둘을 같이 고친다.
///
/// 신청기한 칸에 「신청마감」처럼 끝났다고 적힌 것은 표 없이 뺀다
/// ([isClosedNotice]) — 내년에 글이 다시 열리면 저절로 돌아온다. 이 표는 글에
/// 끝났다는 말이 없는데 끝난 것만.
const endedServices = <String, String>{
  // 경기도 산후조리비 — 2026-10-01 종료(9월 30일 신청 건까지), 시·군 누리집 7곳 확인.
  '641000000137': '2026-10-01',
  // 같은 사업의 복지로 글 — 정부24 것만 막아 10월에도 「꼭 신청 · 50만원」으로
  // 떠 있었다(2026-10-31 점검).
  'bokjiro:WLF00001361': '2026-10-01',
  // 서울 육아 지원 코디네이터 — 몽땅정보통 글에 「2023년에 종료」(찾은 날 2026-11-01부터 뺀다).
  'seoul:d90a8d782fe1': '2026-11-01',
};

bool isEndedService(String id, [DateTime? now]) {
  final day = endedServices[id];
  return day != null && !(now ?? DateTime.now()).isBefore(DateTime.parse(day));
}

/// 신청기한 칸이 끝났다는 말 하나뿐인지 — 「신청마감」·「2025년 대상자 모집
/// 마감」·「2017년 이후 출생아 신규가입 불가」. 「매해 상반기(2월~6월)
/// 신청접수 마감」처럼 다시 열리는 때를 적은 것은 아니다.
bool isClosedNotice(String? deadline) {
  final d = (deadline ?? '').replaceAll(RegExp(r'\s+'), '');
  if (d.isEmpty) return false;
  if (d.contains('신규가입불가')) return true;
  return RegExp(
    r'^(\d{4}년)?(대상자)?(모집|신청|접수)(이)?(마감|종료)(됨|되었습니다)?\.?$',
  ).hasMatch(d);
}

/// 이름 맨 앞의 사업 연도가 두 해 넘게 지났는지 — 「2024년 난자 동결 시술비
/// 지원사업」은 2026년에 뺀다. 지난해 것(「2025년 어린이집 교재비」)은 이름만
/// 안 고친 채 계속하는 일이 많아 남긴다(사장님 「빠지는 게 있어서는 안 돼」).
/// 「2024년 이후 출생아 …」·「2024년 1월부터 …」처럼 대상을 가르는 연도는 아니다.
bool isPastYearName(String name, [DateTime? now]) {
  final m = RegExp(
    r'^\s*[\[(〔]?\s*(20\d\d)(\s*년|\s*[\])〕]|\s)\s*',
  ).firstMatch(name);
  if (m == null) return false;
  final rest = name.substring(m.end);
  if (RegExp(r'^(\d+\s*월|이후|이전|출생|생|부터|~|[.\-])').hasMatch(rest)) {
    return false;
  }
  return int.parse(m[1]!) <= (now ?? DateTime.now()).year - 2;
}

/// 목록에서 뺄 끝난 지역 사업인지 — 표([endedServices])·신청기한 칸·이름 연도.
/// 정부24·복지로·서울 것 모두 이것으로 본다.
bool isStaleLocal(Map<String, String> item, [DateTime? now]) =>
    isEndedService(item['id'] ?? '', now) ||
    isClosedNotice(item['deadline']) ||
    isPastYearName(item['name'] ?? '', now);

bool isCuratedCopy(String name) {
  // 임산부 친환경농산물 꾸러미는 농식품부 사업을 지자체가 운영한다 — 이름이
  // 제각각이라(「경기임산부 친환경농산물 지원」·「임산부 친환경농산물 꾸러미
  // 지원」) 낱말로 본다. 앱의 나라 카드(S10)와 같은 것이다(2026-09-28).
  final s = squash(name);
  if (s.contains('친환경농산물') && (s.contains('임산부') || s.contains('임신부'))) {
    return true;
  }
  final n = squash(name)
      .replaceAll(RegExp(r'[\(\[][^\)\]]*[\)\]]'), '')
      .replaceAll(RegExp(r'(지원|사업|신청)+$'), '');
  return _copyNames.contains(n);
}

const _copyNames = {'임신출산진료비', '첫만남이용권', '부모급여', '아동수당', '고위험임산부의료비'};

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
  // 2026-09-28 — 정부24에 나라 쪽 글이 없어 지켜보지 않는다(사람이 1년에 한 번).
  // 영유아 건강검진은 이름으로 빼지 않는다 — 「의료급여수급권자 영유아건강검진비」는
  // 다른 사업이다.
  CuratedProgram('S10', serviceIds: [], names: ['임산부 친환경농산물'], watched: false),
  CuratedProgram('S11', serviceIds: [], names: [], watched: false),
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
    this.closed = const [],
  });

  /// 앱 모양으로 추린 것 — 기관·이름 순.
  final List<Map<String, String>> items;

  /// 끝나서 뺀 것(끝난 사업 표·신청기한 「마감」) — 기관·이름만. 복지로에 같은
  /// 사업이 따로 올라와 있으면 그것도 빼려고 넘긴다(경기도 산후조리비가 그랬다).
  /// 신청기한 글이 다시 열리면 둘 다 저절로 돌아온다.
  final List<Map<String, String>> closed;

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
  final closed = <Map<String, String>>[];
  final perSido = <String, int>{};
  final seen = <String>{};
  var nation = 0;
  var curated = 0;
  var noUrl = 0;
  for (final row in services) {
    final id = cleanText(row['서비스ID']);
    final org = cleanText(row['소관기관명']);
    final name = cleanText(row['서비스명']);
    if (id == null || org == null || name == null) continue;
    // 쪽을 받는 사이에 목록이 바뀌면 같은 서비스가 두 번 올 수 있다.
    if (!seen.add(id)) continue;
    final local = isLocalOrg(org);
    if (!local && !isNationOrg(org)) continue;
    final field = cleanText(row['서비스분야']) ?? '';
    final summary = cleanText(row['서비스목적요약']);
    // 분야가 「임신·출산」이어도 가축·학비·보호종료 아동 이야기는 뺀다.
    if (isOffTopic(name, local ? summary : null)) continue;
    if (hasNotBirthWord(name)) continue;
    // 지자체는 이름·목적으로, 나라는 이름으로 본다([isNationAboutBirth]).
    final aboutBirth = local
        ? isAboutBirth(name, summary)
        : isNationAboutBirth(name);
    if (!aboutBirth && !field.contains('임신')) continue;
    if (!isForPeople(row['사용자구분'])) continue;
    final deadline = cleanText(row['신청기한']);
    if (isEndedService(id) || isClosedNotice(deadline)) {
      closed.add({'org': org, 'name': name});
      continue;
    }
    // 이름 연도로 뺀 것은 복지로 짝까지 빼지 않는다 — 올해 것을 복지로에만
    // 새 이름으로 올렸을 수 있다.
    if (isPastYearName(name)) continue;
    if (local
        ? isCuratedCopy(name)
        : curatedPrograms.any((p) => p.matches(id, name))) {
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
      // 「현금」·「현물」·「서비스(의료)」·「이용권」… 앱이 이것으로 지원금과
      // 돌봄·서비스를 가른다(없으면 이름·금액으로 가른다).
      ...?_field('type', row['지원유형']),
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
    closed: closed,
  );
}

/// 앱에 굽거나 Pages에 올리는 파일 한 장. 키 차례가 곧 파일 차례다 —
/// 앱은 머리의 `checked`만 먼저 읽는다(`LocalSupportsStore.bundledChecked`).
///
/// `rev`는 목록 내용의 지문이다. 같은 날 다시 받아 내용이 바뀌어도 날짜는
/// 같아서, 앱이 날짜만 보면 새 목록을 안 받는다(2026-09-26 하루에 다섯 번
/// 올렸다). 앱은 날짜가 같으면 지문을 견준다.
Map<String, Object?> supportsFile({
  required List<Map<String, String>> items,
  required String checked,
}) => {
  'schema': 1,
  'source': '행정안전부 대한민국 공공서비스(혜택) 정보',
  'checked': checked,
  'rev': contentRev(items),
  'count': items.length,
  'items': items,
};

/// 목록 내용의 지문 — FNV-1a 64비트, 16자리 16진수. 암호용이 아니라 「바뀌었나」만
/// 가린다. 같은 목록이면 늘 같은 값이다(키 차례까지 같게 쓰므로).
String contentRev(List<Map<String, String>> items) {
  // 0xcbf29ce484222325를 부호 있는 64비트로 적은 것(VM의 int는 64비트에서 돈다).
  var h = -3750763034362895579;
  for (final b in utf8.encode(jsonEncode(items))) {
    h ^= b;
    h *= 1099511628211; // 0x100000001b3
  }
  String half(int v) => (v & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
  return '${half(h >> 32)}${half(h)}';
}

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
///
/// 2026-11부터 목록의 상세조회URL이 모두 `plus.gov.kr/…?svcId=번호`로 왔다(그달
/// 정부24 항목이 통째로 빠져 안전장치가 막았다). 앱의 출처 목록과 스토어 설명은
/// `www.gov.kr`이고 이미 나간 앱은 그 주소만 받으니, 서비스 번호로 옛 주소를
/// 만든다. 표본 40곳이 그 주소로 열리는 것을 확인했다.
String? govUrl(String? url) {
  if (url == null) return null;
  final u = url.replaceFirst(RegExp(r'^http://'), 'https://');
  if (u.startsWith('https://www.gov.kr/')) return u;
  if (!u.startsWith('https://plus.gov.kr/')) return null;
  final id = Uri.tryParse(u)?.queryParameters['svcId'];
  if (id == null || id.isEmpty) return null;
  return 'https://www.gov.kr/portal/rcvfvrSvc/dtlEx/$id';
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

/// 한 서비스가 왜 목록에 들었는지·빠졌는지 — 점검용(Run workflow의 `probe`).
///
/// 사장님 2026-09-27 「마포구만 해도 주는 게 이렇게 많은데 왜 하나도 안
/// 나와」 — 정부24에 없는 것인지 우리가 거른 것인지 가리려고 만들었다.
/// [pickSupports]와 같은 차례로 본다(둘을 같이 고친다).
String explainPick(Map<String, Object?> row) {
  final id = cleanText(row['서비스ID']);
  final org = cleanText(row['소관기관명']);
  final name = cleanText(row['서비스명']);
  if (id == null || org == null || name == null) return '빠짐: 칸이 비었다';
  final local = isLocalOrg(org);
  if (!local && !isNationOrg(org)) return '빠짐: 지자체·나라 기관 이름 꼴이 아니다';
  final field = cleanText(row['서비스분야']) ?? '';
  final summary = cleanText(row['서비스목적요약']);
  if (isOffTopic(name, local ? summary : null)) return '빠짐: 가축·농사·학비';
  if (hasNotBirthWord(name)) return '빠짐: 빼는 낱말(보호종료·급식·중고교 등)';
  final aboutBirth = local
      ? isAboutBirth(name, summary)
      : isNationAboutBirth(name);
  if (!aboutBirth && !field.contains('임신')) {
    return '빠짐: 임신·출산·육아 낱말이 없다(분야 $field)';
  }
  if (!isForPeople(row['사용자구분'])) {
    return '빠짐: 사람이 받는 것이 아니다(${row['사용자구분']})';
  }
  if (isEndedService(id)) return '빠짐: 끝난 사업(endedServices)';
  if (isClosedNotice(cleanText(row['신청기한']))) return '빠짐: 신청기한 칸이 「마감」';
  if (isPastYearName(name)) return '빠짐: 이름의 사업 연도가 두 해 넘게 지났다';
  if (local
      ? isCuratedCopy(name)
      : curatedPrograms.any((p) => p.matches(id, name))) {
    return '빠짐: 앱의 큰 제도와 같은 것';
  }
  if (govUrl(cleanText(row['상세조회URL'])) == null) return '빠짐: 정부24 원문 주소가 아니다';
  return '들어감';
}

/// [needle]이 기관 이름이나 서비스 이름에 든 서비스를 모두 — 마크다운 표.
///
/// 「=서울특별시」처럼 `=`로 시작하면 기관 이름이 꼭 그것인 것만(시·도 본청).
List<String> probeReport(List<Map<String, Object?>> services, String needle) {
  final exact = needle.startsWith('=');
  final word = exact ? needle.substring(1) : needle;
  final rows = [
    for (final r in services)
      if (exact
          ? cleanText(r['소관기관명']) == word
          : (cleanText(r['소관기관명']) ?? '').contains(word) ||
                (cleanText(r['서비스명']) ?? '').contains(word))
        r,
  ];
  return [
    '',
    '### 점검: 「$needle」 ${rows.length}건',
    '',
    '| 기관 | 서비스 | 분야 | 지원유형 | 결과 |',
    '|---|---|---|---|---|',
    for (final r in rows)
      '| ${cleanText(r['소관기관명'])} | ${cleanText(r['서비스명'])} | '
          '${cleanText(r['서비스분야']) ?? ''} | ${cleanText(r['지원유형']) ?? ''} | '
          '${explainPick(r)} |',
  ];
}
