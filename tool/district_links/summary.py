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
            # 출발 쪽을 연 뒤 판정에서 죽었으면 hub_status가 없고 error가 있다(키 오류 등).
            e = h.get("error") or (r.get("error") or "")[:120] or f"HTTP {h.get('status')}"
            errs[e] += 1
            if len(samples) < 10:
                samples.append(f"{r['sido']} {r['district']}: {e}")
print(f"출발 쪽이 열린 곳 {ok} · 안 열린 곳 {sum(errs.values())} {dict(errs)} · 판정한 쪽 {links}\n")
for x in samples:
    print(f"- {x}")

# TypeSafe 키가 틀렸거나(401) 판정이 거의 다 죽었으면 실패로 끝낸다 — 성공으로 끝나면 메일이
# 안 가서 아무도 모른다(2026-09-30 첫 실행: 비밀값 오류로 189곳이 401인데 「성공」이었다).
failed = sum(n for e, n in errs.items() if e.startswith("TypeSafe"))
if failed:
    print(f"\n⚠️ TypeSafe 오류 {failed}곳 — Settings → Secrets → TYPESAFE_API_KEY를 확인하세요.")
    raise SystemExit(2)
