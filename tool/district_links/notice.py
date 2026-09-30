# 매달 커뮤니티 공지 — 시·군·구 누리집 자동 확인 결과와 **확인하지 못한 곳**(사장님 2026-09-30).
#   LINK_OUT=build/district_links python tool/district_links/notice.py --root .            (글만 찍기)
#   ... notice.py --root . --post   (NOTICE_TOKEN이 있으면 서버 함수 publish_monthly_notice로 올리기)
#
# 글은 1,000자 안(커뮤니티 글 제한). 넘치면 목록 끝을 「외 N곳」으로 줄인다.
import collections, datetime, glob, json, os, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = pathlib.Path(os.environ.get("LINK_OUT") or ROOT / "build" / "district_links")
SUPABASE_URL = "https://jnbyotcihrmxefcrzvoq.supabase.co"
# 앱에 든 공개 키(lib/data/account/account_config.dart) — 비밀이 아니다.
PUBLISHABLE = "sb_publishable_E07SZnn87JLI7yYMIf--Ew_JTcv3Eih"
SHORT = {"서울특별시": "서울", "경기도": "경기", "부산광역시": "부산", "대구광역시": "대구", "인천광역시": "인천",
         "전남광주통합특별시": "전남광주", "대전광역시": "대전", "울산광역시": "울산", "세종특별자치시": "세종",
         "강원특별자치도": "강원", "충청북도": "충북", "충청남도": "충남", "전북특별자치도": "전북",
         "경상북도": "경북", "경상남도": "경남", "제주특별자치도": "제주"}
LIMIT = 1000

def results():
    rows = []
    for f in sorted(glob.glob(str(OUT / "links_*.json"))):
        if "_" in pathlib.Path(f).stem[len("links_"):]:
            continue  # 몇 곳만 돌린 파일
        rows += json.loads(pathlib.Path(f).read_text(encoding="utf-8"))["results"]
    return rows

def group(places):
    """[(시도, 시군구)] → 「경남 거제시·남해군, 경기 여주시」."""
    by = collections.OrderedDict()
    for sido, gu in sorted(places, key=lambda x: (list(SHORT).index(x[0]) if x[0] in SHORT else 99, x[1])):
        by.setdefault(SHORT.get(sido, sido), []).append(gu)
    return [f"{s} {'·'.join(g)}" for s, g in by.items()]

def body(root, today):
    rs = results()
    table = json.loads((pathlib.Path(root) / "v1" / "links.json").read_text(encoding="utf-8"))
    # 표에 링크나 「더 찾은 것」이 하나라도 있는 곳
    covered = {k.split("|")[0] for k in table.get("links", {})} | set(table.get("found", {}))
    unreached, nolinks = [], []
    for r in rs:
        h = r.get("hub_status") or {}
        key = (r["sido"], r["district"])
        if not h.get("ok"):
            unreached.append(key)          # 이번 달 안 열림 — 지난달 것을 둔다
        elif f"{r['sido']} {r['district']}" not in covered:
            nolinks.append(key)            # 열렸지만 쓸 만한 쪽을 못 찾음
    ok = len(rs) - len(unreached) - len(nolinks)
    n_links = len(table.get("links", {}))
    n_found = sum(len(v) for v in table.get("found", {}).values())
    month = f"{today.month}월"

    head = [
        f"[{month}] 우리 동네 지원 자동 확인 결과",
        "",
        f"매달 1일 전국 시·군·구 누리집 {len(rs)}곳을 자동으로 확인해, 지원 탭의 「○○ 안내 보기」와 "
        "「누리집에서 더 찾은 것」을 고쳐요.",
        "",
        f"■ 확인한 곳 {ok}곳 · 안내 링크 {n_links:,}개 · 정부24에 없는 우리 동네 사업 {n_found}건",
    ]
    tail = [
        "",
        "이 지역에 사시면 보건소나 시·군·구청 누리집·전화로 한 번 확인해 주세요. 금액과 대상은 바뀔 수 있으니 "
        "신청 전에 원문을 꼭 확인해 주세요. 이 앱은 정부 기관이 아니에요.",
    ]
    sections = []
    if unreached:
        sections.append((f"■ 이번 달 누리집이 열리지 않은 곳 {len(unreached)}곳 — 지난달 정보를 그대로 보여 드려요",
                         group(unreached)))
    if nolinks:
        sections.append((f"■ 자동으로 확인할 수 없는 곳 {len(nolinks)}곳 — 안내 링크가 없어요", group(nolinks)))

    def render(cut):
        out = list(head)
        for title, items in sections:
            shown = items[:cut] if cut is not None else items
            out += ["", title] + [f"· {x}" for x in shown]
            if len(items) > len(shown):
                out.append(f"· 외 {len(items) - len(shown)}개 시·도")
        if not sections:
            out += ["", "■ 이번 달은 모든 곳을 확인했어요."]
        return "\n".join(out + (tail if sections else []))

    text = render(None)
    cut = 12
    while len(text) > LIMIT and cut > 0:
        text = render(cut)
        cut -= 1
    return text[:LIMIT]

def post(text, key):
    import requests
    token = (os.environ.get("NOTICE_TOKEN") or "").strip()
    if not token:
        print("NOTICE_TOKEN이 없어 공지를 올리지 않았다", file=sys.stderr)
        return False
    r = requests.post(f"{SUPABASE_URL}/rest/v1/rpc/publish_monthly_notice", timeout=30,
                      headers={"apikey": PUBLISHABLE, "Authorization": f"Bearer {PUBLISHABLE}",
                               "Content-Type": "application/json"},
                      json={"p_token": token, "p_key": key, "p_body": text})
    if r.status_code != 200:
        print(f"공지 올리기 실패 {r.status_code}: {r.text[:200].replace(token, '***')}", file=sys.stderr)
        sys.exit(4)
    print(f"공지 올림 {key} · {r.text.strip()}")
    return True

if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".")
    ap.add_argument("--post", action="store_true")
    a = ap.parse_args()
    today = datetime.date.today()
    text = body(a.root, today)
    print(text)
    print(f"\n({len(text)}자)")
    rs = results()
    unreached = sum(1 for r in rs if not (r.get("hub_status") or {}).get("ok"))
    # 누리집이 3할 넘게 안 열린 날(해외 서버에서 한꺼번에 늦을 때)에는 공지를 미루고 다음 날 다시 돈다 —
    # 「100곳이 안 열렸다」는 공지는 사실과 달라 보인다. 매달 1·2·3일 중 3일째나 손으로 돌린 때는 올린다.
    busy = rs and unreached > len(rs) * 0.3
    last_try = today.day >= 3 or os.environ.get("SCHEDULED") != "true"
    if busy and not last_try:
        print(f"\n누리집 {unreached}/{len(rs)}곳이 안 열려 공지를 미룬다 — 내일 다시 돈다")
        (OUT / "retry_tomorrow").write_text("1", encoding="utf-8")
    elif a.post:
        post(text, f"links-{today:%Y-%m}")
