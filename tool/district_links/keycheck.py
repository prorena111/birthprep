# 키 모양 확인 — 값은 찍지 않고 길이·낱말 수·지문(sha256) 앞 8자리만. 이 PC의 키 파일과 견줄 때.
#   python tool/district_links/keycheck.py   (환경변수 TYPESAFE_API_KEY, 없으면 OneDrive 파일)
import hashlib, os, pathlib

raw = os.environ.get("TYPESAFE_API_KEY")
where = "비밀값"
if raw is None:
    raw = (pathlib.Path.home() / "OneDrive" / "타입세이프 api 키.txt").read_text(encoding="utf-8-sig")
    where = "키 파일"
words = raw.replace("﻿", "").replace("​", "").split()
key = words[-1] if words else ""
odd = sorted({hex(ord(c)) for c in raw if not c.isprintable() and c not in "\n\r\t "})
print(f"{where}: 전체 {len(raw)}자 · 낱말 {len(words)}개 · 키 {len(key)}자 · "
      f"지문 {hashlib.sha256(key.encode()).hexdigest()[:8]}" + (f" · 보이지 않는 글자 {odd}" if odd else ""))
