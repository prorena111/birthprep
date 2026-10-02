# 시·군·구마다 출발 쪽을 넓힌다 — 사장님 2026-10-02 「마포구처럼 빠진 것이 많을 것 같다. 전체적으로
# 확인해 줘, 타입세이프를 사용해서」. 마포구는 출발 쪽이 보건소 「임산부 건강관리」 하나라 구청의
# 「영유아복지」·「베이비시터하우스 어린이집」 같은 쪽을 아예 못 봤다.
#
# 구마다 누리집 첫 화면·사이트맵·보건소 쪽(find_hub.candidates)과 지금 출발 쪽에서 임신·출산·영유아·
# 보육·아동 메뉴 링크를 모으고, TypeSafe(Jev)에 「주민이 받는 임신~만 6세 지원을 모아 두었거나 설명하는
# 쪽인가」를 묻는다. 높은 것부터 최대 MAX_EXTRA개를 더 출발 쪽으로 hubs.json에 적는다(--apply).
# seeds·sections·render로 손본 곳은 건드리지 않는다. local_sites.json의 birth(앱 누리집 단추)도 그대로.
#
#   python tool/district_links/widen_hubs.py                 # 전국, 결과만 build/district_links/widen.json
#   python tool/district_links/widen_hubs.py --apply         # hubs.json에 적기
#   python tool/district_links/widen_hubs.py 서울특별시 마포구  # 몇 곳만
import json, re, sys, pathlib, concurrent.futures as cf
from urllib.parse import urlparse
import pilot, find_hub

HERE = pathlib.Path(__file__).parent
MAX_EXTRA = 8
CUT = 0.6
CAT = re.compile(r"임신|임산|출산|출생|모자|모성|육아|보육|영유아|유아|산모|산후|난임|아동|어린이|다자녀|아이|아기|"
                 r"돌봄|모유|신생아|가족센터|장난감")
SKIP = re.compile(r"공지|게시판|뉴스|소식|보도|채용|입찰|고시|공고|조직|부서|직원|청소년|노인|어르신|청년|"
                  r"사이트맵|전체메뉴|로그인|회원|급식|교육청|학교|위원회|조례|통계|예산|민원서식|자료실|포토|영상")

def seen_urls():
    """지난 판정(links_<시도>.json)에서 이미 연 쪽 — 다시 고르지 않는다."""
    seen = {}
    for f in pilot.OUT.glob("links_*.json"):
        if "_" in f.stem[len("links_"):] or "before" in f.stem:
            continue
        for r in json.loads(f.read_text(encoding="utf-8"))["results"]:
            place = f"{r['sido']} {r['district']}"
            for l in r.get("links", []):
                for u in (l.get("url"), l.get("final")):
                    if u:
                        seen.setdefault(place, set()).add(u.split("#")[0])
    return seen

SEEN = seen_urls()

def candidates(site, hubs):
    found = {}
    try:
        found.update(find_hub.candidates(site))
    except Exception:
        pass
    for h in hubs:
        page = pilot.fetch(h)
        if page.get("ok"):
            key = pilot.site_key(urlparse(page["final"]).hostname or "")
            for u, t in find_hub.links_of(page, key).items():
                found.setdefault(u, t)
    have = {h.split("#")[0] for h in hubs} | SEEN.get(f"{site['sido']} {site['district']}", set())
    out = []
    for u, t in found.items():
        if u in have or not CAT.search(t) or SKIP.search(t):
            continue
        if re.search(r"\.(hwp|hwpx|pdf|xlsx?|docx?|zip|jpg|png)$", urlparse(u).path, re.I):
            continue
        out.append({"text": t, "url": u})
    return out[:150]

def judge(place, links):
    district = place.split(" ", 1)[-1]
    res = []
    for i in range(0, len(links), 25):
        chunk = links[i:i + 25]
        state = {"district": place, "links": [{"text": l["text"], "url": l["url"]} for l in chunk]}
        qs = {f"q{j}": {
            "type": "noul",
            "instructions": f"On the {district} local government website, does `links[{j}]` (judged by its text, "
                            "url as a hint) lead to a page where RESIDENTS learn about support they can receive for "
                            "pregnancy, childbirth, infants or children under 7 — either a menu/section page gathering "
                            "several such programs (e.g. 모자보건, 영유아 건강관리, 출산·보육 지원, 영유아복지, 아이돌봄) "
                            "or one specific program (e.g. 출산축하금, 장난감 대여, 구립 어린이집 시간연장)?",
            "criteria": {"true": "A page residents use to find or apply for pregnancy/birth/infant/childcare support.",
                         "false": "News, notices, boards, facility directories only, staff/business pages, "
                                  "programs for teenagers/elderly/adults only, or not about pregnancy/children under 7."}}
            for j in range(len(chunk))}
        ans = pilot.ask(state, qs)
        res += [{**l, "p": round(ans[f"q{j}"]["noul"], 3)} for j, l in enumerate(chunk)]
    return res

def run(site, hubs):
    place = f"{site['sido']} {site['district']}"
    links = candidates(site, hubs)
    judged = judge(place, links) if links else []
    pick = sorted([l for l in judged if l["p"] >= CUT], key=lambda l: -l["p"])[:MAX_EXTRA]
    return {"place": place, "hubs": hubs, "n": len(links), "picked": pick,
            "judged": sorted(judged, key=lambda l: -l["p"])[:30]}

if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    apply = "--apply" in sys.argv
    sites = [x for x in json.load(open(pilot.ROOT / "tool" / "local_sites.json", encoding="utf-8"))
             if x["district"] and x.get("birth")]
    if args:
        sites = [s for s in sites if s["sido"] == args[0] and (len(args) == 1 or s["district"] in args[1:])]
    hubs_path = HERE / "hubs.json"
    hubs = json.loads(hubs_path.read_text(encoding="utf-8"))
    todo = []
    for s in sites:
        h = hubs.get(f"{s['sido']} {s['district']}")
        if isinstance(h, dict):
            continue  # seeds·sections·render — 손본 곳
        todo.append((s, h if isinstance(h, list) else [h or s["birth"]]))
    out = []
    with cf.ThreadPoolExecutor(6) as ex:
        futs = {ex.submit(run, s, h): s for s, h in todo}
        for f in cf.as_completed(futs):
            s = futs[f]
            try:
                r = f.result()
            except Exception as e:
                r = {"place": f"{s['sido']} {s['district']}", "error": str(e).replace(pilot.KEY, "***"), "picked": []}
            out.append(r)
            print(r["place"], "후보", r.get("n"), "고름", len(r["picked"]), r.get("error", ""), flush=True)
    out.sort(key=lambda r: r["place"])
    name = "widen.json" if not args else "widen_" + "_".join(args) + ".json"
    (pilot.OUT / name).write_text(json.dumps({"usage": pilot.USAGE, "results": out}, ensure_ascii=False, indent=1),
                                  encoding="utf-8")
    if apply:
        for r in out:
            if r["picked"]:
                hubs[r["place"]] = r["hubs"] + [l["url"] for l in r["picked"] if l["url"] not in r["hubs"]]
        hubs_path.write_text(json.dumps(hubs, ensure_ascii=False, indent=1) + "\n", encoding="utf-8", newline="\n")
    print("USAGE", pilot.USAGE, "약 $%.3f" % (pilot.USAGE["input"] / 1e6 * 0.042))
