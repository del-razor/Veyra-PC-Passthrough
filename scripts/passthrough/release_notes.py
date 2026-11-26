"""Write Veyra PLUS release notes: this fork's changes plus the English part of the upstream notes.

usage: python release_notes.py --upstream UPSTREAM.md --version X.Y.Z --changes PLUS-CHANGES.md --output NOTES.md

Only English text is kept, and links are reduced to their text, so the notes never point at
upstream downloads. Sentences about removing the mouse passthrough are dropped because
Veyra PLUS keeps it.
"""
import argparse
import re
from pathlib import Path

CJK = re.compile(r"[　-〿㐀-鿿＀-￯]")
LINK = re.compile(r"!?\[([^\]]*)\]\([^)]*\)")
URL = re.compile(r"https?://\S+")
DROP_SENTENCE = re.compile(r"passthrough is removed|mouse click-through has been removed|links to Magpie", re.I)


def english_section(text):
    """The upstream body's '## English' section, else every line without Chinese."""
    match = re.search(r"^## English\s*$(.*?)(?=^## |\Z)", text, re.M | re.S)
    if match:
        return match.group(1)
    return "\n".join(line for line in text.splitlines() if not CJK.search(line))


def clean(section):
    # The upstream test results describe the upstream build, not this one.
    section = re.sub(r"^### Validation\s*$.*?(?=^#{2,3} |\Z)", "", section, flags=re.M | re.S)
    out = []
    for line in section.splitlines():
        if CJK.search(line) or line.lstrip().startswith("<"):
            continue
        line = LINK.sub(lambda m: m.group(1), line)
        line = URL.sub("", line).rstrip()
        if DROP_SENTENCE.search(line):
            prefix = re.match(r"\s*(?:[-*]\s+)?", line).group(0)
            sentences = re.split(r"(?<=[.!?])\s+", line[len(prefix):])
            kept = [s for s in sentences if not DROP_SENTENCE.search(s)]
            if not kept:
                continue
            line = prefix + " ".join(kept)
        out.append(line)
    text = "\n".join(out)
    return re.sub(r"\n{3,}", "\n\n", text).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--upstream", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--changes", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    upstream = clean(english_section(args.upstream.read_text(encoding="utf-8-sig")))
    changes = args.changes.read_text(encoding="utf-8-sig").strip().replace("{version}", args.version)
    body = f"{changes}\n\n## What's new in Veyra {args.version}\n\n{upstream}\n"
    args.output.write_text(body, encoding="utf-8")


if __name__ == "__main__":
    main()
