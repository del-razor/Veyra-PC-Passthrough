"""Write OverRez release notes from RELEASE-NOTES.md.

usage: python release_notes.py --version X.Y.Z --upstream-version A.B.C --changes RELEASE-NOTES.md --output NOTES.md

{version} becomes the OverRez version and {upstream} the Veyra release it is based on. The notes
are checked to be English only and free of links, so they never point at other downloads.
"""
import argparse
import re
from pathlib import Path

CJK = re.compile(r"[　-〿㐀-鿿＀-￯]")
LINK = re.compile(r"https?://|\]\(")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--upstream-version", required=True)
    parser.add_argument("--changes", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    body = args.changes.read_text(encoding="utf-8-sig").strip()
    body = body.replace("{version}", args.version).replace("{upstream}", args.upstream_version) + "\n"
    if CJK.search(body):
        raise SystemExit("release notes must be English only")
    if LINK.search(body):
        raise SystemExit("release notes must not contain links")
    args.output.write_text(body, encoding="utf-8")


if __name__ == "__main__":
    main()
