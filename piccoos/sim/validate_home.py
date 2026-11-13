#!/usr/bin/env python3
"""validate_home.py — two modes.

Full mode:
    validate_home.py --bmp <path> --log <path> --ref <path>

    Validates a Balanced Home screen capture. Outputs exactly one line per check in
    fixed order: log, pixel_sig, diff.

    Line format:
      PASS <check>: <detail>    — check ran, result positive
      FAIL <check>: <detail>    — check ran, result negative
      ERROR <check>: <reason>   — internal error (missing/unreadable input, decode
                                   failure, Pillow import error); exit code 2

    Exit 0 — all three checks ran (even if some are FAIL).
    Exit 2 — at least one check had an internal error (ERROR line).

    Thresholds (do not change without updating CI):
      y=711 (separator): black pixels (< 128) >= 90% of row width
      y=690 (content zone): white pixels (>= 200) >= 98% of row width
      diff: pixel differs when |delta| > 32; difference >= 5% of total pixels

Marker-only mode:
    validate_home.py --marker-only --log <path>

    Checks only the balanced home marker in the simulator log.
    Exit 0  — marker found.
    Exit 1  — log readable, marker absent.
    Exit 2  — log missing, empty, or unreadable.
    Output  — one line: PASS marker: … / FAIL marker: … / ERROR marker: …

NUL-byte rule (both modes): each line is evaluated independently. A line containing
a NUL byte (or any character outside the exact marker pattern) does not match and is
skipped; other lines in the same log are still checked normally.
"""

import argparse
import re
import sys

# logPrintf format (Logging.cpp:47): [<ms>] [INF] [HOME] layout=balanced\n
# newline="" keeps \r untranslated; split("\n") is the only separator;
# strip one trailing \r for CRLF; fullmatch anchors to the complete line.
_MARKER_RE = re.compile(r"\[[0-9]+\] \[INF\] \[HOME\] layout=balanced")


def _has_balanced_marker(log_text: str) -> bool:
    """Return True iff any line in log_text exactly matches the balanced home marker."""
    for line in log_text.split("\n"):
        stripped = line[:-1] if line.endswith("\r") else line
        if _MARKER_RE.fullmatch(stripped):
            return True
    return False


def run_marker_only(log_path: str) -> int:
    """Check marker only: 0=found, 1=absent, 2=log missing/empty/unreadable."""
    try:
        with open(log_path, encoding="utf-8", errors="replace", newline="") as f:
            log_text = f.read()
    except OSError as e:
        print(f"ERROR marker: {e}")
        return 2
    if not log_text:
        print("FAIL marker: log empty")
        return 2
    if _has_balanced_marker(log_text):
        print("PASS marker: layout=balanced")
        return 0
    print("FAIL marker: layout=balanced absent")
    return 1


def run(bmp_path: str, log_path: str, ref_path: str) -> int:
    try:
        from PIL import Image, ImageChops  # noqa: F401 (checked at function scope)
        pil_ok = True
        pil_err = ""
    except ImportError as e:
        pil_ok = False
        pil_err = str(e)
        Image = ImageChops = None  # type: ignore[assignment]

    errors = 0
    img = None
    img_w = img_h = 0

    # ── (a) log check ──────────────────────────────────────────────────────────
    try:
        with open(log_path, encoding="utf-8", errors="replace", newline="") as f:
            log_text = f.read()
        if _has_balanced_marker(log_text):
            print("PASS log: layout=balanced")
        else:
            print("FAIL log: layout=balanced absent")
    except OSError as e:
        print(f"ERROR log: {e}")
        errors += 1

    # ── (b,c) pixel_sig check ─────────────────────────────────────────────────
    if not pil_ok:
        print(f"ERROR pixel_sig: Pillow import error: {pil_err}")
        errors += 1
    else:
        try:
            img = Image.open(bmp_path).convert("L")  # type: ignore[union-attr]
            img_w, img_h = img.size
            if (img_w, img_h) != (480, 800):
                print(f"FAIL pixel_sig: size {img_w}x{img_h} (want 480x800)")
            else:
                row711 = [img.getpixel((x, 711)) for x in range(img_w)]
                black_pct = 100 * sum(1 for v in row711 if v < 128) / img_w
                row690 = [img.getpixel((x, 690)) for x in range(img_w)]
                white_pct = 100 * sum(1 for v in row690 if v >= 200) / img_w
                if black_pct >= 90 and white_pct >= 98:
                    print(f"PASS pixel_sig: y711_black={black_pct:.1f}% y690_white={white_pct:.1f}%")
                else:
                    print(f"FAIL pixel_sig: y711_black={black_pct:.1f}% y690_white={white_pct:.1f}%")
        except Exception as e:
            print(f"ERROR pixel_sig: {e}")
            errors += 1
            img = None

    # ── (d) diff check ────────────────────────────────────────────────────────
    if not pil_ok:
        print(f"ERROR diff: Pillow import error: {pil_err}")
        errors += 1
    elif img is None:
        print("ERROR diff: bmp not loaded (see pixel_sig error)")
        errors += 1
    else:
        try:
            ref = Image.open(ref_path).convert("L")  # type: ignore[union-attr]
            rw, rh = ref.size
            if (img_w, img_h) != (rw, rh):
                print(f"FAIL diff: size_mismatch bmp={img_w}x{img_h} ref={rw}x{rh}")
            else:
                d = ImageChops.difference(img, ref).point(  # type: ignore[union-attr]
                    lambda v: 255 if v > 32 else 0
                )
                changed = d.histogram()[255]
                total = img_w * img_h
                pct_str = f"{100.0 * changed / total:.2f}"
                if changed * 100 >= total * 5:
                    print(f"PASS diff: {pct_str}%")
                else:
                    print(f"FAIL diff: only_{pct_str}%_vs_ref")
        except Exception as e:
            print(f"ERROR diff: {e}")
            errors += 1

    return 2 if errors > 0 else 0


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Validate a Balanced Home screen capture."
    )
    parser.add_argument("--marker-only", action="store_true",
                        help="check marker only; exit 0=found 1=absent 2=error")
    parser.add_argument("--bmp", help="screenshot BMP path (required without --marker-only)")
    parser.add_argument("--log", required=True, help="simulator log path")
    parser.add_argument("--ref", help="reference BMP for diff check (required without --marker-only)")
    args = parser.parse_args()

    try:
        if args.marker_only:
            sys.exit(run_marker_only(args.log))
        else:
            if args.bmp is None or args.ref is None:
                parser.error("--bmp and --ref are required without --marker-only")
            sys.exit(run(args.bmp, args.log, args.ref))
    except Exception as e:  # catch-all — no silent swallowing
        print(f"ERROR log: unexpected top-level error: {e}")
        print(f"ERROR pixel_sig: unexpected top-level error: {e}")
        print(f"ERROR diff: unexpected top-level error: {e}")
        sys.exit(2)


if __name__ == "__main__":
    main()
