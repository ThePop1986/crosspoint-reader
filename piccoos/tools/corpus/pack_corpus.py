#!/usr/bin/env python3
"""Pack a generated corpus into a ZIP with UTF-8 file names, then verify it.

Usage:
    python3 pack_corpus.py <corpus-dir> <out.zip>

Python's zipfile sets the UTF-8 flag (general purpose bit 11) for every non-ASCII
name, so Cyrillic EPUB names survive in any compliant unzip tool. After writing,
the archive is reopened and every entry is checked against manifest.json:
name, UTF-8 flag on non-ASCII names, size and sha256.
"""
from __future__ import annotations

import hashlib
import json
import sys
import zipfile
from pathlib import Path

UTF8_FLAG = 0x800


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    corpus, out = Path(sys.argv[1]), Path(sys.argv[2])
    manifest = json.loads((corpus / "manifest.json").read_text(encoding="utf-8"))
    files = [corpus / "manifest.json"] + sorted((corpus / "books").glob("*.epub"))
    if (corpus / "LICENSE-CORPUS.md").is_file():
        files.insert(1, corpus / "LICENSE-CORPUS.md")

    with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_STORED) as z:  # EPUBs are already zipped
        for f in files:
            info = zipfile.ZipInfo(f.relative_to(corpus).as_posix(), date_time=(2026, 11, 12, 0, 0, 0))
            info.external_attr = 0o644 << 16
            z.writestr(info, f.read_bytes())

    errors = []
    expected = {f"books/{b['filename']}": b for b in manifest["books"]}
    with zipfile.ZipFile(out) as z:
        seen = set()
        for info in z.infolist():
            if not info.filename.isascii() and not info.flag_bits & UTF8_FLAG:
                errors.append(f"no UTF-8 flag: {info.filename!r}")
            book = expected.get(info.filename)
            if book is None:
                continue
            seen.add(info.filename)
            data = z.read(info)
            if len(data) != book["size"] or hashlib.sha256(data).hexdigest() != book["sha256"]:
                errors.append(f"size/sha256 mismatch: {info.filename}")
        missing = set(expected) - seen
        errors += [f"missing in zip: {m}" for m in sorted(missing)]
    non_ascii = sum(1 for n in expected if not n.isascii())
    print(f"{out}: {len(files)} files, {non_ascii} non-ASCII names, errors: {len(errors)}")
    for e in errors:
        print("  " + e, file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
