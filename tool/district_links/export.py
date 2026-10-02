# 판정 결과(build/district_links/links_*.json)에서 앱에 넣을 것만 골라
#   tool/district_links/links.json   — 원본(저장소에 들어간다, 사람이 읽고 고칠 수 있다)
#   lib/data/catalog/district_links.dart — 앱이 쓰는 표(손으로 고치지 않는다)
# 를 만든다(--bake <v1/links.json>이면 게시된 표를 그대로 굽는다). 넣는 것: 앱 항목과 같은 사업으로 확인된 것(짝 확인 ≥ 0.8)과
# 나라 제도·보건소 공통 카드의 구 안내 쪽. 검토·새 것·범위 밖은 넣지 않는다.
import json, pathlib, re, sys, datetime
from urllib.parse import urlparse
import requests, urllib3
urllib3.disable_warnings()

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "build" / "district_links"
OUT_JSON = ROOT / "tool" / "district_links" / "links.json"
OUT_DART = ROOT / "lib" / "data" / "catalog" / "district_links.dart"
NATIONAL_ID = {**{f"S{n:02d}": f"S{n:02d}" for n in range(1, 12)}, **{f"H{n}": f"HC{n}" for n in range(1, 7)}}

def site_key(url):
    host = urlparse(url).hostname or ""
    parts = host.split(".")
    n = 3 if len(parts) >= 3 and parts[-2] in ("go", "seoul", "daegu", "ulsan", "busan", "incheon") else 2
    return ".".join(parts[-n:])

SITES = {f"{x['sido']} {x['district']}": {site_key(x["url"]), *( [site_key(x["birth"])] if x.get("birth") else [])}
         for x in json.loads((ROOT / "tool" / "local_sites.json").read_text(encoding="utf-8")) if x["district"]}
_https_ok = {}

def as_https(url):
    """http 링크는 https로 열리면 바꾸고, 안 열리면 None(앱은 https만 쓴다)."""
    if url.startswith("https://"):
        return url
    u = "https://" + url[len("http://"):]
    if u not in _https_ok:
        try:
            r = requests.get(u, timeout=20, verify=False, headers={"User-Agent": "Mozilla/5.0"})
            _https_ok[u] = r.status_code == 200
        except requests.RequestException:
            _https_ok[u] = False
    return u if _https_ok[u] else None

def load_existing():
    if OUT_JSON.exists():
        return json.loads(OUT_JSON.read_text(encoding="utf-8"))
    return {"checked": {}, "links": []}

def collect(files, old_rows):
    """판정 결과에서 앱에 넣을 줄을 고른다. 이번에 **제대로 돈 곳**(출발 쪽이 열리고 링크 후보가
    있던 곳)만 새 줄로 바꾸고, 못 돈 곳은 예전 줄을 그대로 둔다 — 누리집이 잠깐 안 열린 달에
    그 시·군·구의 단추가 사라지지 않게."""
    keep = {}                      # (place, id) -> row
    found = {}                     # place -> {url: label} — 앱 목록에 없는 구 자체 사업
    notes = {}                     # url -> [[종류, 줄]] — 쪽 본문에서 고른 줄(서울 시범)
    checked, runs, dropped = {}, set(), []
    BAD.clear()
    for f in files:
        data = json.loads(pathlib.Path(f).read_text(encoding="utf-8"))
        day = datetime.date.fromtimestamp(pathlib.Path(f).stat().st_mtime).isoformat()
        for r in data["results"]:
            if "sido" not in r:
                continue
            place = f"{r['sido']} {r['district']}"
            if not (r.get("hub_status") or {}).get("ok") or not r.get("n_candidates") or r.get("error"):
                continue
            runs.add(place)
            checked[place] = day
            for l in r["links"]:
                # 잠깐 안 열린 쪽(응답 없음)은 빼지 않는다 — 404·410처럼 없어진 쪽만.
                gone = l.get("cls") == "broken" and l.get("status") in (404, 410)
                # 「split」 — 여러 사업을 묶은 쪽, 사업마다 나눈 것이 대신 들어간다(pilot.split_programs).
                if (gone or l.get("cls") in ("login", "not_page", "out_scope", "split")) and l.get("final"):
                    BAD.add((place, as_https(l["final"]) or l["final"]))
                if is_found(l):
                    url = as_https(l["final"])
                    if url and site_key(url) in SITES.get(place, set()):
                        found.setdefault(place, {}).setdefault(url, clean_label(l["text"]))
                        # 누리집이 태그를 글자로 내보낸 줄(「<p class=…>」)은 뺀다.
                        kept = [n for n in l.get("notes") or [] if not re.search(r"<[a-zA-Z/]", n[1])]
                        if kept:
                            notes.setdefault(url, kept)
                    continue
                if l.get("cls") not in ("match", "national"):
                    continue
                m = l["match"]
                ids = [NATIONAL_ID[m["key"]]] if m["level"] == "나라 제도" else m["ids"]
                url = as_https(l["final"])
                # 그 구·군 자기 누리집 안의 쪽만 — 「동래구 안내 보기」가 부산시 쪽을 열면 안 된다.
                if not url or site_key(url) not in SITES.get(place, set()):
                    dropped.append((place, l["final"]))
                    continue
                label = clean_label(l["text"])
                # 본문 줄은 「더 찾은 것」에만 — 앱이 이미 정부24·복지로 글로 보여 주는 사업에 구 쪽
                # 글을 붙이면 낡은 구 쪽(「아동수당 만 8세」)과 앱이 다른 말을 한다(2026-10-01 서울 시범).
                for i in ids:
                    row = {"place": place, "id": i, "url": url, "label": label,
                           "p": l["p_same"], "hash": l.get("hash")}
                    k = (place, i)
                    if k not in keep or keep[k]["p"] < row["p"]:
                        keep[k] = row
    rows = [x for x in old_rows if x["place"] not in runs] + list(keep.values())
    rows.sort(key=lambda x: (x["place"], x["id"]))
    # 한 곳에 30건까지, 같은 이름은 한 번만.
    found_rows = {}
    for place, byurl in found.items():
        seen, out = set(), []
        for url, label in byurl.items():
            key = re.sub(r"\s|(안내|소개|운영|신청)$", "", re.sub(r"\s*(안내|소개|운영|신청)$", "", label))
            if key not in seen and len(out) < 30:
                seen.add(key)
                out.append([label, url])
        found_rows[place] = out
    return rows, checked, runs, dropped, found_rows, notes

BAD = set()   # (place, url) — 이번 판정에서 깨졌거나·로그인·설명 쪽 아님·범위 밖으로 나온 쪽

def carry_found(old_found, new_found, rows, runs):
    """지난번에 넣은 「더 찾은 것」을 이어 둔다 — 2026-10-02 출발 쪽을 넓혀 다시 판정하자 영도구
    「출산축하금」·안성 「출생축하선물」 같은 진짜 사업이 판정이 흔들려 빠졌다. 이번에 그 쪽이 깨졌거나
    사업 설명이 아니라고 나왔거나, 앱 목록의 사업과 짝이 지어졌거나(rows), 거르기(NOT_FOUND)에
    걸리면 뺀다. 한 곳에 30건까지."""
    linked = {(r["place"], r["url"]) for r in rows}
    out = {p: list(v) for p, v in new_found.items()}
    for place, items in old_found.items():
        if place not in runs:
            continue
        have = {u for _, u in out.get(place, [])}
        keys = {re.sub(r"\s", "", t) for t, _ in out.get(place, [])}
        for label, url in items:
            if (url in have or (place, url) in linked or (place, url) in BAD
                    or re.sub(r"\s", "", label) in keys or not is_found({"text": label, "_carry": True})):
                continue
            if len(out.setdefault(place, [])) < 30:
                out[place].append([label, url])
    return out

def merge_notes(old_notes, new_notes, links_rows, found, runs):
    """줄 표 — 이번에 돈 곳은 새 것, 못 돈 곳은 지난 것. 표(links·found)에 남은 쪽의 것만."""
    place_of = {r["url"]: r["place"] for r in links_rows}
    place_of.update({u: p for p, items in found.items() for _, u in items})
    out = {u: v for u, v in old_notes.items() if place_of.get(u) not in runs}
    out.update(new_notes)
    return {u: v for u, v in sorted(out.items()) if u in place_of and v}

def clean_label(t):
    """링크 글자 — 공백을 줄이고 앞의 기호(「- 」「· 」「# 」)와 끝의 「자세히 보기」를 뗀다."""
    t = re.sub(r"\s+", " ", t).strip()
    t = re.sub(r"^[\-·•#○◦▶>\s]+", "", t)
    # 「1-4 임산부 배려 전용 주차구역」·「2-9 해피맘 건강교실」 — 누리집 칸 번호를 뗀다.
    t = re.sub(r"^\d+(-\d+)+\s+", "", t)
    # 「공동육아나눔터란 ?」「B형간염 주산기 감염 예방사업이란?」 — 사업 이름만.
    t = re.sub(r"\s*(이)?란\s*\?$", "", t)
    return re.sub(r"\s*자세히\s*보기$", "", t).strip()

# 출산 준비와 거리가 먼 아동복지·행정 절차 — 「새 것」이어도 앱에 싣지 않는다.
NOT_FOUND = re.compile(r"위탁|학대|결식|급식|옴부즈|출생신고|금연|보호종료|자립|지역아동센터|청소년|초등|방과후|\d+월\s*프로그램|[{}]|^\d{4}년"
                       # 2026-10-01 전국 넓힘에서 들어온 행정·보호 쪽(「아동보호」「어린이집 관리」).
                       r"|아동보호|보호아동|요보호|어린이집\s*(관리|운영|현황|평가|지도)"
                       # 2026-10-02 출발 쪽 넓힘 — 게시판 글·지난 행사(「9월 임신육아교실 운영 안내」「접수마감」
                       # 「….」로 잘린 제목), 계산기(「출산예정일」), 나라 제도와 겹치는 쪽(부모급여·양육수당·
                       # 맘편한 임신·홍역·MMR·어린이 예방접종), 직원·시설용(보육자격·대체교사·원아 교육), 멈춘 사업.
                       r"|^\d+월\s|\.\.$|접수\s*마감|제\d+회|에어바운스|출산\s*예정일|새창|^(?!.*(출산|출생|축하|장려)).*(부모급여|양육수당)|보육료\s*/"
                       r"|맘편한\s*임신|홍역|MMR|어린이\s*예방접종|보육\s*자격|대체\s*교사|원아|보류|중단됨|사업\s*종료")

# 쪽을 사업마다 나누다 딸려 온 칸 제목(「지원대상 및 신청자격」「검진절차」「사용처」「지원항목 및 금액」) —
# 칸 낱말이 있는데 끝이 사업 이름 꼴(…지원·대여·교실·수당·운영…)이 아니면 사업이 아니다(2026-10-02).
FIELD_TITLE = re.compile(r"대상|자격|요건|절차|방법|서류|범위|방식|기간|시간|장소|항목|사용처|참고사항|유의사항|"
                         r"교육\s*내용|제공되는|변경\s*시|신청$|^사업\s*신청|접수$|관련\s*사항|기준$|주요\s*내용|용도|^\[.*\]$|\?$|^<.*>$|^사업\s*명$|^서비스\s*이용$")
PROGRAM_END = re.compile(r"(지원(사업)?|대여|교실|클리닉|검사|검진|수당|축하금|장려금|지원금|비|운영|사업|서비스|접종|"
                         r"카드|발급|감면|보험|쉼터|모임|프로그램|용품|꾸러미|센터)\s*(\(.*\))?$")

def field_title(t):
    t = re.sub(r"\s+", " ", t).strip()
    return bool(FIELD_TITLE.search(t)) and not PROGRAM_END.search(t)

def is_found(l):
    """앱 목록에 없는 구 자체 사업 중 앱에 보여 줄 것 — 그 사업을 설명하는 쪽이고(0.8), 로그인 없이
    보이고, 대상에 임신~만 6세가 들고(0.5), 목록의 어느 것과도 짝이 안 지어진 것(「새 것」을 고른 확신
    0.5, 또는 고른 짝을 확인에서 아니라고 한 것). 2026-10-01 넓힘 — 서초구 「모유 수유 클리닉」(새 것
    0.54)·「출산 후 건강검진」(범위 0.55)이 빠졌다. 겹쳐도 해는 작다(이름과 원문 링크뿐)."""
    if NOT_FOUND.search(l.get("text", "")) or re.search(r"^\s*\d+\s*[).]|:", l.get("text", "")):
        return False
    if field_title(clean_label(l.get("text", ""))):
        return False
    if l.get("_carry"):
        return True
    if l.get("cls") == "split":
        return False
    unmatched = not l.get("match") and (
        (l.get("same_as") == "new" and l.get("same_conf", 0) >= 0.5) or l.get("rejected_match"))
    return (l.get("cls") in ("new", "review") and unmatched and l.get("p_describes", 0) >= 0.8
            and l.get("p_scope", 0) >= 0.5 and l.get("p_login", 1) < 0.3 and not l.get("code_login"))

def remote(pages_root, files):
    """매달 작업 — 공개 저장소의 v1/links.json을 새로 쓰고 v1/data.json에 links 머리(날짜·지문)를
    적는다. 앱은 그 머리를 보고 새 표를 내려받는다(DistrictLinksStore). 링크가 지난달보다 3할 넘게
    줄면 쓰지 않고 실패로 끝낸다(누리집이 한꺼번에 막힌 달 — 사람이 본다)."""
    import hashlib
    root = pathlib.Path(pages_root)
    lp, dp = root / "v1" / "links.json", root / "v1" / "data.json"
    old = json.loads(lp.read_text(encoding="utf-8")) if lp.exists() else {"links": {}}
    old_rows = [{"place": k.split("|")[0], "id": k.split("|")[1], "url": v[0], "label": v[1]}
                for k, v in old.get("links", {}).items()]
    rows, checked, runs, dropped, new_found, new_notes = collect(files, old_rows)
    links = {f"{x['place']}|{x['id']}": [x["url"], x["label"]] for x in rows}
    found = {p: v for p, v in old.get("found", {}).items() if p not in runs}
    found.update(carry_found(old.get("found", {}), new_found, rows, runs))
    found = dict(sorted(found.items()))
    notes = merge_notes(old.get("notes", {}), new_notes, rows, found, runs)
    parts = [links, found, notes] if notes else [links, found]
    rev = hashlib.sha1(json.dumps(parts, ensure_ascii=False, sort_keys=True).encode()).hexdigest()[:16]
    n_old = len(old.get("links", {}))
    print(f"링크 {n_old} → {len(links)} · 더 찾은 것 {sum(len(v) for v in found.values())} · 본문 줄 {len(notes)}쪽"
          f" · 돈 곳 {len(runs)} · 뺀 링크 {len(dropped)}")
    if n_old and len(links) < n_old * 0.7:
        print("⚠️ 3할 넘게 줄었다 — 올리지 않는다", file=sys.stderr)
        sys.exit(3)
    if old.get("rev") == rev:
        # 표는 그대로여도 data.json에 알림 머리가 없으면(손으로 뽑아 올린 data.json 등) 채운다.
        data = json.loads(dp.read_text(encoding="utf-8"))
        head = {"checked": old["checked"], "rev": rev}
        if data.get("links") != head:
            data["links"] = head
            dp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print("바뀐 것 없음")
        return
    today = datetime.date.today().isoformat()
    lp.write_text(json.dumps({"checked": today, "rev": rev, "count": len(links), "links": dict(sorted(links.items())),
                              "found": found, **({"notes": notes} if notes else {})},
                             ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    data = json.loads(dp.read_text(encoding="utf-8"))
    data["links"] = {"checked": today, "rev": rev}
    dp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"v1/links.json {today} {rev}")

def main(files, bake=None):
    old = load_existing()
    if bake:
        # 게시된 v1/links.json을 그대로 앱에 굽는다(매달 작업 결과와 앱 판을 맞출 때).
        pub = json.loads(pathlib.Path(bake).read_text(encoding="utf-8"))
        rows = sorted(({"place": k.split("|")[0], "id": k.split("|")[1], "url": v[0], "label": v[1]}
                       for k, v in pub["links"].items()), key=lambda x: (x["place"], x["id"]))
        checked = {**old.get("checked", {}), **{r["place"]: pub["checked"] for r in rows}}
        found = dict(sorted(pub.get("found", {}).items()))
        notes = dict(sorted(pub.get("notes", {}).items()))
        dropped = []
    else:
        rows, new_checked, runs, dropped, new_found, new_notes = collect(files, old.get("links", []))
        checked = {**old.get("checked", {}), **new_checked}
        found = {p: v for p, v in old.get("found", {}).items() if p not in runs}
        found.update(carry_found(old.get("found", {}), new_found, rows, runs))
        found = dict(sorted(found.items()))
        notes = merge_notes(old.get("notes", {}), new_notes, rows, found, runs)
    OUT_JSON.write_text(json.dumps({"checked": dict(sorted(checked.items())), "links": rows, "found": found,
                                    "notes": notes},
                                   ensure_ascii=False, indent=1) + "\n", encoding="utf-8")

    def q(s):
        return "'" + s.replace("\\", "\\\\").replace("'", "\\'").replace("$", "\\$") + "'"
    built = max(checked.values()) if checked else datetime.date.today().isoformat()
    lines = [
        "import 'dart:convert';",
        "",
        "import '../models/region.dart';",
        "import 'local_sites.dart';",
        "",
        "/// 구 누리집 안에서 **그 혜택 하나를 설명하는 쪽**.",
        "///",
        "/// 사장님 2026-09-30: 「누리집을 눌러도 구청 첫 화면이나 로그인으로 가서 무슨",
        "/// 혜택인지 못 본다 — 혜택마다 정확한 링크가 있어야 한다」. 시·군·구마다",
        "/// 출산·육아 쪽에서 링크를 모으고, TypeSafe가 그 쪽이 혜택을 설명하는지 ·",
        "/// 로그인 없이 보이는지 · 앱 목록의 어느 항목과 같은 사업인지를 판정해",
        "/// **같은 사업으로 확인된 것만** 적었다(`tool/district_links/`). AI는 주소를",
        "/// 만들지 않고 누리집에 있는 링크 중에서 고르기만 한다.",
        "///",
        "/// 이 표는 앱에 든 판이다. 매달 1일 작업이 다시 판정해 `v1/links.json`으로",
        "/// 올리면 앱이 내려받아 더 새것을 쓴다([DistrictLinkBook],",
        "/// `DistrictLinksStore`).",
        "///",
        "/// 열쇠: 「서울특별시 마포구」 + 항목 id(지원 목록 id, 나라 제도 `S01`…,",
        "/// 보건소 공통 카드 `HC1`…).",
        "class DistrictLinks {",
        "  const DistrictLinks._();",
        "",
        "  /// 이 판을 만든 날(가장 늦게 확인한 날).",
        f"  static const builtOn = {q(built)};",
        "",
        "  /// 그 구에서 이 항목을 설명하는 쪽. 없으면 null.",
        "  static DistrictLink? of(Region region, String district, String id) =>",
        "      _links['${region.name} $district|$id'];",
        "",
        "  /// 그 구를 언제 확인했는지(「2026-09-30」). 검사용.",
        "  static String? checkedOf(Region region, String district) =>",
        "      _checked['${region.name} $district'];",
        "",
        "  /// 전부 — 검사용.",
        "  static Map<String, DistrictLink> get all => _links;",
        "}",
        "",
        "class DistrictLink {",
        "  const DistrictLink(this.url, this.label);",
        "",
        "  final String url;",
        "",
        "  /// 구 누리집에 걸린 링크 글자 그대로(「35세 이상 임산부 의료비 지원」).",
        "  final String label;",
        "}",
        "",
        "/// 구 누리집 쪽 본문에서 고른 한 줄 — **글자 그대로**다. AI는 줄을 고르기만",
        "/// 하고 쓰지 않는다(사장님 2026-10-01 「내용까지 앱 항목으로 — 서울 시범」).",
        "class DistrictNote {",
        "  const DistrictNote(this.kind, this.text);",
        "",
        "  /// `benefit`(받는 것) · `who`(대상) · `apply`(신청).",
        "  final String kind;",
        "  final String text;",
        "",
        "  static const kinds = {'benefit': '받는 것', 'who': '대상', 'apply': '신청'};",
        "",
        "  String get kindLabel => kinds[kind] ?? '';",
        "}",
        "",
        "/// 링크 표 한 판 — 앱에 든 판([baked]) 또는 내려받은 `v1/links.json`.",
        "class DistrictLinkBook {",
        "  const DistrictLinkBook({",
        "    required this.links,",
        "    required this.checked,",
        "    this.rev,",
        "    this.found = const {},",
        "    this.notes = const {},",
        "  });",
        "",
        "  /// 쪽 주소 → 그 쪽 본문에서 고른 줄(서울 시범). 없으면 링크만 보여 준다.",
        "  final Map<String, List<DistrictNote>> notes;",
        "",
        "  /// 열쇠 「서울특별시 마포구|S09」 → 쪽.",
        "  final Map<String, DistrictLink> links;",
        "",
        "  /// 앱 목록(정부24·복지로)에 없는 구 자체 사업 — 「서울특별시 마포구」 → 그 구 누리집의",
        "  /// 사업 쪽들. 그 사업을 설명하고 로그인 없이 보이고 대상에 임신~만 6세가 드는 것만.",
        "  final Map<String, List<DistrictLink>> found;",
        "",
        "  /// 만든 날(`2026-10-01`).",
        "  final String checked;",
        "",
        "  /// 내용 지문(16자리 16진수). 앱에 든 판은 없다.",
        "  final String? rev;",
        "",
        "  static const baked = DistrictLinkBook(",
        "    links: _links,",
        "    checked: DistrictLinks.builtOn,",
        "    found: _found,",
        "    notes: _notes,",
        "  );",
        "",
        "  DistrictLink? of(Region region, String district, String id) =>",
        "      links['${region.name} $district|$id'];",
        "",
        "  /// 그 쪽 본문에서 고른 줄. 없으면 빈 목록.",
        "  List<DistrictNote> notesOf(String url) => notes[url] ?? const [];",
        "",
        "  /// 그 구 누리집에서 더 찾은 사업. 없으면 빈 목록.",
        "  List<DistrictLink> foundOf(Region region, String district) =>",
        "      found['${region.name} $district'] ?? const [];",
        "",
        "  /// 이보다 적게 읽히면 이상한 파일이다 — 앱에 든 판의 반.",
        "  static int get minLinks => _links.length ~/ 2;",
        "",
        "  /// 내려받은 글을 읽는다. 줄마다 검사해 **그 시·군·구 자기 누리집 안의",
        "  /// https 쪽**만 남기고, 남은 것이 [minLinks]보다 적으면 null(앱에 든 판을",
        "  /// 쓴다). 무엇이 잘못돼도 던지지 않는다.",
        "  static DistrictLinkBook? parse(String body) {",
        "    try {",
        "      final root = jsonDecode(body);",
        "      if (root is! Map) return null;",
        "      final checked = root['checked'];",
        "      if (checked is! String || !_day.hasMatch(checked)) return null;",
        "      final rev = root['rev'];",
        "      final raw = root['links'];",
        "      if (raw is! Map) return null;",
        "      final links = <String, DistrictLink>{};",
        "      for (final MapEntry(:key, :value) in raw.entries) {",
        "        if (key is! String || value is! List || value.length != 2) continue;",
        "        final [url, label] = value;",
        "        if (url is! String || label is! String) continue;",
        "        final bar = key.indexOf('|');",
        "        if (bar < 0 || label.trim().isEmpty || label.length > 80) continue;",
        "        if (!isOwnSite(key.substring(0, bar), url)) continue;",
        "        links[key] = DistrictLink(url, label.trim());",
        "      }",
        "      if (links.length < minLinks) return null;",
        "      final found = <String, List<DistrictLink>>{};",
        "      final rawFound = root['found'];",
        "      if (rawFound is Map) {",
        "        for (final MapEntry(:key, :value) in rawFound.entries) {",
        "          if (key is! String || value is! List) continue;",
        "          final list = <DistrictLink>[",
        "            for (final item in value.take(30))",
        "              if (item is List && item.length == 2)",
        "                if (item case [final String label, final String url])",
        "                  if (label.trim().isNotEmpty &&",
        "                      label.length <= 80 &&",
        "                      isOwnSite(key, url))",
        "                    DistrictLink(url, label.trim()),",
        "          ];",
        "          if (list.isNotEmpty) found[key] = list;",
        "        }",
        "      }",
        "      final notes = <String, List<DistrictNote>>{};",
        "      final rawNotes = root['notes'];",
        "      if (rawNotes is Map) {",
        "        for (final MapEntry(:key, :value) in rawNotes.entries) {",
        "          if (key is! String || !key.startsWith('https://') || value is! List) {",
        "            continue;",
        "          }",
        "          final list = <DistrictNote>[",
        "            for (final item in value.take(10))",
        "              if (item case [final String kind, final String text])",
        "                if (DistrictNote.kinds.containsKey(kind) &&",
        "                    text.trim().isNotEmpty &&",
        "                    text.length <= 200)",
        "                  DistrictNote(kind, text.trim()),",
        "          ];",
        "          if (list.isNotEmpty) notes[key] = list;",
        "        }",
        "      }",
        "      return DistrictLinkBook(",
        "        links: links,",
        "        checked: checked,",
        "        rev: rev is String && _rev.hasMatch(rev) ? rev : null,",
        "        found: found,",
        "        notes: notes,",
        "      );",
        "    } catch (_) {",
        "      return null;",
        "    }",
        "  }",
        "",
        "  /// [url]이 https이고 그 시·군·구 누리집(또는 출산·육아 쪽이 있는 누리집)",
        "  /// 안인지. 「동래구 안내 보기」가 부산시 쪽을 열면 안 된다.",
        "  static bool isOwnSite(String place, String url) {",
        "    final uri = Uri.tryParse(url);",
        "    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return false;",
        "    final home = LocalSites.all[place];",
        "    if (home == null) return false;",
        "    final birth = LocalSites.births[place];",
        "    return {siteOf(home), if (birth != null) siteOf(birth)}.contains(siteOf(url));",
        "  }",
        "",
        "  /// 「www.mapo.go.kr」→「mapo.go.kr」, 「health.gangnam.go.kr」→「gangnam.go.kr」.",
        "  static String siteOf(String url) {",
        "    final parts = (Uri.tryParse(url)?.host ?? '').split('.');",
        "    if (parts.length < 2) return parts.join('.');",
        "    const second = {'go', 'seoul', 'daegu', 'ulsan', 'busan', 'incheon'};",
        "    final n = parts.length >= 3 && second.contains(parts[parts.length - 2]) ? 3 : 2;",
        "    return parts.sublist(parts.length - n).join('.');",
        "  }",
        "",
        r"  static final _day = RegExp(r'^\d{4}-\d{2}-\d{2}$');",
        "  static final _rev = RegExp(r'^[0-9a-f]{16}$');",
        "}",
        "",
        "// ── 아래는 tool/district_links/export.py가 만든다. 손으로 고치지 않는다. ──",
        "const _checked = <String, String>{",
        *[f"  {q(k)}: {q(v)}," for k, v in sorted(checked.items())],
        "};",
        "const _found = <String, List<DistrictLink>>{",
        *[f"  {q(p)}: [\n" + "".join(f"    DistrictLink({q(u)}, {q(t)}),\n" for t, u in items) + "  ],"
          for p, items in found.items()],
        "};",
        "const _notes = <String, List<DistrictNote>>{",
        *[f"  {q(u)}: [\n" + "".join(f"    DistrictNote({q(k)}, {q(t)}),\n" for k, t in items) + "  ],"
          for u, items in notes.items()],
        "};",
        "const _links = <String, DistrictLink>{",
        *[f"  {q(x['place'] + '|' + x['id'])}: DistrictLink(\n    {q(x['url'])},\n    {q(x['label'])},\n  ),"
          for x in rows],
        "};",
        "",
    ]
    OUT_DART.write_text("\n".join(lines), encoding="utf-8")
    print(f"{len(rows)}줄 · {len(checked)}곳 → {OUT_JSON.name}, {OUT_DART.name} · 뺀 링크 {len(dropped)}(https 안 됨·다른 누리집)")

if __name__ == "__main__":
    args = sys.argv[1:]
    if args[:1] == ["--remote"]:
        src = pathlib.Path(__import__("os").environ.get("LINK_OUT") or SRC)
        remote(args[1], args[2:] or sorted(str(p) for p in src.glob("links_*.json") if "_" not in p.stem[len("links_"):]))
    elif args[:1] == ["--bake"]:
        main([], bake=args[1])
    else:
        main(args or sorted(str(p) for p in SRC.glob("links_*.json") if "_" not in p.stem[len("links_"):]))
