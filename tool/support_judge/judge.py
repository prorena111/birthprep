"""지원 목록(v1/local.json)을 TypeSafe로 한 번 더 거른다 — 매달 자동 작업(monthly.yml)이
tool/monthly/monthly.dart 다음에 부른다.

사장님 2026-11-01 「타입세이프를 적극 활용해」. 10/31 점검에서 낱말 규칙(gov24_pick.dart)만으로는
보호종료 아동 자립금·결식 급식·행사 예산·끝난 사업·두 줄로 올라온 같은 사업을 다 못 걸렀다.
낱말 규칙은 그대로 1차로 두고, 남은 것을 사업마다 TypeSafe에 묻는다.

  ① 임신 준비~만 6세 아이를 키우는 집이 받을 수 있나(scope)
  ② 주민이 직접 받는 것인가 — 시설·행사·기관 예산이 아닌가(personal)
  ③ 글에 끝났다·신규 불가라고 적혀 있나(ended)
  ④ 언제 신청하나(phase) — 앱의 시기(SupportPhase) 이름으로. 확신이 높으면 항목에 `phase`로 적는다.
  ⑤ 같은 기관의 비슷한 이름 두 줄이 같은 사업인가(same) — 정부24 것을 남기고 복지로·서울·경기 사본을 뺀다.

**AI는 글을 쓰지 않는다** — 빼거나(①②③⑤) 앱에 있는 시기 이름 중 하나를 고를(④) 뿐이다.
「빠지는 게 있어서는 안 돼」(사장님 2026-09-27) — 확률이 아주 낮을 때만 뺀다(SCOPE_MIN 등).
한 번에 15%를 넘게 빼려 하면 아무것도 바꾸지 않고 멈춘다(판정 사고).

지난 판정은 tool/support_judge/cache.json — 글이 그대로면 다시 묻지 않는다(매달 비용은 바뀐 것만).
키: 환경변수 TYPESAFE_API_KEY, 없으면 「타입세이프 api 키.txt」(구 누리집 링크 도구와 같다). 찍지 않는다.
TypeSafe가 안 되면 목록을 그대로 두고 0으로 끝난다(매달 갱신은 살린다).

  python tool/support_judge/judge.py --root <공개 저장소>            # 판정하고 v1/local.json·data.json 고침
  python tool/support_judge/judge.py --root <공개 저장소> --dry      # 고치지 않고 보고만
dart 기본 라이브러리처럼 파이썬 기본 라이브러리만 쓴다(Actions에서 pip 없이).
"""
import argparse
import concurrent.futures as cf
import difflib
import hashlib
import json
import os
import pathlib
import re
import sys
import threading
import time
import urllib.error
import urllib.request

HERE = pathlib.Path(__file__).resolve().parent
SCOPE_MIN = 0.12      # 이보다 낮으면 「임신~만 6세 집이 못 받는다」
PERSONAL_MIN = 0.12   # 이보다 낮으면 「주민이 받는 것이 아니다」
ENDED_MIN = 0.88      # 이보다 높으면 「끝났다」
SAME_MIN = 0.88       # 이보다 높으면 「같은 사업」
PHASE_MIN = 0.7       # 시기를 항목에 적는 확신
MAX_DROP = 0.15       # 한 번에 이보다 많이 빼려 하면 멈춘다
PHASES = ("preconception", "pregnancy", "birthReport", "afterBirth")
SOURCE_RANK = {"gov24": 0, "bokjiro": 1, "seoul": 2, "gg": 3}  # 같은 사업이면 앞의 것을 남긴다
SIDO = ["서울특별시", "부산광역시", "대구광역시", "인천광역시", "광주광역시", "대전광역시", "울산광역시",
        "세종특별자치시", "경기도", "강원특별자치도", "강원도", "충청북도", "충청남도", "전북특별자치도", "전라북도",
        "전라남도", "전남광주통합특별시", "경상북도", "경상남도", "제주특별자치도"]
USAGE = {"calls": 0, "input": 0}
_lock = threading.Lock()


def _key():
    raw = os.environ.get("TYPESAFE_API_KEY")
    if not raw:
        # 구글 드라이브 맨 위(G:\내 드라이브) — 이 파일 위 폴더를 차례로 본다. 그다음 옛 OneDrive.
        for p in [d / "타입세이프 api 키.txt" for d in HERE.parents] + [
                pathlib.Path.home() / "OneDrive" / "타입세이프 api 키.txt"]:
            if not p.is_file():
                continue
            try:
                raw = p.read_text(encoding="utf-8-sig")
                break
            except OSError:
                continue
    words = (raw or "").replace(chr(0xFEFF), "").replace(chr(0x200B), "").split()
    return words[-1] if words else ""


KEY = _key()


def ask(state, questions):
    body = json.dumps({"model": "jev-latest", "state": state, "questions": questions}).encode()
    for attempt in range(6):
        req = urllib.request.Request("https://api.typesafe.ai/v1/systemone", data=body, method="POST",
                                     headers={"Authorization": "Bearer " + KEY, "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                d = json.loads(r.read())
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 502, 503, 520, 529):
                time.sleep(2 ** attempt)
                continue
            raise RuntimeError(f"TypeSafe {e.code}") from None
        except (urllib.error.URLError, TimeoutError, OSError):
            time.sleep(2 ** attempt)
            continue
        with _lock:
            USAGE["calls"] += 1
            USAGE["input"] += d.get("usage", {}).get("input_tokens", 0)
        return d["answers"]
    raise RuntimeError("TypeSafe 재시도 초과")


def _cut(v, n):
    v = (v or "").strip()
    return v if len(v) <= n else v[:n] + "…"


def item_state(i, today):
    return {"today": today, "org": i["org"], "name": i["name"], "summary": _cut(i.get("summary"), 300),
            "target": _cut(i.get("target"), 700), "criteria": _cut(i.get("criteria"), 500),
            "content": _cut(i.get("content"), 1100), "deadline": _cut(i.get("deadline"), 200),
            "how": _cut(i.get("howText"), 250)}


def _hash(obj):
    return hashlib.sha1(json.dumps(obj, ensure_ascii=False, sort_keys=True).encode()).hexdigest()[:16]


ITEM_QS = {
    "scope": {"type": "noul",
        "instructions": "Can a pregnant woman, a couple preparing for pregnancy or treating infertility, or a family raising "
                        "a baby or a child aged 6 or younger (up to entering elementary school) receive or use this program? "
                        "Answer yes when that group is included among the eligible people, even if older children or other "
                        "groups are also eligible.",
        "criteria": {"true": "Eligible people include pregnancy, infertility, newborns, infants, toddlers, preschool children, "
                             "children entering elementary school, or their parents (incl. multi-child or single-parent "
                             "families with young children).",
                     "false": "Only older school children (after elementary entry), middle/high school students, youths "
                              "leaving care at 18, adults in general, the elderly, staff, businesses or facilities."}},
    "personal": {"type": "noul",
        "instructions": "Do residents (individuals or households) themselves apply for or directly receive this — money, a "
                        "voucher, goods, a discount, a free service, a check-up, a class, a rental or use of a facility — "
                        "rather than it being a budget paid to a facility, hospital, organization, event or business?",
        "criteria": {"true": "Residents apply for, receive or use it themselves.",
                     "false": "It only funds or operates a facility, hospital, event, festival, organization, staff or "
                              "business; residents do not apply for or receive anything themselves."}},
    "ended": {"type": "noul",
        "instructions": "Given `today`, does the text say this program has already ended, was discontinued, abolished or "
                        "replaced, or no longer accepts any new applicants? Conditional notes such as 'until the budget runs "
                        "out', a yearly application window, or a past start date do NOT count.",
        "criteria": {"true": "The text states it ended / was discontinued / intake is closed with no future intake / new "
                             "applicants are not accepted, or it is clearly a one-off program for a year before 2025.",
                     "false": "It is ongoing, or the text only mentions conditional closing, application periods, "
                              "eligibility dates or effective dates."}},
    "phase": {"type": "choice",
        "instructions": "When does a family usually apply for or start using this program?",
        "criteria": {
            "preconception": "Before pregnancy — preparing for pregnancy, infertility treatment, egg freezing, "
                             "pre-pregnancy or newlywed health check-ups.",
            "pregnancy": "During pregnancy — for pregnant women: prenatal care, pregnancy registration, prenatal tests, "
                         "transport or items before the birth.",
            "birthReport": "Right at the birth — a one-time birth bonus, birth congratulation money or birth gift applied "
                           "for at or soon after the birth registration.",
            "afterBirth": "After the baby is born, while raising the child — postpartum care, infant/child care, monthly "
                          "child allowances, nursery or kindergarten costs, child health, school entry money at age 6-7."}},
}


def judge_item(i, today):
    a = ask(item_state(i, today), ITEM_QS)
    ph = a["phase"]
    return {"scope": round(a["scope"]["noul"], 3), "personal": round(a["personal"]["noul"], 3),
            "ended": round(a["ended"]["noul"], 3), "phase": ph.get("choice"),
            "phaseConf": round(ph.get("confidence") or 0, 3)}


def judge_pair(a, b):
    def side(i):
        return {"source": i.get("source", "gov24"), "name": i["name"], "summary": _cut(i.get("summary"), 250),
                "target": _cut(i.get("target"), 400), "content": _cut(i.get("content"), 700)}
    ans = ask({"org": a["org"], "a": side(a), "b": side(b)}, {"same": {"type": "noul",
        "instructions": "Are `a` and `b` the same program — the same benefit for the same target group from the same "
                        "provider, possibly worded differently or registered on two different websites?",
        "criteria": {"true": "Same program (e.g. one site's copy of the other, or one lists it with slightly different words).",
                     "false": "Different programs: a different benefit, a different target group (e.g. only low-income, "
                              "only twins, third child, single parents), a different amount scheme, or only loosely related."}}})
    return round(ans["same"]["noul"], 3)


# ---------- 같은 사업 후보 ----------
def _norm(name, org):
    n = re.sub(r"\([^)]*\)|\[[^\]]*\]|〔[^〕]*〕|20\d\d\s*년?", "", name)
    for t in org.split():
        for v in {t, t[:-1] if len(t) > 2 else t, t[:2]}:
            if len(v) >= 2:
                n = n.replace(v, "")
    n = re.sub(r"[\s·ㆍ・,.\-_:「」<>~]", "", n)
    return re.sub(r"(지원사업|지원금|지원|사업|지급|서비스|운영|신청|안내)+$", "", n)


def pair_candidates(items):
    """같은 기관 안(그리고 시군구 사본 ↔ 그 시·도 정부24 것)에서 이름이 비슷한 두 줄 — 한쪽은 정부24가 아닌 것."""
    by_org = {}
    for i in items:
        by_org.setdefault(i["org"], []).append(i)
    out = []
    for org, lst in by_org.items():
        sido = next((s for s in SIDO if org.startswith(s + " ")), None)
        pool = lst + ([g for g in by_org.get(sido, []) if g.get("source", "gov24") == "gov24"] if sido else [])
        for x in range(len(lst)):
            a = lst[x]
            for b in pool[x + 1:]:
                if a is b or (a.get("source", "gov24") == "gov24" and b.get("source", "gov24") == "gov24"):
                    continue
                na, nb = _norm(a["name"], a["org"]), _norm(b["name"], b["org"])
                if not na or not nb:
                    continue
                cross = a["org"] != b["org"]
                r = difflib.SequenceMatcher(None, na, nb).ratio()
                contain = min(len(na), len(nb)) >= 2 and (na in nb or nb in na)
                if r >= (0.7 if cross else 0.5) or (contain and not cross):
                    out.append((a, b))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".")
    ap.add_argument("--dry", action="store_true", help="고치지 않고 보고만")
    ap.add_argument("--cache", default=str(HERE / "cache.json"))
    ap.add_argument("--report", default=str(HERE / "last_report.md"))
    ap.add_argument("--workers", type=int, default=8)
    ap.add_argument("--today")
    args = ap.parse_args()
    root = pathlib.Path(args.root)
    lp, dp = root / "v1" / "local.json", root / "v1" / "data.json"
    local = json.loads(lp.read_text(encoding="utf-8"))
    items = local["items"]
    today = args.today or time.strftime("%Y-%m-%d", time.gmtime(time.time() + 9 * 3600))
    if not KEY:
        print("TypeSafe 키가 없어 판정을 건너뜀(목록은 그대로).")
        return 0
    cpath = pathlib.Path(args.cache)
    cache = json.loads(cpath.read_text(encoding="utf-8")) if cpath.exists() else {"items": {}, "pairs": {}}
    year = today[:4]  # 「끝났나」는 해가 바뀌면 다시 묻는다

    verdicts, todo = {}, []
    for i in items:
        h = _hash([year, item_state(i, "")])
        c = cache["items"].get(i["id"])
        if c and c.get("hash") == h:
            verdicts[i["id"]] = c
        else:
            todo.append((i, h))
    try:
        with cf.ThreadPoolExecutor(args.workers) as ex:
            for (i, h), v in zip(todo, ex.map(lambda t: judge_item(t[0], today), todo)):
                verdicts[i["id"]] = {"hash": h, **v}
        pairs = pair_candidates(items)
        ptodo, same = [], {}
        for a, b in pairs:
            k = "|".join(sorted([a["id"], b["id"]]))
            h = _hash([item_state(a, ""), item_state(b, "")])
            c = cache["pairs"].get(k)
            if c and c.get("hash") == h:
                same[k] = c["same"]
            else:
                ptodo.append((k, h, a, b))
        with cf.ThreadPoolExecutor(args.workers) as ex:
            for (k, h, a, b), p in zip(ptodo, ex.map(lambda t: judge_pair(t[2], t[3]), ptodo)):
                same[k] = p
                cache["pairs"][k] = {"hash": h, "same": p}
    except RuntimeError as e:
        print(f"TypeSafe 판정 실패 — 목록은 그대로 둠: {e}")
        return 0
    cache["items"] = {**{k: v for k, v in cache["items"].items() if k in verdicts}, **verdicts}
    live = {i["id"] for i in items}
    cache["pairs"] = {k: v for k, v in cache["pairs"].items() if all(x in live for x in k.split("|"))}

    drop = {}
    for i in items:
        v = verdicts[i["id"]]
        if v["scope"] < SCOPE_MIN:
            drop[i["id"]] = f"임신~만 6세 집이 못 받음({v['scope']})"
        elif v["personal"] < PERSONAL_MIN:
            drop[i["id"]] = f"주민이 받는 것 아님({v['personal']})"
        elif v["ended"] >= ENDED_MIN:
            drop[i["id"]] = f"끝남({v['ended']})"
    for a, b in pairs:
        k = "|".join(sorted([a["id"], b["id"]]))
        if same.get(k, 0) >= SAME_MIN and a["id"] not in drop and b["id"] not in drop:
            ra, rb = SOURCE_RANK.get(a.get("source", "gov24"), 9), SOURCE_RANK.get(b.get("source", "gov24"), 9)
            loser, keep = (b, a) if (rb, len(b.get("content") or "")) >= (ra, len(a.get("content") or "")) and rb >= ra else (a, b)
            if loser.get("source", "gov24") != "gov24":
                drop[loser["id"]] = f"같은 사업({same[k]}) ← {keep['id']} {keep['name']}"

    names = {i["id"]: i for i in items}
    lines = [f"## 지원 목록 TypeSafe 판정 {today}", "",
             f"- 항목 {len(items)}개 · 새로 물은 것 {len(todo)}개 · 같은 사업 후보 {len(pairs)}쌍(새로 {len(ptodo)}) · "
             f"부른 수 {USAGE['calls']} · 입력 {USAGE['input']:,} 토큰(≈{USAGE['input'] / 1e6 * 0.042:.3f}달러)",
             f"- 뺄 것 {len(drop)}개", ""]
    for k, why in sorted(drop.items(), key=lambda kv: (kv[1][:4], names[kv[0]]["org"])):
        lines.append(f"  - {names[k]['org']} | {names[k]['name']} — {why} (`{k}`)")
    over = len(drop) > len(items) * MAX_DROP
    if over:
        lines.append(f"\n**{len(drop)}개는 {MAX_DROP:.0%}를 넘어 이번에는 아무것도 빼지 않았다 — 사람이 볼 것.**")
    report = "\n".join(lines) + "\n"
    pathlib.Path(args.report).write_text(report, encoding="utf-8")
    print(report)
    cpath.write_text(json.dumps(cache, ensure_ascii=False, indent=1, sort_keys=True) + "\n", encoding="utf-8")
    if args.dry or over:
        return 0

    kept = []
    for i in items:
        if i["id"] in drop:
            continue
        v = verdicts[i["id"]]
        j = {k: x for k, x in i.items() if k != "phase"}
        if v.get("phase") in PHASES and v.get("phaseConf", 0) >= PHASE_MIN:
            j["phase"] = v["phase"]
        kept.append(j)
    rev = hashlib.sha1(json.dumps(kept, ensure_ascii=False).encode()).hexdigest()[:16]
    nation = sum(1 for i in kept if not any(i["org"] == s or i["org"].startswith(s + " ") for s in SIDO))
    local.update({"rev": rev, "count": len(kept), "items": kept})
    lp.write_text(json.dumps(local, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    data = json.loads(dp.read_text(encoding="utf-8"))
    if isinstance(data.get("local"), dict) and data["local"].get("checked") == local.get("checked"):
        data["local"].update({"rev": rev, "count": len(kept), "nation": nation})
        dp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
