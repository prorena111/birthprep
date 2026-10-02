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
OLD_CACHE = {"links": _old.get("links", {}), "pages": _old.get("pages", {}), "notes": _old.get("notes", {})}
NEW_CACHE = {"links": {}, "pages": {}, "notes": {}}
HITS = {"links": 0, "pages": 0, "notes": 0}
# 쪽 본문에서 「받는 것·대상·신청」 줄을 골라 앱에 그대로 보여 줄 시·도(--notes, 전국은 all). 서울 시범 뒤 전국(2026-10-01).
NOTES_SIDO = set()
_lock = threading.Lock()
# 키: 환경변수 TYPESAFE_API_KEY, 없으면 OneDrive 맨 위의 「타입세이프 api 키.txt」. 찍지 않는다.
def _clean_key(raw):
    """앞뒤 공백·줄바꿈·BOM·보이지 않는 글자를 걷고 마지막 낱말만(설명 글과 같이 붙여 넣어도)."""
    raw = raw.replace(chr(0xFEFF), "").replace(chr(0x200B), "")
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

def fetch(url, _again=True):
    try:
        r = requests.get(url, headers=UA, timeout=25, verify=False, allow_redirects=True)
    except (requests.exceptions.ConnectTimeout, requests.exceptions.ReadTimeout):
        # 해외(GitHub 서버)에서 부르면 누리집이 가끔 늦다 — 조금 쉬었다가 한 번 더.
        if not _again:
            return {"ok": False, "error": "Timeout", "final": url}
        time.sleep(5)
        return fetch(url, _again=False)
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
    final, status = r.url, r.status_code
    if status == 200 and len(html) < 2000:
        # 프로그램에는 빈 쪽(스크립트로 브라우저인지 보는 쪽)만 주는 누리집 — 강북구 등.
        # 화면 없는 크롬으로 다시 연다(playwright가 없으면 그대로).
        got = _browser_html(url)
        if got:
            final, html = got
    soup = BeautifulSoup(html, "html.parser")
    title = (soup.title.get_text(" ", strip=True) if soup.title else "")[:120]
    has_pw = bool(soup.find("input", {"type": "password"}))
    for t in soup(["script", "style", "noscript", "header", "footer", "nav"]):
        t.decompose()
    text = re.sub(r"\s+", " ", soup.get_text(" ", strip=True))
    main = main_text(soup) or text
    return {"ok": status == 200, "status": status, "final": final, "title": title,
            "html": html, "text": text, "main": main, "has_pw": has_pw,
            "login_url": bool(LOGIN_URL.search(urlparse(final).path + "?" + urlparse(final).query))}

_tl = threading.local()

def _browser_html(url):
    """화면 없는 크롬으로 연 쪽(주소, html). 스레드마다 브라우저 하나. 못 열면 None."""
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        return None
    try:
        if getattr(_tl, "browser", None) is None:
            _tl.pw = sync_playwright().start()
            _tl.browser = _tl.pw.chromium.launch()
        page = _tl.browser.new_page(user_agent=UA["User-Agent"], ignore_https_errors=True)
        try:
            page.goto(url, wait_until="networkidle", timeout=45000)
            return page.url, page.content()
        finally:
            page.close()
    except Exception:
        return None

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

# 사업 이름이 아니라 그 안의 항목 제목(「1) 지원대상 :」「신청방법」「구비서류」) — 이것으로 자르면 사업이
# 조각난다(고양·화성, 2026-09-30).
FIELD = re.compile(r"^\s*(\d+\s*[).]|[①-⑳]|[가-하]\s*[.)])|:|^\s*(지원|신청|구비|문의|대상|내용|방법|기간|기한|금액|"
                   r"절차|선정|제외|유의|담당|접수|제출|처리|참고|근거|구분|사업|개요|목적|혜택|카드|지급|자격|서류|"
                   r"안내|주의|기타|관련|문의처|연락처)\s*(대상|내용|방법|기간|기한|금액|절차|기준|사항|서류|처|개요|"
                   r"목적|혜택|시기|요건|장소|부서)?\s*$")

def sections_of(html):
    """한 쪽에 여러 사업을 풀어 적은 누리집(담양군 등) — 가장 많이 쓰인 제목 태그(h3·h4·h5)로 본문을
    잘라 [(제목, 그 아래 글)]. 제목에서 다음 제목 앞까지, 3,000자까지."""
    soup = BeautifulSoup(html, "html.parser")
    for t in soup(["script", "style", "noscript", "header", "footer", "nav"]):
        t.decompose()
    cands = {tag: [x for x in (h.get_text(" ", strip=True) for h in soup.find_all(tag))
                   if 3 <= len(x) <= 45 and not FIELD.search(x)]
             for tag in ("h3", "h4", "h5")}
    titles = max(cands.values(), key=len)
    text = re.sub(r"\s+", " ", soup.get_text(" ", strip=True))
    out, pos = [], 0
    for i, t in enumerate(titles):
        a = text.find(t, pos)
        if a < 0:
            continue
        b = text.find(titles[i + 1], a + len(t)) if i + 1 < len(titles) else -1
        out.append((t, text[a:(b if b > a else a + 3000)][:3000]))
        pos = a + len(t)
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

# ---------- 판정 3: 쪽 본문에서 앱에 옮길 줄 고르기 (서울 시범) ----------
# AI는 글을 쓰지 않는다 — 누리집 본문을 줄로 나누고(코드), 줄마다 「받는 것·대상·신청·기타」를
# 고르게만 한다(TypeSafe) — 받는 것 6·대상 2·신청 2줄까지. 앱에는 고른 줄을 글자 그대로 보여 주고 원문 단추를 붙인다.
BLOCK = ["p", "li", "dd", "dt", "h2", "h3", "h4", "h5", "h6", "td", "th", "div", "caption", "dl", "ul", "ol",
         "table", "tr", "section", "article", "blockquote"]
BULLET = re.compile(r"^[\s\-·•∙◦○●■□▪▶▷►★☆※♣♠◆◇→⇒>✔✓☞]+")
KINDS = ("benefit", "who", "apply")
NOTE_MAX = {"benefit": 6, "who": 2, "apply": 2}
# 운영 세부 — 시간·전화번호·수령 요일·계산 예시·서식 내려받기. 이런 줄은 원문에서 본다.
OPERATIONAL = re.compile(r"☎|\d{2,4}\s*-\s*\d{3,4}\s*-\s*\d{4}|\d{1,2}\s*:\s*\d{2}|\d{1,2}시\s*~|오전|오후|"
                         r"토요일|일요일|공휴일|^예\s*\)|⇒\s*지원대상|=\s*\d|다운로드|바로가기|https?://|\.hwp|\.pdf|<[a-zA-Z/]")

def page_lines(html):
    """본문 덩어리를 줄로 — 안에 다른 덩어리가 없는 칸(li·p·td…)마다 한 줄, <br>은 줄바꿈.
    한글이 있고 6~160자인 줄만, 같은 줄은 한 번, 앞에서부터 80줄."""
    soup = BeautifulSoup(html, "html.parser")
    for t in soup(["script", "style", "noscript", "header", "footer", "nav", "form", "button", "select"]):
        t.decompose()
    for t in soup.find_all(attrs={"id": MENU}) + soup.find_all(attrs={"class": MENU}):
        if not t.decomposed:
            t.decompose()
    best, score = None, 0
    for t in soup.find_all(["div", "section", "article", "main", "td"]):
        ident = " ".join([t.get("id") or ""] + (t.get("class") or []))
        if not CONT.search(ident):
            continue
        txt = t.get_text(" ", strip=True)
        sc = len(txt) - 2 * sum(len(a.get_text(" ", strip=True)) for a in t.find_all("a"))
        if len(txt) >= 150 and sc > score:
            best, score = t, sc
    root = best or soup.body or soup
    for br in root.find_all("br"):
        br.replace_with("\n")
    out, seen = [], set()
    for el in root.find_all(BLOCK):
        if el.find(BLOCK):
            # 안에 목록을 품은 칸은 제 글만(「임신초기검사 : 서초구민…」 + 아래 목록) — 목록 줄은 따로 나온다.
            text = "".join(c if isinstance(c, str) else c.get_text(" ")
                           for c in el.children if isinstance(c, str) or (c.name not in BLOCK and not c.find(BLOCK)))
        else:
            text = el.get_text(" ")
        for part in text.split("\n"):
            line = BULLET.sub("", re.sub(r"\s+", " ", part)).strip()
            if not (6 <= len(line) <= 160) or line in seen or not re.search(r"[가-힣]", line):
                continue
            seen.add(line)
            out.append(line)
    return out[:80]

def pick_notes(place, program, title, lines):
    """줄마다 종류를 골라 [[종류, 줄]] — 종류마다 확신 높은 것부터 NOTE_MAX줄, 본문 차례대로."""
    ck = hashlib.sha1(json.dumps([program, lines], ensure_ascii=False).encode()).hexdigest()[:16]
    got = OLD_CACHE["notes"].get(ck)
    if got is not None:
        with _lock:
            HITS["notes"] += 1
            NEW_CACHE["notes"][ck] = got
        return got
    picks = []
    # 쪽의 줄을 25줄씩 준다(쪽 전체 80줄을 한꺼번에 주면 답이 0.5 근처로 몰렸다 — 2026-10-01 시범).
    for i in range(0, len(lines), 25):
        state = {"district": place, "program": program, "page_title": title, "lines": lines[i:i + 25]}
        chunk = range(len(state["lines"]))
        qs = {f"l{j}": {"type": "choice",
            "instructions": f"`lines[{j}]` is one line copied from the {place} website page about `program`. If this "
                            "single line were shown alone as a bullet under the heading `program` in an app for "
                            "pregnant women and parents, what would it tell them?",
            "criteria": {
                "benefit": "What residents actually get from the program: an item, a money amount, a free test or "
                           "vaccination, a service, a quantity or duration, a discount or rental — stated concretely "
                           "and understandable on its own.",
                "who": "Who can get it: residence, pregnancy weeks, the child's age, birth order, income or other "
                       "eligibility conditions.",
                "apply": "How, where or when to apply or receive it, or what to bring.",
                "other": "Anything else: a bare heading or category name, opening hours, phone numbers, staff or "
                         "department names, legal basis, general notices, menu text, content about a different "
                         "program, or a fragment that cannot be understood alone."}}
            for j in chunk}
        # 종류와 따로 「혼자 보여도 쓸모 있는 줄인가」 — 수령 요일·택배 반납·대수·계산 예시 같은 운영
        # 세부와 「16주~20주」 같은 표 머리 조각이 섞이던 것(서초구 시범, 2026-10-01)을 거른다.
        for j in chunk:
            qs[f"k{j}"] = {"type": "noul",
                "instructions": f"Shown alone as a bullet under the heading `program` in an app, does `lines[{j}]` give "
                                "a pregnant woman or parent a concrete, useful fact — something they can get (a named "
                                "item, test, vaccination, service, class, rental or money), who qualifies, or how to "
                                "apply — that is clear without the rest of the page?",
                "criteria": {"true": "Concrete and understandable alone, e.g. 「엽산제 지원 : 거주지 제한 없음, 최대 2개월 "
                                     "분량」, 「대상 : 출산 후 3개월 이내 서초구 산모」, 「신청방법 : 인터넷 사전 예약」.",
                             "false": "A heading or fragment (「16주~20주」, 「기본 30일」), opening hours, phone numbers, "
                                      "pickup or return rules, stock counts, product models, an example calculation, a "
                                      "warning, or something about a different program."}}
        ans = ask(state, qs)
        for j in chunk:
            line, a = state["lines"][j], ans[f"l{j}"]
            p = (a.get("probabilities") or {}).get(a["choice"], a.get("confidence", 0))
            key = ans[f"k{j}"]["noul"]
            # 8자 미만은 표 머리 조각(「16주~분만전」), 시간·전화·수령 요일·계산 예시는 코드로 뺀다.
            if (a["choice"] in KINDS and p >= 0.5 and key >= 0.35 and len(line) >= 8
                    and not OPERATIONAL.search(line)):
                picks.append((key, i + j, a["choice"], line))
    out = []
    for kind in KINDS:
        # 꼭 알아야 할 줄부터 골라 본문 차례로 놓는다.
        best = sorted((x for x in picks if x[2] == kind), key=lambda x: -x[0])[:NOTE_MAX[kind]]
        out += [[kind, line] for _, _, _, line in sorted(best, key=lambda x: x[1])]
    with _lock:
        NEW_CACHE["notes"][ck] = out
    return out

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

def sec_lines(body, title=""):
    """제목으로 자른 칸의 글(공백이 하나로 눌린 글)을 줄로 — 글머리표·「1)」·문장 끝, 그리고
    「지원대상:」「지원내용:」「문의:」 같은 이름표 앞에서 자른다(해남 — 한 칸이 한 줄로 붙어 있었다)."""
    if title and body.startswith(title):
        body = body[len(title):]
    parts = re.split(r"\s+(?=[○●■□▶◆◇※·•∙\-–]\s)|\s+(?=\d+\)\s)|(?<=[다요음함]\.)\s+"
                     r"|\s+(?=[가-힣]{2,6}\s?:)", body)
    out, seen = [], set()
    for part in parts:
        line = BULLET.sub("", part).strip()
        if 6 <= len(line) <= 160 and line not in seen and re.search(r"[가-힣]", line):
            seen.add(line)
            out.append(line)
    return out[:40]

GENERIC_TITLE = re.compile(r"^(이용|신청|지원|사업|접수|문의|참여|운영|기타)?\s*(방법|안내|대상|내용|절차|기간|기준|자격|"
                           r"장소|시간|처|문의처|유의사항|구비서류|제출서류)$")

def split_programs(place, page_title, pg):
    """한 쪽에 사업 여럿을 접어 둔 누리집(해남·고성·예산 등) — 제목(h3·h4·h5)마다 잘라 사업마다 한 건으로.
    사장님 2026-10-02 「최대한 배너 형태로」: 지원 탭에 사업 하나가 카드 한 장. 제목이 사업 이름인지는
    TypeSafe가 먼저 본다(「지원대상」「둘째아」 같은 칸 제목은 FIELD와 이 판정이 걸러 낸다). 주소는
    쪽 주소 + #s1·#s2… — 앱 표에서 같은 주소끼리 하나로 합쳐지지 않게."""
    if not pg.get("html"):
        return []
    all_secs = sections_of(pg["html"])
    seen_t = {}
    for t, _ in all_secs:
        seen_t[t] = seen_t.get(t, 0) + 1
    # 한 쪽에 같은 제목이 되풀이되면(영월 「이용방법」×7) 사업 이름이 아니라 칸 제목이다.
    secs = [(t, b) for t, b in all_secs
            if len(b) >= 80 and len(t) >= 3 and seen_t[t] == 1 and not GENERIC_TITLE.search(t)]
    if len(secs) < 3:
        return []
    base = (pg.get("final") or "").split("#")[0]
    cands = [{"text": t, "url": f"{base}#s{i + 1}", "body": b} for i, (t, b) in enumerate(secs[:24])]
    judged = judge_links(place, page_title, [{"text": c["text"], "url": c["url"]} for c in cands])
    return [{**c, "p_program": j["p_program"]} for c, j in zip(cands, judged) if j["p_program"] >= 0.5]

def section_row(place, sido, c, groups):
    pg = {"ok": True, "status": 200, "final": c["url"], "title": c["text"], "main": c["body"], "text": c["body"]}
    row = {"text": c["text"], "url": c["url"], "p_program": c["p_program"], "section": True,
           "final": c["url"], "status": 200, "title": c["text"], "code_login": False,
           "hash": hashlib.sha1(c["body"].encode()).hexdigest()[:12]}
    judge_cached(place, {"text": c["text"], "url": c["url"]}, pg, row, groups)
    row["cls"] = classify(row)
    if ((sido in NOTES_SIDO or "all" in NOTES_SIDO) and row["cls"] in ("new", "review")
            and not row.get("match") and row.get("p_describes", 0) >= 0.7):
        lines = sec_lines(c["body"], c["text"])
        if lines:
            row["notes"] = pick_notes(place, c["text"], c["text"], lines)
    return row

def run_district(site):
    sido, d = site["sido"], site["district"]
    place = f"{sido} {d}"
    rec = {"sido": sido, "district": d, "hub": site["birth"], "hub_title_saved": site.get("birth_title")}
    sections = {}
    if site.get("seeds"):
        # 메뉴를 스크립트로 그리는 누리집 — 웹 검색으로 찾아 둔 혜택별 쪽을 바로 판정한다(hubs.json).
        hub = {"ok": True, "status": 200, "final": site["seeds"][0][1], "title": f"{place} 출산·육아 지원"}
        links = [{"text": t, "url": u} for t, u in site["seeds"]]
    elif site.get("render"):
        # 목록을 스크립트로 불러오는 누리집(성남시 등) — 처음부터 브라우저로 연다(hubs.json).
        got = _browser_html(site["render"])
        hub = {"ok": bool(got), "status": 200 if got else None, "final": got[0] if got else site["render"],
               "title": f"{place} 출산·육아 지원", "html": got[1] if got else "", "error": None if got else "Browser"}
        links = collect_links(hub, site["render"]) if got else []
    elif site.get("sections"):
        # 한 쪽에 사업을 풀어 적은 누리집 — 브라우저로 열어 제목마다 잘라 판정한다(hubs.json).
        url = site["sections"]
        got = _browser_html(url)
        hub = {"ok": bool(got), "status": 200 if got else None, "final": got[0] if got else url,
               "title": f"{place} 출산·육아 지원", "error": None if got else "Browser"}
        for t, body in (sections_of(got[1]) if got else []):
            sections[t] = body
        links = [{"text": t, "url": hub["final"]} for t in sections]
    else:
        hub = fetch(site["birth"])
    rec["hub_status"] = {k: hub.get(k) for k in ("ok", "status", "final", "title", "has_pw", "login_url", "error")}
    if not hub.get("ok"):
        rec["links"] = []
        return rec
    if not site.get("seeds") and not site.get("sections") and not site.get("render"):
        links = []
        for u in [site["birth"], *site.get("more", [])]:
            h2 = hub if u == site["birth"] else fetch(u)
            if h2.get("ok"):
                links += collect_links(h2, u)
        if len(links) < 3:
            # 목록을 스크립트로 불러오는 누리집(성남시 등) — 브라우저로 다시 연다.
            got = _browser_html(site["birth"])
            if got:
                links = collect_links({"ok": True, "final": got[0], "html": got[1]}, site["birth"])
        seen_u, uniq = set(), []
        for l in links:
            if l["url"] not in seen_u:
                seen_u.add(l["url"])
                uniq.append(l)
        links = uniq
    rec["n_candidates"] = len(links)
    if site.get("seeds") or site.get("sections"):
        judged = [{**l, "p_program": 1.0} for l in links]
    else:
        judged = judge_links(place, hub["title"], links) if links else []
        # 「임산부」「영유아」처럼 메뉴 이름이라 떨어진 링크는 한 단계 더 들어가 그 안의 사업 링크를
        # 모은다(서초구 — 보건소 사업이 메뉴 아래에 있었다, 2026-10-01). 네 쪽·60개까지.
        known = {l["url"] for l in judged} | {hub.get("final")}
        more = []
        for c in [l for l in judged if l["p_program"] < 0.5 and len(l["text"]) <= 12][:4]:
            h3 = fetch(c["url"])
            if h3.get("ok") and h3.get("html"):
                for l in collect_links(h3, c["url"]):
                    if l["url"] not in known:
                        known.add(l["url"])
                        more.append(l)
        if more:
            judged += judge_links(place, hub["title"], more[:60])
            rec["n_candidates"] += len(more[:60])
        # 출발 쪽 자체도 한 사업을 설명할 수 있다 — 서초구는 출발 쪽이 「임산부 건강관리」였는데 그
        # 안의 링크만 보고 쪽 자체는 판정하지 않았다(2026-10-01).
        name = re.split(r"\s+[-|ㅣ:<>]\s+|\s*[|ㅣ]\s*", site.get("birth_title") or hub.get("title") or "")[0].strip()
        if 2 <= len(name) <= 45 and hub.get("html"):
            judged.insert(0, {"text": name, "url": hub["final"], "p_program": 1.0, "hub": True})
    groups = groups_for(sido, d)
    found, seen_final = [], set()
    for l in judged:
        if l["p_program"] < 0.5:
            continue
        if l["text"] in sections:
            body = sections[l["text"]]
            pg = {"ok": True, "status": 200, "final": l["url"], "title": l["text"], "main": body, "text": body}
        else:
            if l.get("hub"):
                pg = hub
            else:
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
        # 본문 줄은 앱 목록과 짝이 안 지어진 쪽(「더 찾은 것」 후보)만 — 앱이 그것만 보여 준다.
        if ((sido in NOTES_SIDO or "all" in NOTES_SIDO) and pg.get("html") and row["cls"] in ("new", "review")
                and not row.get("match") and row.get("p_describes", 0) >= 0.7):
            lines = page_lines(pg["html"])
            if lines:
                row["notes"] = pick_notes(place, l["text"], pg.get("title") or "", lines)
        parts = split_programs(place, l["text"], pg) if pg.get("ok") and l["text"] not in sections else []
        if len(parts) >= 3:
            rows = [section_row(place, sido, c, groups) for c in parts]
            found.extend(rows)
            # 여러 사업을 묶은 쪽 한 장은 사업마다 나눈 것과 겹친다 — 앱 목록의 사업과 짝이 지어진 게
            # 아니면(새 것·검토) 빼고 나눈 것만 둔다.
            if row["cls"] in ("new", "review") and not row.get("match"):
                row["cls"] = "split"
        found.append(row)
    # 링크로 찾은 사업이 셋도 안 되면, 출발 쪽 자체에 사업을 풀어 적은 누리집일 수 있다(고양·화성·
    # 창원·아산 등 — 2026-09-30 전국에서 54곳). 출발 쪽을 제목마다 잘라 한 번 더 판정한다.
    good = sum(1 for r in found if r["cls"] in ("match", "national", "new"))
    if good < 3 and not site.get("sections") and not site.get("seeds") and hub.get("ok"):
        secs = sections_of(hub.get("html", "")) if hub.get("html") else []
        if len(secs) < 3:
            got = _browser_html(hub["final"])
            secs = sections_of(got[1]) if got else []
        have = {r["text"] for r in found}
        base = hub["final"].split("#")[0]
        for i, (t, body) in enumerate(secs):
            if t in have or len(body) < 80:
                continue
            have.add(t)
            found.append(section_row(place, sido, {"text": t, "url": f"{base}#s{i + 1}", "body": body,
                                                   "p_program": 1.0}, groups))
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
    ap.add_argument("--notes", default="", help="본문 줄을 고를 시·도(쉼표로), 전국은 all — 2026-10-01 서울 시범 뒤 전국")
    ap.add_argument("districts", nargs="*")
    a = ap.parse_args()
    NOTES_SIDO.update(x for x in a.notes.split(",") if x)
    sites = [x for x in json.load(open(ROOT / "tool" / "local_sites.json", encoding="utf-8"))
             if x["district"] and x.get("birth") and (a.all or x["sido"] == a.sido)]
    if a.districts:
        sites = [s for s in sites if s["district"] in a.districts]
    # 링크 모으기에 안 맞는 출발 쪽은 hubs.json이 바꾼다(앱의 누리집 단추는 그대로).
    hubs = json.loads((pathlib.Path(__file__).parent / "hubs.json").read_text(encoding="utf-8"))
    def hub_of(s):
        h = hubs.get(f"{s['sido']} {s['district']}")
        if isinstance(h, dict):
            if "sections" in h:
                return {**s, "sections": h["sections"]}
            if "render" in h:
                return {**s, "render": h["render"]}
            return {**s, "seeds": h["seeds"]}
        if isinstance(h, list):
            return {**s, "birth": h[0], "more": h[1:]}
        return {**s, "birth": h or s["birth"]}
    sites = [hub_of(s) for s in sites]
    results = run_sites(sites, a.workers)
    # 해외(GitHub 서버)에서는 누리집이 몰릴 때 늦게 답한다 — 안 열린 곳만 1분 쉬었다가 둘씩 한 번 더.
    slow = {(r["sido"], r["district"]) for r in results
            if (r.get("hub_status") or {}).get("error") in ("Timeout", "ConnectionError", "ConnectTimeout", "ReadTimeout")}
    if slow:
        print(f"다시 시도 {len(slow)}곳", flush=True)
        time.sleep(60)
        again = {(r["sido"], r["district"]): r for r in run_sites(
            [s for s in sites if (s["sido"], s["district"]) in slow], 2)}
        def better(r):
            a2 = again.get((r["sido"], r["district"]))
            return a2 if a2 and (a2.get("hub_status") or {}).get("ok") else r
        results = [better(r) for r in results]
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
