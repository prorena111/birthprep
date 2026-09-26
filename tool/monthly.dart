// 매달 1일 자동 작업 — 공개 저장소 prorena111/birthprep에서 GitHub Actions가
// 돌린다(.github/workflows/monthly.yml). 사람이 누를 것이 없다.
//
// **원본은 앱 저장소의 tool/monthly/이다.** 고치면 저 저장소의 tool/에 그대로
// 복사해 올린다(docs/remote_data.md 「매달 1일 자동 갱신」). 검사는 앱 저장소의
// test/monthly_test.dart.
//
// 하는 일 셋:
//   1) 정부24에서 나라·지자체의 임신·출산·육아 지원을 받아 v1/local.json을
//      새로 쓴다. 앱은 하루 한 번 v1/data.json을 보다가 `local.checked`가
//      자기 것보다 새로우면 이 파일을 내려받는다(LocalSupportsStore).
//   2) 나라 제도 여덟 가지의 정부24 글이 사람이 확인한 글과 같은지 본다
//      (central_watch.dart). 같으면 data.json의 확인 시점을 이번 달로 올리고,
//      다르면 tool/central_changes.md에 전·후를 적고 알린다.
//   3) tool/coupang_urls.tsv에 있는데 파트너스 링크가 없는 품목을 바꿔
//      data.json의 coupang에 넣는다(한 번 만든 링크는 기한이 없다).
//
// 사람이 볼 것이 있으면 GITHUB_OUTPUT에 attention=true를 적는다 — 워크플로가
// 파일을 올린 뒤 실패로 끝나 저장소 주인에게 메일이 간다.
//
// 키는 환경변수로만: DATA_GO_KR_KEY, COUPANG_ACCESS_KEY, COUPANG_SECRET_KEY
// (GitHub 저장소 Settings → Secrets에 사장님이 넣는다. Claude는 키를 다루지
// 않는다).
//
// 손으로 돌릴 때(키 없이 되는 것):
//   dart tool/monthly/monthly.dart --root <birthprep 폴더> --only-coupang
//   dart tool/monthly/monthly.dart --root <birthprep 폴더> --accept-pending S04
//     바뀐 글을 확인하고 앱·data.json을 고쳤으면 그 글을 새 기준으로 받아들인다.
//   dart tool/monthly/monthly.dart --root <birthprep 폴더> --merge build/remote_data.json
//     앱에서 새로 뽑은 data.json을 올릴 때 — 자동 작업이 올린 확인 시점·
//     지원 목록 날짜·쿠팡 링크를 지키며 합친다.
//
// **`dart run`이 아니라 `dart`다**(CLAUDE.md).

import 'dart:convert';
import 'dart:io';

import 'central_watch.dart';
import 'coupang_api.dart';
import 'gov24_client.dart';
import 'gov24_pick.dart';

/// 파일 자리(저장소 뿌리 기준).
const dataPath = 'v1/data.json';
const supportsPath = 'v1/local.json';
const statusPath = 'v1/status.json';
const watchPath = 'tool/central_watch.json';
const changesPath = 'tool/central_changes.md';
const coupangUrlsPath = 'tool/coupang_urls.tsv';

/// 지원 목록이 지난달의 이만큼보다 적으면 올리지 않는다 — 정부24 쪽 사고로
/// 반쯤 빈 목록을 받았을 수 있다.
const shrinkLimit = 0.7;

/// 지난달 목록이 없을 때 이보다 적으면 이상한 것이다(2026-09 지자체만 1,147건).
const minSupports = 300;

typedef FetchServices = Future<List<Map<String, Object?>>> Function();
typedef ConvertLinks = Future<CoupangRun> Function(Map<String, String> todo);

class MonthlyResult {
  MonthlyResult(this.attention, this.summary);

  /// 사람이 볼 것. 비어 있으면 조용히 끝난다.
  final List<String> attention;

  /// 실행 요약(마크다운 줄).
  final List<String> summary;
}

/// 한 번 돈다. [now]는 한국 시각이다([koreaNow]).
///
/// [fetchServices]가 null이면 정부24 키가 없는 것, [convertLinks]가 null이면
/// 쿠팡 키가 없는 것이다.
Future<MonthlyResult> runMonthly({
  required Directory root,
  required DateTime now,
  FetchServices? fetchServices,
  ConvertLinks? convertLinks,
  Set<String> accept = const {},
  bool onlyCoupang = false,
  String Function(Object)? hide,
}) async {
  String safe(Object e) => hide == null ? '$e' : hide(e);
  File file(String path) => File('${root.path}/$path');

  final dataFile = file(dataPath);
  final data = jsonDecode(dataFile.readAsStringSync()) as Map<String, Object?>;
  final before = jsonEncode(data);
  final attention = <String>[];
  final summary = <String>['## 매달 데이터 갱신 ${dayOf(now)}', ''];
  final status = <String, Object?>{'ran': _stamp(now)};

  // ── 1·2) 정부24 ──────────────────────────────────────────────────
  if (!onlyCoupang) {
    if (fetchServices == null) {
      attention.add(
        '정부24 키(DATA_GO_KR_KEY)가 없어 지원 목록과 나라 제도를 확인하지 '
        '못했습니다. 저장소 Settings → Secrets and variables → Actions에 '
        '넣어 주세요.',
      );
    } else {
      try {
        final services = await fetchServices();
        summary.add('정부24 서비스 ${services.length}개를 받았습니다.');

        // 지원 목록.
        final pick = pickSupports(services);
        final prev = _count(file(supportsPath));
        final n = pick.items.length;
        final tooFew = prev != null ? n < prev * shrinkLimit : n < minSupports;
        if (tooFew) {
          attention.add(
            '지원 목록이 ${prev ?? '(처음)'}개 → $n개로 너무 적습니다. 정부24 쪽 '
            '사고일 수 있어 이번에는 올리지 않았습니다.',
          );
        } else {
          final checked = dayOf(now);
          _writeJson(
            file(supportsPath),
            supportsFile(items: pick.items, checked: checked),
          );
          data['local'] = {
            'checked': checked,
            'count': n,
            'nation': pick.nation,
          };
          summary.add(
            '- 지원 목록 $n개(나라 ${pick.nation} · 지자체 ${n - pick.nation}) — '
            '지난번 ${prev ?? '없음'}',
          );
        }
        status['supports'] = {
          'count': n,
          'nation': pick.nation,
          'perSido': pick.perSido,
          'curated': pick.curated,
          'noUrl': pick.noUrl,
          if (tooFew) 'skipped': true,
        };

        // 나라 제도 여덟 가지.
        final watchFile = file(watchPath);
        final baseline = watchFile.existsSync()
            ? jsonDecode(watchFile.readAsStringSync()) as Map<String, Object?>
            : <String, Object?>{};
        final report = watchCentral(
          baseline: baseline,
          services: services,
          accept: accept,
        );
        _writeJson(watchFile, report.baseline);
        final bumped = bumpChecked(data, report.bump, monthOf(now));
        status['central'] = {
          for (final e in report.status.entries) e.key: e.value.name,
        };
        summary.add(
          '- 나라 제도: ${[for (final e in report.status.entries) '${e.key} ${e.value.label}'].join(' · ')}',
        );
        if (bumped.isNotEmpty) {
          summary.add('- 확인 시점을 ${monthOf(now)}로: ${bumped.join(', ')}');
        }
        file(changesPath).writeAsStringSync(_changes(report, now));
        if (report.needsHuman) {
          attention.add(
            '나라 제도의 정부24 글이 바뀌었거나 찾지 못했습니다 — '
            '$changesPath를 보고 앱·data.json을 고친 뒤 받아들여 주세요.',
          );
        }
      } on Gov24KeyRejected catch (e) {
        attention.add(
          '정부24 키가 거절됐습니다(HTTP ${e.status}). 공공데이터포털 활용신청이 '
          '살아 있는지, 「일반 인증키(Decoding)」를 넣었는지 봐 주세요.',
        );
      } catch (e) {
        attention.add('정부24에서 받다가 멈췄습니다: ${safe(e)}');
      }
    }
  }

  // ── 3) 쿠팡 링크 ─────────────────────────────────────────────────
  final urls = file(coupangUrlsPath);
  if (urls.existsSync()) {
    final targets = readCoupangTargets(urls.readAsStringSync());
    final known = data['coupang'] is Map
        ? (data['coupang'] as Map).cast<String, Object?>()
        : <String, Object?>{};
    final todo = {
      for (final e in targets.entries)
        if (known[e.key] is! String) e.key: e.value,
    };
    var added = 0;
    if (todo.isEmpty) {
      summary.add('- 쿠팡 링크: 품목 ${targets.length}개 모두 있음');
    } else if (convertLinks == null) {
      attention.add('쿠팡 키가 없어 새 품목 ${todo.length}개의 링크를 못 만들었습니다.');
    } else {
      final run = await convertLinks(todo);
      added = run.links.length;
      if (added > 0) {
        data['coupang'] = {...known, ...run.links};
      }
      summary.add('- 쿠팡 링크 $added개를 새로 만들었습니다(남은 ${todo.length - added}개).');
      if (run.failure != null) {
        attention.add('쿠팡 링크를 만들다 멈췄습니다: ${safe(run.failure!)}');
      }
    }
    status['coupang'] = {
      'items': targets.length,
      'added': added,
      'missing': todo.length - added,
    };
  }

  if (jsonEncode(data) != before) {
    data['updated'] = dayOf(now);
    _writeJson(dataFile, data);
  }
  status['attention'] = attention;
  _writeJson(file(statusPath), status);

  if (attention.isNotEmpty) {
    summary
      ..add('')
      ..add('### 확인할 것')
      ..addAll(attention.map((a) => '- $a'));
  }
  return MonthlyResult(attention, summary);
}

/// 사람이 확인한 뒤 바뀐 글(pending)을 새 기준으로 받아들인다 — 키가 필요
/// 없다. 받아들인 제도는 확인 시점도 이번 달로 올린다.
List<String> acceptPending({
  required Directory root,
  required DateTime now,
  required Set<String> programs,
}) {
  final watchFile = File('${root.path}/$watchPath');
  final dataFile = File('${root.path}/$dataPath');
  final baseline =
      jsonDecode(watchFile.readAsStringSync()) as Map<String, Object?>;
  final all = (baseline['programs'] as Map?) ?? const {};
  final accepted = <String>[];
  for (final e in all.entries) {
    final id = e.key as String;
    if (!programs.contains('all') && !programs.contains(id)) continue;
    final p = e.value as Map;
    final pending = p.remove('pending');
    if (pending is Map && pending.isNotEmpty) {
      ((p['services'] ??= <String, Object?>{}) as Map).addAll(pending);
      accepted.add(id);
    }
  }
  if (accepted.isEmpty) return accepted;
  _writeJson(watchFile, baseline);
  final data = jsonDecode(dataFile.readAsStringSync()) as Map<String, Object?>;
  if (bumpChecked(data, accepted, monthOf(now)).isNotEmpty) {
    data['updated'] = dayOf(now);
    _writeJson(dataFile, data);
  }
  return accepted;
}

/// 앱에서 새로 뽑은 data.json([fresh])을 올린 것([published])과 합친다.
///
/// 앱에서 뽑은 것이 금액·시세·지역의 기준이다. 다만 자동 작업이 올린 것은
/// 지킨다 — 제도별 **더 새 확인 시점**, 지원 목록 날짜(`local`), 앱에 아직
/// 없는 **쿠팡 링크**. 이걸 안 하면 앱에서 뽑아 올릴 때마다 확인 시점이
/// 되돌아가고, 앱이 지원 목록을 다시 내려받지 않고, 새 품목 링크가 빠진다.
Map<String, Object?> mergeData(
  Map<String, Object?> fresh,
  Map<String, Object?> published,
) {
  final out = jsonDecode(jsonEncode(fresh)) as Map<String, Object?>;
  final pubPrograms =
      ((published['support'] as Map?)?['programs'] as Map?) ?? const {};
  final outSupport = (out['support'] ??= <String, Object?>{}) as Map;
  final outPrograms = (outSupport['programs'] ??= <String, Object?>{}) as Map;
  for (final e in pubPrograms.entries) {
    final pubChecked = (e.value as Map)['checked'];
    if (pubChecked is! String) continue;
    final mine = (outPrograms[e.key] ??= <String, Object?>{}) as Map;
    final myChecked = mine['checked'];
    if (myChecked is! String || pubChecked.compareTo(myChecked) > 0) {
      mine['checked'] = pubChecked;
    }
  }
  if (published['local'] != null) out['local'] = published['local'];
  final pubLinks = (published['coupang'] as Map?) ?? const {};
  final myLinks = (out['coupang'] as Map?) ?? const {};
  if (pubLinks.isNotEmpty) out['coupang'] = {...pubLinks, ...myLinks};
  return out;
}

Future<void> main(List<String> args) async {
  final opts = _parse(args);
  final root = Directory(opts['root'] ?? '.');
  final now = koreaNow();

  if (opts['merge'] case final freshPath?) {
    final dataFile = File('${root.path}/$dataPath');
    final merged = mergeData(
      jsonDecode(File(freshPath).readAsStringSync()) as Map<String, Object?>,
      jsonDecode(dataFile.readAsStringSync()) as Map<String, Object?>,
    );
    _writeJson(dataFile, merged);
    stdout.writeln('합쳤습니다 → ${dataFile.path}');
    return;
  }

  if (opts['accept-pending'] case final which?) {
    final accepted = acceptPending(root: root, now: now, programs: _ids(which));
    stdout.writeln(
      accepted.isEmpty
          ? '받아들일 바뀐 글이 없습니다.'
          : '받아들였습니다: ${accepted.join(', ')} (확인 시점 ${monthOf(now)})',
    );
    return;
  }

  final env = Platform.environment;
  final key = env['DATA_GO_KR_KEY']?.trim() ?? '';
  final access = env['COUPANG_ACCESS_KEY']?.trim() ?? '';
  final secret = env['COUPANG_SECRET_KEY']?.trim() ?? '';
  final gov = key.isEmpty ? null : Gov24Client(key);
  try {
    final result = await runMonthly(
      root: root,
      now: now,
      fetchServices: gov == null ? null : () => gov.all('serviceList'),
      convertLinks: access.isEmpty || secret.isEmpty
          ? null
          : (todo) => convertCoupang(
              todo: todo,
              accessKey: access,
              secretKey: secret,
              log: stdout.writeln,
            ),
      accept: _ids(opts['accept'] ?? env['ACCEPT'] ?? ''),
      onlyCoupang:
          opts.containsKey('only-coupang') || env['ONLY_COUPANG'] == 'true',
      hide: gov?.hide,
    );
    final text = result.summary.join('\n');
    stdout.writeln(text);
    if (env['GITHUB_STEP_SUMMARY'] case final path? when path.isNotEmpty) {
      File(path).writeAsStringSync('$text\n', mode: FileMode.append);
    }
    if (env['GITHUB_OUTPUT'] case final path? when path.isNotEmpty) {
      File(path).writeAsStringSync(
        'attention=${result.attention.isNotEmpty}\n',
        mode: FileMode.append,
      );
    }
  } finally {
    gov?.close();
  }
}

/// 「S04, S07」·「all」 → {'S04', 'S07'}.
Set<String> _ids(String raw) => {
  for (final part in raw.split(RegExp(r'[,\s]+')))
    if (part.trim().isNotEmpty) part.trim(),
};

int? _count(File f) {
  if (!f.existsSync()) return null;
  try {
    final root = jsonDecode(f.readAsStringSync());
    final items = root is Map ? root['items'] : null;
    return items is List ? items.length : null;
  } catch (_) {
    return null;
  }
}

/// 두 칸 들여쓰기, 줄 끝은 LF — 앱에서 뽑은 data.json과 같은 모양.
void _writeJson(File f, Object? value) {
  f.parent.createSync(recursive: true);
  f.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(value)}\n');
}

String _stamp(DateTime now) =>
    '${dayOf(now)}T${now.hour.toString().padLeft(2, '0')}:'
    '${now.minute.toString().padLeft(2, '0')}+09:00';

String _changes(WatchReport report, DateTime now) {
  final out = StringBuffer('# 나라 제도 — 정부24 글 확인 (${dayOf(now)})\n\n');
  final human = report.notes.where((n) => n.status.needsHuman).toList();
  if (human.isEmpty) {
    out.writeln('지금은 확인할 것이 없습니다. 지켜보는 나라 제도 모두 사람이 확인한 글과 같습니다.');
  } else {
    out
      ..writeln('사람이 확인할 것이 있습니다. 원문을 보고 앱(`support_programs.dart`)과')
      ..writeln('`v1/data.json`을 고친 뒤, 앱 저장소에서')
      ..writeln(
        '`dart tool/monthly/monthly.dart --root <이 저장소> --accept-pending S04`',
      )
      ..writeln('처럼 받아들이고 올립니다(또는 Actions → Run workflow → accept에 S04).')
      ..writeln();
    for (final n in human) {
      out
        ..writeln('## ${n.program} — ${n.status.label}')
        ..writeln();
      for (final line in n.lines) {
        out.writeln(line);
      }
      out.writeln();
    }
  }
  final added = report.notes.where((n) => n.status == WatchStatus.added);
  if (added.isNotEmpty) {
    out
      ..writeln()
      ..writeln('처음 적은 기준: ${added.map((n) => n.program).join(', ')}');
  }
  return out.toString();
}

Map<String, String> _parse(List<String> args) {
  final out = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (!arg.startsWith('--')) continue;
    final name = arg.substring(2);
    if (name == 'only-coupang') {
      out[name] = 'true';
    } else if (i + 1 < args.length) {
      out[name] = args[++i];
    }
  }
  return out;
}
