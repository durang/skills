#!/usr/bin/env python3
"""Replay pages the signal-detector could not write (~/.gbrain/hooks/retry-queue/*.md).

    python3 replay-retry-queue.py --dry-run    # report only, writes nothing
    python3 replay-retry-queue.py              # replay; successes move to retry-queue/done/

Why not `gbrain put < file`: a bare put onto an existing slug is rejected with
revision_conflict, which is what put these pages in the queue in the first place.
Existing pages get the capture APPENDED (merge_into_existing: sources appended,
Related kept, expected_revision passed); slugs that do not exist yet are created as-is.

Each replayed entry keeps its ORIGINAL capture date and session_id (from the queued
file), not today's — otherwise a replay would claim the capture happened now.
"""
import importlib.util, json, re, shutil, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("sd", str(HERE / "signal-detector.py"))
sd = importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(sd)
except SystemExit:
    pass

import yaml

QUEUE = Path.home() / ".gbrain/hooks/retry-queue"
DONE = QUEUE / "done"


def parse(path: Path):
    m = re.match(r"^---\n(.*?)\n---\n?(.*)$", path.read_text(), re.S)
    if not m:
        return None
    fm = yaml.safe_load(m.group(1)) or {}
    rest = m.group(2).strip()
    rel = re.search(r"(?m)^## Related\s*$", rest)
    links = re.findall(r"\[\[([^\]]+)\]\]", rest[rel.start():]) if rel else []
    body = (rest[:rel.start()] if rel else rest).strip()
    return fm, body, links


def exists(slug: str) -> bool:
    return sd._gb(["get", slug, "--json"]).returncode == 0


def main(dry: bool) -> int:
    files = sorted(QUEUE.glob("*.md"))
    if not files:
        print("cola vacía")
        return 0
    DONE.mkdir(exist_ok=True)
    res = {"merged": 0, "duplicate": 0, "created": 0, "failed": 0}
    for f in files:
        slug = f.stem.replace("~", "/")
        parsed = parse(f)
        if not parsed:
            print(f"  ⚠️  {slug}: no se pudo leer el frontmatter"); res["failed"] += 1; continue
        fm, body, links = parsed
        src = (fm.get("sources") or [{}])[0] if isinstance(fm.get("sources"), list) else {}
        cap = str(fm.get("captured_at") or src.get("date") or "")[:10] or "unknown"
        entry = {"date": cap, "channel": src.get("channel") or "claude-code-signal-detector",
                 "session_id": src.get("session_id") or fm.get("source_session") or "unknown"}
        if dry:
            print(f"  · {slug}: {'existe → merge' if exists(slug) else 'nueva → create'} · cuerpo {len(body)} chars · fecha {cap}")
            continue
        if exists(slug):
            out = sd.merge_into_existing(slug, body, links, entry, cap)
        else:
            r = sd._gb(["put", slug], stdin=f.read_text())
            out = "created" if r.returncode == 0 else f"put_failed: {sd._clean_err(r.stderr or r.stdout)}"
        if out in ("merged", "duplicate", "created"):
            res[out] += 1; shutil.move(str(f), str(DONE / f.name)); print(f"  ✅ {slug}: {out}")
        else:
            res["failed"] += 1; print(f"  ❌ {slug}: {out}")
    if not dry:
        print(f"\nresumen: {res}")
    return 0 if res["failed"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main("--dry-run" in sys.argv))
