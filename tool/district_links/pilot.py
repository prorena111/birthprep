# 시·군·구 누리집 출산·육아 쪽에서 혜택별 링크를 찾아 (1) 특정 혜택 링크인지 (2) 로그인
# 없이 그 혜택을 설명하는지 (3) 앱 목록의 어느 항목과 같은지 판정한다. 판정은 TypeSafe(Jev),
# 모으기·거르기는 코드. 키는 요청 머리글에만 쓰고 어디에도 찍지 않는다.
#
# 매달 작업(공개 저장소 .github/workflows/links.yml)에서도 돈다 — 그때는 환경변수로 경로를 준다:
#   LINK_ITEMS  앱 목록(기본 assets/data/local_supports.json, 매달 작업은 v1/local.json)
#   LINK_OUT    판정 결과를 둘 폴더(기본 build/district_links)
#   LINK_CACHE  지난 판정. 있으면 읽고, 끝나면 이번에 쓴 것만 남겨 다시 쓴다 — 링크 글자·쪽
#               본문·보기가 그대로면 TypeSafe에 다시 묻지 않는다.
import json, os, re, sys, time, hashlib, pathlib, threading, urllib3, concurrent.futures as cf
from urllib.parse import urljoin, urlparse
import requests
from bs4 import BeautifulSoup

urllib3.disable_warnings()
ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = pathlib.Path(os.environ.get("LINK_OUT") or ROOT / "build" / "district_links")
OUT.mkdir(parents=True, exist_ok=True)
ITEMS = pathlib.Path(os.environ.get("LINK_ITEMS") or ROOT / "assets" / "data" / "local_supports.json")
CACHE_PATH = os.environ.get("LINK_CACHE")
_old = (json.loads(pathlib.Path(CACHE_PATH).read_text(encoding="utf-8"))
        if CACHE_PATH and pathlib.Path(CACHE_PATH).exists() else {})
OLD_CACHE = {"links": _old.get("links", {}), "pages": _old.get("pages", {})}
NEW_CACHE = {"links": {}, "pages": {}}
HITS = {"links": 0, "pages": 0}
_lock = threading.Lock()
# 키: 환경변수 TYPESAFE_API_KEY, 없으면 OneDrive 맨 위의 「타입세이프 api 키.txt」. 찍지 않는다.
def _clean_key(raw):
    """앞뒤 공백·줄바꿈·BOM·보이지 않는 글자를 걷고 마지막 낱말만(설명 글과 같이 붙여 넣어도)."""
    raw = raw.replace("﻿", "").replace("​", "")
    words = raw.split()
    return words[-1] if words else ""

KEY = _clean_key(os.environ.get("TYPESAFE_API_KEY") or
                 (pathlib.Path.home() / "OneDrive" / "타입세이프 api 키.txt").read_text(encoding="utf-8-sig"))
UA = {"User-Agent": "Mozilla/5.0 (Linux; Android 14; SM-S948N) AppleWebKit/537.36 Chrome/128 Mobile Safari/537.36"}
USAGE = {"input": 0, "output": 0, "calls": 0}

# ---------- TypeSafe ----------
def ask(state, questions):
    body = {"model": "jev-latest", "state": state, "questions": questions}
    for attempt in range(6):
        try:
            r = requests.post("https://api.typesafe.ai/v1/systemone", json=body, timeout=60,
                              headers={"Authorization": "Bearer " + KEY})
        except requests.RequestException:
            time.sleep(2 ** attempt); continue
        if r.status_code in (429, 529, 500, 502, 503):
            time.sleep(2 ** attempt); continue
        if r.status_code != 200:
            raise RuntimeError(f"TypeSafe {r.status_code}: {r.text[:300].replace(KEY, '***')}")
        d = r.json()
        with _lock:
            USAGE["calls"] += 1
            USAGE["input"] += d.get("usage", {}).get("input_tokens", 0)
            USAGE["output"] += d.get("usage", {}).get("output_tokens", 0)
        return d["answers"]
    raise RuntimeError("TypeSafe 재시도 초과")

# ---------- 가져오기 ----------
LOGIN_URL = re.compile(r"login|logon|sso|/member/|signin|auth", re.I)

class _LegacyTLS(requests.adapters.HTTPAdapter):
    """옛 암호 방식만 받는 누리집(성남·안양·용인 — handshake failure)용."""
    def init_poolmanager(self, *a, **kw):
        import ssl
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        ctx.set_ciphers("DEFAULT:@SECLEVEL=0")
        ctx.options |= getattr(ssl, "OP_LEGACY_SERVER_CONNECT", 0x4)
        ctx.minimum_version = ssl.TLSVersion.TLSv1
        kw["ssl_context"] = ctx
        return super().init_poolmanager(*a, **kw)

_legacy = requests.Session()
_legacy.mount("https://", _LegacyTLS())

def fetch(url):
    try:
        r = requests.get(url, headers=UA, timeout=25, verify=False, allow_redirects=True)
    except requests.exceptions.SSLError:
        try:
            r = _legacy.get(url, headers=UA, timeout=25, verify=False, allow_redirects=True)
        except requests.RequestException as e:
            return {"ok": False, "error": type(e).__name__, "final": url}
    except requests.RequestException as e:
        return {"ok": False, "error": type(e).__name__, "final": url}
    enc = r.encoding
    if not enc or enc.lower() in ("iso-8859-1", "ascii"):
        enc = r.apparent_encoding or "utf-8"
    html = r.content.decode(enc, errors="replace")
    soup = BeautifulSoup(html, "html.parser")
    title = (soup.title.get_text(" ", strip=True) if soup.title else "")[:120]
    has_pw = bool(soup.find("input", {"type": "password"}))
    for t in soup(["script", "style", "noscript", "header", "footer", "nav"]):
        t.decompose()
    text = re.sub(r"\s+", " ", soup.get_text(" ", strip=True))
    main = main_text(soup) or text
    return {"ok": r.status_code == 200, "status": r.status_code, "final": r.url, "title": title,
            "html": html, "text": text, "main": main, "has_pw": has_pw,
            "login_url": bool(LOGIN_URL.search(urlparse(r.url).path + "?" + urlparse(r.url).query))}

MENU = re.compile(r"gnb|lnb|snb|menu|nav|header|footer|quick|side|location|breadcrumb|util|allmenu|sitemap|skip|family|banner", re.I)
CONT = re.compile(r"content|contents|cont_|_cont|contArea|article|sub_con|subCon|txt_area|board_view|view", re.I)

def main_text(soup):
    """본문 덩어리 — 메뉴를 걷어내고, 링크 글자가 적고 글이 많은 것."""
    for t in soup.find_all(attrs={"id": MENU}) + soup.find_all(attrs={"class": MENU}):
        if not t.decomposed:
            t.decompose()
    best, score = None, 0
    for t in soup.find_all(["div", "section", "article", "main", "td"]):
        ident = " ".join([t.get("id") or ""] + (t.get("class") or []))
        if not CONT.search(ident):
            continue
        txt = t.get_text(" ", strip=True)
        links = sum(len(a.get_text(" ", strip=True)) for a in t.find_all("a"))
        sc = len(txt) - 2 * links
        if len(txt) >= 150 and sc > score:
            best, score = txt, sc
    return re.sub(r"\s+", " ", best) if best else None

# ---------- 링크 모으기 ----------
SKIP_TEXT = re.compile(r"로그인|회원가입|사이트맵|개인정보|저작권|이용약관|영문|english|전체메뉴|바로가기$|본문|top$|닫기|열기|이전|다음|처음|마지막|인쇄|공유|페이스북|트위터|카카오|블로그|인스타|유튜브|RSS|만족도|담당자|목록|검색", re.I)
BIRTH_WORDS = re.compile(r"임신|임산|출산|출생|산모|산후|산전|육아|아기|아가|영유아|신생아|다둥|다자녀|난임|난관|정관|모자|모성|보육|돌봄|양육|태아|수유|모유|유축|맘|베이비|키즈|어린이|아동|엄마|아빠|부모|예비|가임|엽산|철분|풍진|기저귀|분유|조리|아이")
SECOND = ("go", "seoul", "daegu", "ulsan", "busan", "incheon")

def site_key(host):
    """「www.mapo.go.kr」→「mapo.go.kr」, 「suseong.daegu.kr」→「suseong.daegu.kr」, 「nowon.kr」.
    앱(DistrictLinkBook.siteOf)·export.py와 같은 규칙."""
    parts = host.split(".")
    n = 3 if len(parts) >= 3 and parts[-2] in SECOND else 2
    return ".".join(parts[-n:])

def collect_links(page, base):
    soup = BeautifulSoup(page["html"], "html.parser")
    home = site_key(urlparse(page["final"]).hostname or "")
    seen, out = set(), []
    for a in soup.find_all("a", href=True):
        text = re.sub(r"\s+", " ", a.get_text(" ", strip=True) or a.get("title", "")).strip()
        href = a["href"].strip()
        if not text or len(text) < 2 or len(text) > 45 or href.startswith(("javascript", "#", "mailto", "tel")):
            continue
        url = urljoin(page["final"], href)
        u = urlparse(url)
        if u.scheme not in ("http", "https") or site_key(u.hostname or "") != home:
            continue
        if re.search(r"\.(hwp|hwpx|pdf|xlsx?|docx?|zip|jpg|png)$", u.path, re.I):
            continue
        if SKIP_TEXT.search(text) or not BIRTH_WORDS.search(text):
            continue
        key = url.split("#")[0]
        if key in seen or key == page["final"]:
            continue
        seen.add(key)
        out.append({"text": text, "url": key})
    return out

# ---------- 판정 1: 링크 글자만 보고 ----------
def judge_links(place, hub_title, links):
    def key(l):
        return f"{place}|{l['text']}|{l['url']}"
    res, todo = {}, []
    for l in links:
        if key(l) in OLD_CACHE["links"]:
            res[key(l)] = OLD_CACHE["links"][key(l)]
            with _lock:
                HITS["links"] += 1
        else:
            todo.append(l)
    district = place.split(" ", 1)[-1]
    for i in range(0, len(todo), 25):
        chunk = todo[i:i + 25]
        state = {"district": place, "hub_page_title": hub_title,
                 "links": [{"text": l["text"], "url": l["url"]} for l in chunk]}
        qs = {f"q{j}": {
            "type": "noul",
            "instructions": f"On the {district} district office website, does the link `links[{j}]` "
                            "(judged by its link text, with the url as a hint) lead to a page about ONE specific "
                            "benefit, subsidy, service, class, check-up, rental or voucher that residents can receive "
                            "for pregnancy, childbirth, infants or child-rearing?",
            "criteria": {"true": "The link text names a specific program or service for residents, e.g. 출산양육지원금, "
                                 "산후조리비 지원, 임산부 등록, 유축기 대여, 모유수유 교실, 영유아 건강검진, 난임부부 시술비 지원.",
                         "false": "A generic menu or category (e.g. 보건소, 복지, 건강증진), a notice board, news, "
                                  "a facility directory, a page for staff or businesses, or not about pregnancy/childbirth/infants."}}
            for j in range(len(chunk))}
        ans = ask(state, qs)
        for j, l in enumerate(chunk):
            res[key(l)] = round(ans[f"q{j}"]["noul"], 3)
    with _lock:
        NEW_CACHE["links"].update(res)
    return [{**l, "p_program": res[key(l)]} for l in links]

# ---------- 판정 2: 쪽을 열어서 ----------
def judge_page(place, link, page, options):
    state = {"district": place, "link_text": link["text"],
             "page": {"title": page["title"], "url": page["final"], "text": page["main"][:3000]}}
    qs = {
        "describes": {"type": "noul",
            "instructions": "Does `page.text` explain the program named in `link_text` itself — at least one of who can "
                            "get it, what is given, or how/where to apply — rather than being a menu, list, login screen "
                            "or unrelated page?",
            "criteria": {"true": "The page body explains that specific program (eligibility, benefit or application).",
                         "false": "The page is a login/member screen, error page, main page, menu or list of links, "
                                  "or explains something else."}},
        "in_scope": {"type": "noul",
            "instructions": "Can a pregnant woman, a couple preparing pregnancy, or a family with a baby or child aged 6 or "
                            "younger (before elementary school) use the program in `link_text` / `page`? Answer yes when that "
                            "group is included in the eligible ages, even if older children are also eligible.",
            "criteria": {"true": "The eligible group includes pregnancy, infertility, newborns, infants, toddlers or preschool children (or their parents).",
                         "false": "Only school-age children, teens, adults in general, the elderly, staff, businesses or facilities can use it."}},
        "login": {"type": "noul",
            "instructions": "Does `page` show that the visitor must log in (or verify identity) before the content can be seen?",
            "criteria": {"true": "A login / identity verification is required to view the content.",
                         "false": "The content is publicly visible without logging in."}},
    }
    if options:
        crit = dict(options)
        crit["new"] = "None of the listed programs — this is a different program not in the list."
        qs["same_as"] = {"type": "choice",
            "instructions": "Which listed program is the SAME program as the one described by `link_text` and `page` "
                            "(same benefit from the same provider, even if worded differently)? A program for a different "
                            "target group (e.g. twins only, low-income only, third child) is a different program.",
            "criteria": crit}
    ans = ask(state, qs)
    out = {"p_describes": round(ans["describes"]["noul"], 3), "p_login": round(ans["login"]["noul"], 3),
           "p_scope": round(ans["in_scope"]["noul"], 3)}
    if options:
        out["same_as"] = ans["same_as"]["choice"]
        out["same_conf"] = round(ans["same_as"]["confidence"], 3)
        out["same_probs"] = ans["same_as"].get("probabilities", {})
    return out

def verify_same(place, link, page, cand_name):
    """고른 짝이 정말 같은 사업인가 — 예/아니오로 한 번 더(보기가 여럿이면 표가 갈라져 확신도가 낮다)."""
    state = {"district": place, "link_text": link["text"], "candidate": cand_name,
             "page": {"title": page["title"], "text": page["main"][:3000]}}
    a = ask(state, {"same": {"type": "noul",
        "instructions": "Is the program described by `link_text` and `page` the same program as `candidate` — the same "
                        "benefit or service for the same target group, possibly named differently or run locally?",
        "criteria": {"true": "Same program (e.g. the district health center's page for that program).",
                     "false": "A different program, a different target group (e.g. only low-income, only twins, third child), "
                              "or only loosely related."}}})
    return round(a["same"]["noul"], 3)

# ---------- 앱 목록 (같은 사업은 한 묶음) ----------
items = json.load(open(ITEMS, encoding="utf-8"))["items"]
CENTRAL = {"S01": "임신·출산 진료비 지원(국민행복카드)", "S02": "첫만남이용권", "S03": "부모급여",
           "S04": "아동수당", "S09": "고위험 임산부 의료비 지원", "S05": "출산가구 전기요금 할인",
           "S08": "출산가구 도시가스 요금 경감", "S06": "산모·신생아 건강관리 지원(산후도우미 바우처)",
           "S07": "육아휴직 급여", "S10": "임산부 친환경농산물 꾸러미", "S11": "영유아 건강검진"}
HC = {"H1": "임신 사전건강관리(가임기 남녀 검사)", "H2": "엽산제 지원", "H3": "임산부 등록·모자보건수첩",
      "H4": "임산부 철분제 지원", "H5": "산전·산후 우울 검사·상담", "H6": "생애초기 건강관리 가정방문"}
SIDO_PREFIX = ("서울", "부산", "대구", "인천", "광주", "대전", "울산", "세종", "경기", "강원", "충청", "충북", "충남",
               "전북", "전라", "전남", "경상", "경북", "경남", "제주")
NOISE = re.compile(r"\([^)]*\)|\[[^\]]*\]|［[^］]*］|〔[^〕]*〕|지원사업|지원|사업|서비스|안내|운영|신청|제공|[\s·‧ㆍ⋅,./\-_「」『』]")

def norm(name, org):
    n = NOISE.sub("", name)
    for w in [org.split()[-1]] + ["서울특별시", "서울시"]:
        n = n.replace(w, "")
    return n or name

def bigrams(s):
    s = re.sub(r"\s", "", s)
    return {s[i:i + 2] for i in range(len(s) - 1)}

def groups_for(sido, district):
    """그 구 + 그 시·도 + 나라(정부24·복지로) 항목을 이름으로 묶는다. 같은 사업이 두세 줄씩 있어
    짝짓기 표가 갈라지던 것(시범 검토 102건)을 막는다."""
    orgs = {f"{sido} {district}", sido}
    rank = {"구": 0, "시·도": 1, "나라": 2}
    gs = {}
    for it in items:
        if it["org"] in orgs or not it["org"].startswith(SIDO_PREFIX):
            level = "구" if it["org"] == f"{sido} {district}" else ("시·도" if it["org"] == sido else "나라")
            g = gs.setdefault(norm(it["name"], it["org"]), {"level": level, "names": [], "ids": [], "orgs": set()})
            if rank[level] < rank[g["level"]]:
                g["level"] = level
            g["names"].append(it["name"]); g["ids"].append(it["id"]); g["orgs"].add(it["org"])
    return list(gs.values())

def page_options(groups, link_text, title):
    """나라 제도 17개 + 이름이 가장 비슷한 묶음 14개만 보기로 준다(입력 토큰을 줄인다)."""
    q = bigrams(link_text + title)
    scored = sorted(groups, key=lambda g: -max(len(q & bigrams(n)) / (len(bigrams(n)) or 1) for n in g["names"]))
    opts, ref = {}, {}
    for k, v in {**CENTRAL, **HC}.items():
        opts[k] = f"{v} (나라 제도)"; ref[k] = {"key": k, "name": v, "level": "나라 제도", "ids": []}
    for i, g in enumerate(scored[:14]):
        name = min(g["names"], key=len)
        opts[f"g{i}"] = f"{name} ({g['level']}, {'/'.join(sorted(g['orgs']))})"
        ref[f"g{i}"] = {"key": f"g{i}", "name": name, "level": g["level"], "ids": g["ids"]}
    return opts, ref

def classify(row):
    if "p_describes" not in row: return "broken"
    if row.get("code_login") or row["p_login"] >= 0.5: return "login"
    if row["p_describes"] < 0.7: return "not_page"
    if row["p_scope"] < 0.5: return "out_scope"
    m, v = row.get("match"), row.get("p_same")
    if m:
        if v is None or v < 0.8: return "review"
        return "national" if m["level"] == "나라 제도" else "match"
    return "new" if row.get("same_conf", 0) >= 0.6 else "review"

def judge_cached(place, link, pg, row, groups):
    """쪽 판정 — 링크 글자·쪽 본문 지문·보기가 지난번과 같으면 지난 판정을 쓴다."""
    opts, ref = page_options(groups, link["text"], pg.get("title") or "")
    sig = hashlib.sha1("\n".join(f"{k}={v}" for k, v in opts.items()).encode()).hexdigest()[:12]
    ck = f"{link['text']}|{pg['final']}|{row['hash']}|{sig}"
    got = OLD_CACHE["pages"].get(ck)
    if got is None:
        j = judge_page(place, link, pg, opts)
        got = {k: j[k] for k in ("p_describes", "p_login", "p_scope")}
        if "same_as" in j:
            got["same_as"], got["same_conf"] = j["same_as"], j["same_conf"]
        probs = sorted(((v, k) for k, v in (j.get("same_probs") or {}).items() if k != "new"), reverse=True)
        chosen = j.get("same_as") not in (None, "new")
        if probs and (chosen or probs[0][0] >= 0.15):
            # 「새 것」을 골랐어도 가장 그럴듯한 보기를 한 번 확인한다
            top = j["same_as"] if chosen else probs[0][1]
            v = verify_same(place, link, pg, ref[top]["name"])
            if v >= 0.5:
                got["match_key"], got["p_same"] = top, v
            elif chosen:
                got["p_same"], got["rejected_match"] = v, ref[top]["name"]
    else:
        with _lock:
            HITS["pages"] += 1
    with _lock:
        NEW_CACHE["pages"][ck] = got
    row.update({k: v for k, v in got.items() if k != "match_key"})
    if got.get("match_key") in ref:
        row["match"] = ref[got["match_key"]]

def run_district(site):
    sido, d = site["sido"], site["district"]
    place = f"{sido} {d}"
    rec = {"sido": sido, "district": d, "hub": site["birth"], "hub_title_saved": site.get("birth_title")}
    hub = fetch(site["birth"])
    rec["hub_status"] = {k: hub.get(k) for k in ("ok", "status", "final", "title", "has_pw", "login_url", "error")}
    if not hub.get("ok"):
        rec["links"] = []
        return rec
    links = collect_links(hub, site["birth"])
    rec["n_candidates"] = len(links)
    judged = judge_links(place, hub["title"], links) if links else []
    groups = groups_for(sido, d)
    found, seen_final = [], set()
    for l in judged:
        if l["p_program"] < 0.5:
            continue
        time.sleep(0.3)
        pg = fetch(l["url"])
        if pg.get("final") in seen_final:
            continue
        seen_final.add(pg.get("final"))
        row = {**l, "final": pg.get("final"), "status": pg.get("status"), "title": pg.get("title"),
               "code_login": bool(pg.get("has_pw") or pg.get("login_url"))}
        if pg.get("ok") and len(pg.get("text", "")) > 80:
            row["hash"] = hashlib.sha1((pg.get("main") or "").encode()).hexdigest()[:12]
            judge_cached(place, l, pg, row, groups)
        row["cls"] = classify(row)
        found.append(row)
    rec["links"] = found
    rec["rejected"] = [l for l in judged if l["p_program"] < 0.5]
    return rec

def run_sites(sites, workers=5):
    results = []
    with cf.ThreadPoolExecutor(workers) as ex:
        futs = {ex.submit(run_district, s): s for s in sites}
        for f in cf.as_completed(futs):
            s = futs[f]
            try:
                r = f.result()
            except Exception as e:
                r = {"sido": s["sido"], "district": s["district"], "error": str(e).replace(KEY, "***"), "links": []}
            results.append(r)
            print(r["sido"], r["district"], "후보", r.get("n_candidates"), "통과", len(r.get("links", [])),
                  r.get("error", ""), flush=True)
    return sorted(results, key=lambda r: (r["sido"], r["district"]))

if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--sido", default="서울특별시")
    ap.add_argument("--all", action="store_true", help="전국 — 시·도마다 links_<시도>.json")
    ap.add_argument("--workers", type=int, default=5)
    ap.add_argument("districts", nargs="*")
    a = ap.parse_args()
    sites = [x for x in json.load(open(ROOT / "tool" / "local_sites.json", encoding="utf-8"))
             if x["district"] and x.get("birth") and (a.all or x["sido"] == a.sido)]
    if a.districts:
        sites = [s for s in sites if s["district"] in a.districts]
    # 링크 모으기에 안 맞는 출발 쪽은 hubs.json이 바꾼다(앱의 누리집 단추는 그대로).
    hubs = json.loads((pathlib.Path(__file__).parent / "hubs.json").read_text(encoding="utf-8"))
    sites = [{**s, "birth": hubs.get(f"{s['sido']} {s['district']}", s["birth"])} for s in sites]
    results = run_sites(sites, a.workers)
    for sido in sorted({r["sido"] for r in results}):
        part = [r for r in results if r["sido"] == sido]
        name = f"links_{sido}" + ("_" + "_".join(a.districts) if a.districts else "") + ".json"
        usage = USAGE if not a.all else {"input": 0, "output": 0, "calls": 0}
        (OUT / name).write_text(json.dumps({"usage": usage, "results": part}, ensure_ascii=False, indent=1),
                                encoding="utf-8")
    if CACHE_PATH:
        # 이번에 쓴 판정만 남긴다(없어진 쪽·바뀐 쪽은 버린다).
        pathlib.Path(CACHE_PATH).write_text(json.dumps(NEW_CACHE, ensure_ascii=False, separators=(",", ":")),
                                            encoding="utf-8")
    (OUT / "usage.json").write_text(json.dumps({**USAGE, "hits": HITS}), encoding="utf-8")
    print("USAGE", USAGE, "약 $%.3f" % (USAGE["input"] / 1e6 * 0.042), "· 다시 안 물은 것", HITS)
