// 쿠팡 파트너스 딥링크 — 검색 주소를 파트너스 링크(link.coupang.com)로 바꾼다.
//
// 두 도구가 같이 쓴다: 바탕화면 exe(tool/make_coupang_links.dart → 앱에 굽기)와
// 매달 1일 자동 작업(tool/monthly/monthly.dart → v1/data.json에 넣기).
//
// 키는 **환경변수 COUPANG_ACCESS_KEY / COUPANG_SECRET_KEY**로만 받는다.
// Claude는 키를 다루지 않는다(CLAUDE.md).
//
// 한 번 만든 파트너스 링크는 기한이 없다 — 그래서 **링크가 없는 품목만**
// 바꾼다. 한 번에 90번까지, 요청 사이 1초, 첫 실패에서 멈춘다(한도를 거듭
// 넘기면 키가 막힌다).

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const coupangHost = 'api-gateway.coupang.com';
const coupangDeeplinkPath =
    '/v2/providers/affiliate_open_api/apis/openapi/v1/deeplink';

/// 한 번 돌릴 때 부르는 최대 횟수. 딥링크 한도를 1시간에 100번으로 적어
/// 두었지만 공식 문서로 다시 확인하지는 못했다.
const coupangLimit = 90;

/// 쿠팡 파트너스 HMAC 인증 머리글.
String coupangAuthorization({
  required String method,
  required String path,
  required String accessKey,
  required String secretKey,
  DateTime? now,
}) {
  final at = (now ?? DateTime.now()).toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  final signedDate =
      '${two(at.year % 100)}${two(at.month)}${two(at.day)}T'
      '${two(at.hour)}${two(at.minute)}${two(at.second)}Z';

  final message = '$signedDate$method$path';
  final signature = Hmac(
    sha256,
    utf8.encode(secretKey),
  ).convert(utf8.encode(message)).toString();

  return 'CEA algorithm=HmacSHA256, access-key=$accessKey, '
      'signed-date=$signedDate, signature=$signature';
}

/// 리포트에서 갈라 볼 이름. 영문·숫자·밑줄만 남긴다(품목 id `C7-25` → `C7_25`).
String coupangSubId(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');

/// 응답 모양이 조금씩 달라도 단축 링크를 찾아낸다.
String? coupangExtractLink(Object? decoded) {
  final data = decoded is Map ? decoded['data'] : decoded;
  final first = data is List && data.isNotEmpty ? data.first : data;
  if (first is! Map) return null;
  for (final key in ['shortenUrl', 'landingUrl', 'originalUrl']) {
    final value = first[key];
    if (value is String && value.startsWith('http')) return value;
  }
  return null;
}

/// `품목id<탭>검색주소` 줄들을 읽는다.
Map<String, String> readCoupangTargets(String text) => {
  for (final line in const LineSplitter().convert(text))
    if (line.split('\t') case [
      final id,
      final url,
    ] when id.trim().isNotEmpty && url.startsWith('https://'))
      id.trim(): url.trim(),
};

class CoupangRun {
  CoupangRun(this.links, this.failure);

  /// 이번에 새로 만든 링크(품목 id → 링크).
  final Map<String, String> links;

  /// 멈춘 까닭. 다 되면 null.
  final String? failure;
}

/// [todo](품목 id → 검색 주소)를 파트너스 링크로 바꾼다.
Future<CoupangRun> convertCoupang({
  required Map<String, String> todo,
  required String accessKey,
  required String secretKey,
  int limit = coupangLimit,
  Duration pause = const Duration(seconds: 1),
  HttpClient? client,
  void Function(String)? log,
}) async {
  final http = client ?? (HttpClient()..userAgent = 'birthprep-coupang');
  final links = <String, String>{};
  String? failure;
  var called = 0;
  try {
    for (final entry in todo.entries) {
      if (called == limit) break;
      if (called > 0) await Future<void>.delayed(pause);
      called++;
      try {
        final req = await http.postUrl(
          Uri.https(coupangHost, coupangDeeplinkPath),
        );
        req.headers.set(
          HttpHeaders.authorizationHeader,
          coupangAuthorization(
            method: 'POST',
            path: coupangDeeplinkPath,
            accessKey: accessKey,
            secretKey: secretKey,
          ),
        );
        req.headers.contentType = ContentType(
          'application',
          'json',
          charset: 'utf-8',
        );
        req.add(
          utf8.encode(
            jsonEncode({
              'coupangUrls': [entry.value],
              // 어느 품목에서 눌렸는지 리포트에서 갈라 보려고 넣는다.
              'subId': coupangSubId(entry.key),
            }),
          ),
        );
        final res = await req.close().timeout(const Duration(seconds: 30));
        final body = await res.transform(utf8.decoder).join();
        if (res.statusCode != 200) {
          failure = '${entry.key} (HTTP ${res.statusCode}) ${_clip(body)}';
        } else {
          final link = coupangExtractLink(jsonDecode(body));
          if (link == null || !link.startsWith('https://link.coupang.com/')) {
            failure = '${entry.key} (링크를 못 찾음) ${_clip(body)}';
          } else {
            links[entry.key] = link;
          }
        }
      } catch (e) {
        failure = '${entry.key} ($e)';
      }
      if (failure != null) break;
      if (called % 20 == 0) log?.call('  쿠팡 $called / ${todo.length}');
    }
  } finally {
    if (client == null) http.close(force: true);
  }
  return CoupangRun(links, failure);
}

String _clip(String body) =>
    body.length <= 300 ? body : '${body.substring(0, 300)}…';
