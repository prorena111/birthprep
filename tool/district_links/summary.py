# 매달 작업(links.yml)의 실행 요약 — TypeSafe 쓴 양, 출발 쪽이 열린 곳·안 열린 까닭.
#   LINK_OUT=build/district_links python tool/district_links/summary.py >> $GITHUB_STEP_SUMMARY
import collections, glob, json, os, pathlib

out = pathlib.Path(os.environ.get("LINK_OUT") or pathlib.Path(__file__).resolve().parents[2] / "build" / "district_links")
u = json.loads((out / "usage.json").read_text(encoding="utf-8"))
print(f"## 구 누리집 링크\n\nTypeSafe {u['calls']}번 · 입력 {u['input']:,} 토큰 ≈ "
      f"${u['input'] / 1e6 * 0.042:.3f} · 다시 안 물은 것 {u['hits']}\n")
ok, links, errs, samples = 0, 0, collections.Counter(), []
for f in sorted(glob.glob(str(out / "links_*.json"))):
    for r in json.loads(pathlib.Path(f).read_text(encoding="utf-8"))["results"]:
        h = r.get("hub_status") or {}
        if h.get("ok"):
            ok += 1
            links += len(r.get("links", []))
        else:
            e = h.get("error") or f"HTTP {h.get('status')}"
            errs[e] += 1
            if len(samples) < 10:
                samples.append(f"{r['sido']} {r['district']}: {e}")
print(f"출발 쪽이 열린 곳 {ok} · 안 열린 곳 {sum(errs.values())} {dict(errs)} · 판정한 쪽 {links}\n")
for x in samples:
    print(f"- {x}")
