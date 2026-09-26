// 나라 제도 여덟 가지(앱이 금액까지 크게 보여 주는 것)의 정부24 글을
// 지켜본다.
//
// **금액을 글에서 뽑아 앱을 고치지 않는다.** 정부24 글은 사람이 쓴 문장이라
// 기계가 금액을 읽으면 틀리고, 틀린 금액은 스토어 심사(「혼동을 야기하는
// 주장」)로 이어진다. 대신
//   · 사람이 확인한 글(tool/central_watch.json의 services)과 **같으면**
//     v1/data.json의 그 제도 확인 시점을 이번 달로 올린다. 앱은 확인한 지
//     6개월이 지난 금액을 숨기는데(SupportPrograms.shelfLifeMonths), 매달
//     원문과 같은 것을 확인했으니 금액을 계속 보여 줄 수 있다.
//   · **다르면** 확인 시점을 올리지 않고 알린다(워크플로가 실패로 끝나
//     메일이 간다). 사람이 원문을 보고 앱·data.json을 고친 뒤 받아들인다
//     (`--accept S04`).
//
// 한계: 정부24가 늦게 고쳐지면(2026-09 아동수당 원문이 법 개정 전 「만 8세
// 미만」 그대로였다) 바뀐 것을 늦게 안다. 사람의 1년 대조
// (tool/support_update.md)는 그대로 한다.

import 'gov24_pick.dart';

/// 지켜보는 칸. 신청방법·전화는 자주 바뀌고 금액과 상관이 없어 뺀다.
const watchedFields = ['지원대상', '선정기준', '지원내용', '신청기한'];

/// 제도 하나의 이번 결과.
enum WatchStatus {
  /// 사람이 확인한 글과 같다 — 확인 시점을 올린다.
  same('같음'),

  /// 처음 보는 제도 — 지금 글을 기준으로 적는다. 확인 시점은 안 올린다.
  added('기준을 새로 적음'),

  /// 사람이 받아들였다 — 새 글을 기준으로 적고 확인 시점을 올린다.
  accepted('받아들임'),

  /// 글이 바뀌었다 — 사람이 볼 때까지 확인 시점을 안 올린다.
  changed('글이 바뀜'),

  /// 적어 둔 서비스가 정부24 목록에서 사라졌다.
  missing('정부24에서 사라짐'),

  /// 이름으로 찾았는데 하나도 없다.
  notFound('못 찾음'),

  /// 이름으로 찾았는데 여럿이다 — 사람이 번호를 골라 적는다.
  ambiguous('여럿이 걸림'),

  /// 정부24 목록에 나라 쪽 글이 없어 지켜보지 않는다(부모급여). 확인 시점은
  /// 사람의 1년 대조로만 오른다.
  skipped('지켜보지 않음');

  const WatchStatus(this.label);

  final String label;

  /// 사람이 볼 것인지.
  bool get needsHuman =>
      this == changed ||
      this == missing ||
      this == notFound ||
      this == ambiguous;
}

/// 사람에게 보여 줄 것 한 가지.
class WatchNote {
  WatchNote(this.program, this.status, this.lines);

  final String program;
  final WatchStatus status;

  /// 마크다운 줄.
  final List<String> lines;
}

class WatchReport {
  WatchReport({
    required this.status,
    required this.notes,
    required this.baseline,
  });

  /// 제도 → 결과.
  final Map<String, WatchStatus> status;

  final List<WatchNote> notes;

  /// 새로 쓸 central_watch.json.
  final Map<String, Object?> baseline;

  /// 확인 시점을 올릴 제도.
  List<String> get bump => [
    for (final e in status.entries)
      if (e.value == WatchStatus.same || e.value == WatchStatus.accepted) e.key,
  ];

  bool get needsHuman => status.values.any((s) => s.needsHuman);
}

/// 정부24 서비스 한 줄에서 지켜보는 것만 뽑는다.
Map<String, Object?> snapshotOf(Map<String, Object?> row) => {
  'name': cleanText(row['서비스명']),
  'org': cleanText(row['소관기관명']),
  'modified': ?cleanText(row['수정일시']),
  'text': {for (final f in watchedFields) f: _normalize(row[f])},
};

/// 줄바꿈·겹친 공백만 다른 것은 같은 글로 본다.
String _normalize(Object? v) =>
    (cleanText(v) ?? '').replaceAll(RegExp(r'\s+'), ' ');

bool _sameText(Object? a, Object? b) {
  if (a is! Map || b is! Map) return false;
  for (final f in watchedFields) {
    if ('${a[f] ?? ''}' != '${b[f] ?? ''}') return false;
  }
  return true;
}

/// 이번 달 결과를 낸다.
///
/// [baseline]은 central_watch.json(없으면 빈 것), [services]는 정부24
/// serviceList 전체, [accept]는 사람이 받아들인 제도(`all`이면 전부).
/// [programs]는 검사에서만 바꾼다.
WatchReport watchCentral({
  required Map<String, Object?> baseline,
  required List<Map<String, Object?>> services,
  Set<String> accept = const {},
  List<CuratedProgram> programs = curatedPrograms,
}) {
  final byId = <String, Map<String, Object?>>{
    for (final row in services) ?cleanText(row['서비스ID']): row,
  };
  final oldPrograms = baseline['programs'] is Map
      ? (baseline['programs'] as Map).cast<String, Object?>()
      : <String, Object?>{};
  final nextPrograms = <String, Object?>{};
  final status = <String, WatchStatus>{};
  final notes = <WatchNote>[];

  for (final p in programs) {
    final old = oldPrograms[p.id] is Map
        ? (oldPrograms[p.id] as Map).cast<String, Object?>()
        : <String, Object?>{};
    final known = old['services'] is Map
        ? (old['services'] as Map).cast<String, Object?>()
        : <String, Object?>{};
    final pending = old['pending'] is Map
        ? (old['pending'] as Map).cast<String, Object?>()
        : <String, Object?>{};
    final accepting = accept.contains('all') || accept.contains(p.id);

    if (!p.watched) {
      status[p.id] = WatchStatus.skipped;
      continue;
    }

    // 지켜볼 서비스 번호 — 적어 둔 것 → 코드에 적은 것 → 이름으로 찾기.
    var ids = known.keys.toList();
    if (ids.isEmpty) ids = [...p.serviceIds];
    if (ids.isEmpty) {
      final found = [
        for (final row in services)
          if (cleanText(row['서비스ID']) case final id?)
            if (cleanText(row['소관기관명']) case final org?)
              if (isNationOrg(org) &&
                  p.matches(id, cleanText(row['서비스명']) ?? ''))
                row,
      ];
      if (found.length != 1) {
        status[p.id] = found.isEmpty
            ? WatchStatus.notFound
            : WatchStatus.ambiguous;
        notes.add(
          WatchNote(p.id, status[p.id]!, [
            '이름 ${p.names.join('·')}로 찾았습니다 — ${found.length}개.',
            for (final row in found.take(10))
              '- `${row['서비스ID']}` ${row['서비스명']} (${row['소관기관명']}) '
                  '${_url('${row['서비스ID']}')}',
            '맞는 번호를 `gov24_pick.dart`의 `curatedPrograms`에 적어 주세요.',
          ]),
        );
        nextPrograms[p.id] = old;
        continue;
      }
      ids = ['${found.single['서비스ID']}'];
    }

    final nextKnown = <String, Object?>{};
    final nextPending = <String, Object?>{};
    var result = WatchStatus.same;
    final lines = <String>[];

    for (final id in ids) {
      final row = byId[id];
      if (row == null) {
        result = WatchStatus.missing;
        if (known[id] != null) nextKnown[id] = known[id];
        lines.add('- `$id` — 정부24 목록에 없습니다 ${_url(id)}');
        continue;
      }
      final snap = snapshotOf(row);
      final before = known[id];
      if (before is! Map) {
        nextKnown[id] = snap;
        if (result == WatchStatus.same) result = WatchStatus.added;
        continue;
      }
      if (_sameText(before['text'], snap['text'])) {
        nextKnown[id] = snap; // 수정일시만 바뀐 것도 새로 적는다
        continue;
      }
      if (accepting) {
        nextKnown[id] = snap;
        if (result == WatchStatus.same) result = WatchStatus.accepted;
        continue;
      }
      nextKnown[id] = before;
      nextPending[id] = snap;
      if (result != WatchStatus.missing) result = WatchStatus.changed;
      lines.addAll(_diff(id, before, snap));
    }

    // 옛 대기(pending)는 따로 옮기지 않는다 — 아직 다르면 위에서 다시
    // 대기가 되고, 정부24가 되돌렸으면 같음이 되어 사라진다. 받아들이지
    // 않는 한 매달 다시 알린다.
    if (pending.isNotEmpty && result == WatchStatus.same && !accepting) {
      lines.add('정부24 글이 사람이 확인한 글로 돌아왔습니다.');
    }

    status[p.id] = result;
    if (result.needsHuman || result == WatchStatus.added) {
      notes.add(WatchNote(p.id, result, lines));
    }
    nextPrograms[p.id] = {
      'services': nextKnown,
      if (nextPending.isNotEmpty) 'pending': nextPending,
    };
  }

  return WatchReport(
    status: status,
    notes: notes,
    baseline: {
      'schema': 1,
      'about':
          '정부24에서 나라 제도 여덟 가지의 글을 지켜본다. services는 사람이 확인한 '
          '글이고, pending은 그 뒤 바뀐 글(사람이 볼 때까지 확인 시점을 안 올린다).',
      'programs': nextPrograms,
    },
  );
}

/// 바뀐 칸마다 전·후.
List<String> _diff(
  String id,
  Map<dynamic, dynamic> before,
  Map<String, Object?> after,
) {
  final a = before['text'] as Map? ?? const {};
  final b = after['text'] as Map? ?? const {};
  return [
    '- `$id` ${after['name']} — ${_url(id)}'
        '${after['modified'] != null ? ' (정부24 수정 ${after['modified']})' : ''}',
    for (final f in watchedFields)
      if ('${a[f] ?? ''}' != '${b[f] ?? ''}') ...[
        '  - **$f**',
        '    - 전: ${a[f] ?? '(없음)'}',
        '    - 후: ${b[f] ?? '(없음)'}',
      ],
  ];
}

String _url(String id) => 'https://www.gov.kr/portal/rcvfvrSvc/dtlEx/$id';

/// v1/data.json의 확인 시점을 올린다. 적어 둔 것보다 새 달일 때만.
/// 돌려주는 값은 실제로 올린 제도.
List<String> bumpChecked(
  Map<String, Object?> data,
  List<String> programs,
  String month,
) {
  if (programs.isEmpty) return const [];
  final support = (data['support'] ??= <String, Object?>{}) as Map;
  final all = (support['programs'] ??= <String, Object?>{}) as Map;
  final bumped = <String>[];
  for (final id in programs) {
    final entry = (all[id] ??= <String, Object?>{}) as Map;
    final before = entry['checked'];
    if (before is String && before.compareTo(month) >= 0) continue;
    entry['checked'] = month;
    bumped.add(id);
  }
  return bumped;
}
