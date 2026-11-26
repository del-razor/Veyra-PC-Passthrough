"""Repack an official Veyra portable ZIP with this fork's player build.

The official NVIDIA / AMD portable ZIPs carry the proprietary GPU runtimes,
models and the launcher/updater. This fork changes only the player
(veyra_qml_ui.exe and its QML), so each official package is opened, the
player and qml/Veyra are replaced with the fork's build, the publisher
manifest is refreshed for the replaced files, and the same-named portable
ZIP plus a Setup EXE (scripts/installer/Veyra.iss) are produced.

usage: python repack.py --official-zip Z --build B --output O --iscc ISCC [--work W]
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile

from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[2]
PLAYER = "veyra_qml_ui.exe"
PRODUCT = "Veyra-PLUS"
MANIFEST = "package-manifest.json"


def digest(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def extract(zip_path, destination):
    with zipfile.ZipFile(zip_path) as bundle:
        bundle.extractall(destination)
    tops = [p for p in destination.iterdir()]
    if len(tops) != 1 or not tops[0].is_dir():
        raise ValueError(f"expected one top-level folder in {zip_path.name}")
    return tops[0]


def dependents(binary):
    """DLL names a PE file imports, from MSVC's dumpbin."""
    out = subprocess.run(["dumpbin", "/nologo", "/dependents", str(binary)], capture_output=True,
                         text=True, check=True).stdout
    names, inside = [], False
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("Image has the following"):
            inside = True
            continue
        if inside:
            if not line:
                if names:
                    break
                continue
            if line.lower().endswith(".dll"):
                names.append(line)
            else:
                break
    return names


def add_missing_dlls(version_dir, start, dll_dirs):
    """Copy every DLL the rebuilt player needs that the official package lacks."""
    system = Path(os.environ.get("SystemRoot", r"C:\Windows")) / "System32"
    present = {p.name.lower() for p in version_dir.iterdir() if p.is_file()}
    added, queue, seen = [], [start], set()
    while queue:
        binary = queue.pop()
        for name in dependents(binary):
            key = name.lower()
            if key in seen or key.startswith(("api-ms-", "ext-ms-")):
                continue
            seen.add(key)
            if key in present:
                continue
            if (system / name).is_file():
                continue
            source = next((d / name for d in dll_dirs if (d / name).is_file()), None)
            if source is None:
                raise FileNotFoundError(f"{binary.name} needs {name}, which is neither in the package nor in {dll_dirs}")
            shutil.copy2(source, version_dir / source.name)
            present.add(key)
            added.append(source.name)
            queue.append(version_dir / source.name)
    print("added DLLs:", ", ".join(added) or "none")
    return added


def replace_player(version_dir, build, dll_dirs):
    shutil.copy2(build / PLAYER, version_dir / PLAYER)
    added = add_missing_dlls(version_dir, version_dir / PLAYER, [build] + dll_dirs)
    built_qml = build / "qml/Veyra"
    target_qml = version_dir / "qml/Veyra"
    if built_qml.is_dir():
        if target_qml.exists():
            shutil.rmtree(target_qml)
        shutil.copytree(built_qml, target_qml)
    manifest_path = version_dir / MANIFEST
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    rows = []
    for row in manifest["files"]:
        source = version_dir / row["path"]
        if row["path"].startswith("qml/Veyra/") or not source.is_file():
            continue
        if row["path"] == PLAYER:
            row = dict(row, size=source.stat().st_size, sha256=digest(source))
        rows.append(row)
    for name in added:
        source = version_dir / name
        rows.append(dict(path=name, size=source.stat().st_size, sha256=digest(source)))
    for source in sorted(target_qml.rglob("*")):
        if source.is_file():
            rows.append(dict(path=source.relative_to(version_dir).as_posix(),
                             size=source.stat().st_size, sha256=digest(source)))
    manifest["files"] = rows
    manifest["fork"] = dict(repository=os.environ.get("GITHUB_REPOSITORY", ""),
                            commit=os.environ.get("GITHUB_SHA", ""),
                            note="Player rebuilt with the screen capture game mode (mouse passthrough) restored.")
    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf8")


def write_zip(top, destination):
    with zipfile.ZipFile(destination, "x", zipfile.ZIP_DEFLATED, compresslevel=6, allowZip64=True) as bundle:
        for source in sorted(top.rglob("*")):
            if source.is_file():
                bundle.write(source, source.relative_to(top.parent).as_posix())


def compose_branding(directory):
    art = ROOT / "qml/Veyra"
    panel = ImageOps.fit(Image.open(art / "backdrop-dusk-strong.png").convert("RGBA"),
                         (492, 1050), centering=(0.62, 0.52))
    sun = Image.open(art / "intro-sun.png").convert("RGBA")
    sun.thumbnail((326, 326), Image.Resampling.LANCZOS)
    sun.putalpha(sun.getchannel("A").point(lambda value: int(value * 0.57)))
    panel.alpha_composite(sun, ((panel.width - sun.width) // 2, 164))
    wordmark = Image.open(art / "wordmark-dusk.png").convert("RGBA")
    wordmark.thumbnail((392, 390), Image.Resampling.LANCZOS)
    panel.alpha_composite(wordmark, ((panel.width - wordmark.width) // 2, 374))
    destination = directory / "brand-panel.png"
    panel.convert("RGB").save(destination)
    mark = Image.open(art / "logo-dusk.png").convert("RGBA")
    mark.thumbnail((156, 116), Image.Resampling.LANCZOS)
    icon = Image.new("RGBA", (174, 174), (0, 0, 0, 0))
    icon.alpha_composite(mark, ((icon.width - mark.width) // 2, (icon.height - mark.height) // 2))
    small = directory / "brand-icon.png"
    icon.save(small)
    return destination, small


def entry(source, folder, name=None):
    rename = f'; DestName: "{name}"' if name else ""
    return f'Source: "{source}"; DestDir: "{{app}}{folder}"{rename}; Flags: ignoreversion'


def build_setup(top, version, flavor, iscc, output, work):
    directory = Path(tempfile.mkdtemp(prefix="iscc-", dir=work))
    (directory / "veyra-installation.txt").write_bytes(f"VeyraPLUS.Win64.{flavor}".encode("ascii"))
    version_dir = rf"\versions\{version}"
    files = [entry(directory / "veyra-installation.txt", ""),
             entry(iscc.parent / "license.txt", version_dir + r"\licenses", "INNO-SETUP.txt")]
    skip = {"START-HERE.txt", "current-version.txt"}
    for source in sorted(top.rglob("*")):
        if not source.is_file():
            continue
        relative = source.relative_to(top)
        if len(relative.parts) == 1 and relative.name in skip:
            continue
        parent = str(relative.parent)
        files.append(entry(source, "" if parent == "." else "\\" + parent.replace("/", "\\")))
    payload = directory / "files.iss"
    payload.write_text("\n".join(files) + "\n", encoding="utf-8-sig")
    panel, icon = compose_branding(directory)
    out = directory / "output"
    out.mkdir()
    defines = dict(Flavor=flavor, AppVersion=version, OutputDir=out, PayloadList=payload,
                   AppIcon=ROOT / "assets/veyra.ico", BrandBackground=ROOT / "qml/Veyra/backdrop-dusk.png",
                   BrandPanel=panel, BrandIcon=icon)
    command = [str(iscc), "/Qp"] + [f"/D{k}={str(v).replace('/', os.sep)}" for k, v in defines.items()]
    command.append(str(ROOT / "scripts/installer/Veyra.iss"))
    subprocess.run(command, cwd=directory, check=True, timeout=1800)
    name = f"{PRODUCT}-{version}-{flavor}-win64-setup.exe"
    shutil.move(str(out / name), str(output / name))
    return output / name


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--official-zip", type=Path, required=True)
    parser.add_argument("--build", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--iscc", type=Path, required=True)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--dll-dir", type=Path, action="append", default=[],
                        help="extra folder to take missing runtime DLLs from (repeatable)")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    args.work.mkdir(parents=True, exist_ok=True)
    unpacked = Path(tempfile.mkdtemp(prefix="zip-", dir=args.work))
    top = extract(args.official_zip, unpacked)
    (flavor_line,) = [line for line in (top / "portable-package.txt").read_text().splitlines()[1:2]]
    version = (top / "current-version.txt").read_text().splitlines()[0].strip()
    version_dir = top / "versions" / version
    if not (version_dir / PLAYER).is_file():
        raise ValueError(f"{PLAYER} not found in {version_dir}")
    replace_player(version_dir, args.build, args.dll_dir)
    flavor = flavor_line.strip()
    stem = f"{PRODUCT}-{version}-{flavor}-win64-portable"
    renamed = top.with_name(stem)
    top.rename(renamed)
    top = renamed
    zip_out = args.output / f"{stem}.zip"
    write_zip(top, zip_out)
    setup = build_setup(top, version, flavor, args.iscc, args.output, args.work)
    print(json.dumps(dict(zip=str(zip_out), setup=str(setup), flavor=flavor, version=version)))


if __name__ == "__main__":
    main()
