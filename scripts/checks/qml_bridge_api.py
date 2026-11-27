"""Fail when QML uses a bridge name that QmlPlayerBridge does not expose.

QML reads `veyra.<name>` at runtime, so a removed Q_PROPERTY, Q_INVOKABLE,
slot or signal still compiles and only shows up as blank or stuck controls.
"""
import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[2]
header = (root / "include/veyra/ui/QmlPlayerBridge.h").read_text(encoding="utf-8")
api = set(re.findall(r"Q_PROPERTY\(\S+\s+(\w+)", header))
api |= set(re.findall(r"Q_INVOKABLE[^(;]*?(\w+)\s*\(", header))
section = False
for line in header.splitlines():
    s = line.strip()
    if re.match(r"(public|private|protected)?\s*(Q_)?(slots|signals|SLOTS|SIGNALS)\s*:", s):
        section = True
        continue
    if re.match(r"(public|private|protected)\s*:", s):
        section = False
        continue
    if section and not s.startswith("//"):
        m = re.match(r".*?(\w+)\s*\(", s)
        if m:
            api.add(m.group(1))

missing = {}
for qml in sorted((root / "qml").rglob("*.qml")):
    for number, line in enumerate(qml.read_text(encoding="utf-8").splitlines(), 1):
        if line.strip().startswith("//"):
            continue
        for name in re.findall(r"(?<![\w\-\"'])veyra\.(\w+)", line):
            if name not in api:
                missing.setdefault(name, []).append(f"{qml.relative_to(root)}:{number}")

for name, places in sorted(missing.items()):
    print(f"missing bridge name veyra.{name}: {', '.join(places[:5])}")
sys.exit(1 if missing else 0)
