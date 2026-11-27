"""Build an OverRez portable ZIP and Setup EXE on top of an official Veyra package.

The official NVIDIA / AMD portable ZIPs carry the proprietary GPU runtimes and
models that OverRez reuses. Everything else comes from this repository's build:
the launcher (OverRez.exe), the app (OverRezApp.exe), its QML (qml/OverRez) and
the virtual camera. Veyra's own files (launcher, updater, startup music, promo
art, developer docs, the update trust file, the manifest of the updater) are
left out, and the package text files are written for OverRez.

usage: python repack.py --official-zip Z --build B --output O --iscc ISCC --work W
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

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
UPSTREAM_PLAYER = "veyra_qml_ui.exe"
PLAYER = "OverRezApp.exe"
LAUNCHER = "OverRez.exe"
MARKER = "OVERREZ_PORTABLE_V1"
# Upstream files and folders OverRez does not ship, relative to the package root
# (top) or to the version folder (version).
DROP_TOP = ["Veyra.exe", "START-HERE.txt", "portable-update-trust.json"]
DROP_VERSION = ["veyra_qml_ui.exe", "veyra_update_worker.exe", "package-manifest.json", "GPU-PACKAGE.txt",
                "assets", "media", "docs", "i18n", "qml/Veyra", "virtualcam", "runtime/magewell",
                "licenses/capture", "licenses/magewell", "licenses/moonlight", "licenses/FFMPEG-VEYRA-BUILD.json",
                "licenses/gpu-dis/VEYRA_INTEGRATION.md"]
DROP_VERSION_GLOBS = ["README*.md", "RELEASE_*.md"]
# Upstream files OverRez keeps under its own name (the app looks for the new names).
RENAME_VERSION = {"runtime/amd-nr-rdna3/veyra_amd_nr_worker.exe": "runtime/amd-nr-rdna3/overrez_amd_nr_worker.exe",
                  "runtime/amd-nr-rdna3/veyra-rdna3-runtime-manifest.json": "runtime/amd-nr-rdna3/rdna3-runtime-manifest.json",
                  "licenses/rdna3-nvapi/VEYRA-CHANGES.txt": "licenses/rdna3-nvapi/CHANGES.txt"}
PRODUCT = "OverRez"
PRODUCT_VERSION = (ROOT / "OVERREZ_VERSION").read_text(encoding="utf-8").split()[0]


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


def remove(path):
    if path.is_dir():
        shutil.rmtree(path)
    elif path.exists():
        path.unlink()


def compose(top, upstream_version, build, dll_dirs):
    """Turn the unpacked official package into the OverRez layout; returns the version folder."""
    flavor = (top / "portable-package.txt").read_text().splitlines()[1].strip()
    if flavor not in ("NVIDIA", "AMD"):
        raise ValueError(f"unexpected package flavor {flavor!r}")
    source_dir = top / "versions" / upstream_version
    if not (source_dir / UPSTREAM_PLAYER).is_file():
        raise ValueError(f"{UPSTREAM_PLAYER} not found in {source_dir}")
    for name in DROP_TOP:
        remove(top / name)
    for name in DROP_VERSION:
        remove(source_dir / name)
    for pattern in DROP_VERSION_GLOBS:
        for match in source_dir.glob(pattern):
            remove(match)
    for old, new in RENAME_VERSION.items():
        if (source_dir / old).exists():
            (source_dir / old).rename(source_dir / new)
    version_dir = top / "versions" / PRODUCT_VERSION
    if version_dir != source_dir:
        source_dir.rename(version_dir)
    shutil.copy2(build / LAUNCHER, top / LAUNCHER)
    shutil.copy2(build / PLAYER, version_dir / PLAYER)
    shutil.copytree(build / "qml/OverRez", version_dir / "qml/OverRez")
    camera = version_dir / "virtualcam"
    camera.mkdir()
    for name in ("overrez-virtualcam64.dll", "overrez-virtualcam32.dll", "overrez-camera-setup.exe"):
        shutil.copy2(build / "virtualcam" / name, camera / name)
    add_missing_dlls(version_dir, version_dir / PLAYER, [build] + dll_dirs)
    (top / "portable-package.txt").write_bytes(f"{MARKER}\n{flavor}\n".encode("ascii"))
    (top / "current-version.txt").write_bytes(f"{PRODUCT_VERSION}\n\n".encode("ascii"))
    leftovers = [p.relative_to(top).as_posix() for p in top.rglob("*")
                 if "veyra" in p.name.lower() and not p.is_dir()]
    if leftovers:
        raise ValueError("files still named after Veyra: " + ", ".join(leftovers))
    return flavor, version_dir


def write_zip(top, destination):
    with zipfile.ZipFile(destination, "x", zipfile.ZIP_DEFLATED, compresslevel=6, allowZip64=True) as bundle:
        for source in sorted(top.rglob("*")):
            if source.is_file():
                bundle.write(source, source.relative_to(top.parent).as_posix())


FUCHSIA = (255, 0, 170)
CYAN = (0, 229, 255)


def _font(size):
    """A fat geometric sans from the Windows font folder, else PIL's default."""
    fonts = Path(os.environ.get("SystemRoot", r"C:\Windows")) / "Fonts"
    for name in ("segoeuib.ttf", "arialbd.ttf", "seguibl.ttf"):
        if (fonts / name).is_file():
            return ImageFont.truetype(str(fonts / name), size)
    return ImageFont.load_default()


def _gradient(size):
    """Fuchsia to cyan, top-left to bottom-right."""
    width, height = size
    image = Image.new("RGB", size)
    pixels = image.load()
    for y in range(height):
        for x in range(width):
            f = (x / max(1, width - 1) + y / max(1, height - 1)) / 2
            pixels[x, y] = tuple(int(a + (b - a) * f) for a, b in zip(FUCHSIA, CYAN))
    return image


def _gradient_text(canvas, text, font, centre_y):
    draw = ImageDraw.Draw(canvas)
    box = draw.textbbox((0, 0), text, font=font)
    w, h = box[2] - box[0], box[3] - box[1]
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).text((-box[0], -box[1]), text, font=font, fill=255)
    canvas.paste(_gradient((w, h)), ((canvas.width - w) // 2, centre_y - h // 2), mask)


def compose_branding(directory):
    """Installer artwork: the OverRez name and tagline until the final logo exists."""
    panel = Image.new("RGB", (492, 1050), (10, 8, 18))
    _gradient_text(panel, "OverRez", _font(96), 470)
    tagline = _font(40)
    draw = ImageDraw.Draw(panel)
    box = draw.textbbox((0, 0), "Beyond Ultra.", font=tagline)
    draw.text(((panel.width - (box[2] - box[0])) // 2, 560), "Beyond Ultra.", font=tagline, fill=(235, 235, 245))
    destination = directory / "brand-panel.png"
    panel.save(destination)
    icon = Image.new("RGB", (174, 174), (10, 8, 18))
    _gradient_text(icon, "OR", _font(92), 87)
    small = directory / "brand-icon.png"
    icon.save(small)
    return destination, small


def entry(source, folder, name=None):
    rename = f'; DestName: "{name}"' if name else ""
    return f'Source: "{source}"; DestDir: "{{app}}{folder}"{rename}; Flags: ignoreversion'


def build_setup(top, flavor, iscc, output, work):
    directory = Path(tempfile.mkdtemp(prefix="iscc-", dir=work))
    (directory / "overrez-installation.txt").write_bytes(f"OverRez.Win64.{flavor}".encode("ascii"))
    version_dir = rf"\versions\{PRODUCT_VERSION}"
    files = [entry(directory / "overrez-installation.txt", ""),
             entry(iscc.parent / "license.txt", version_dir + r"\licenses", "INNO-SETUP.txt")]
    skip = {"current-version.txt"}
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
    defines = dict(Flavor=flavor, AppVersion=PRODUCT_VERSION, OutputDir=out, PayloadList=payload,
                   AppIcon=ROOT / "assets/overrez.ico", BrandBackground=ROOT / "qml/OverRez/backdrop.png",
                   BrandPanel=panel, BrandIcon=icon)
    command = [str(iscc), "/Qp"] + [f"/D{k}={str(v).replace('/', os.sep)}" for k, v in defines.items()]
    command.append(str(ROOT / "scripts/installer/OverRez.iss"))
    subprocess.run(command, cwd=directory, check=True, timeout=1800)
    name = f"{PRODUCT}-{PRODUCT_VERSION}-{flavor}-win64-setup.exe"
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
    upstream_version = (top / "current-version.txt").read_text().splitlines()[0].strip()
    flavor, _ = compose(top, upstream_version, args.build, args.dll_dir)
    stem = f"{PRODUCT}-{PRODUCT_VERSION}-{flavor}-win64-portable"
    renamed = top.with_name(stem)
    top.rename(renamed)
    top = renamed
    zip_out = args.output / f"{stem}.zip"
    write_zip(top, zip_out)
    setup = build_setup(top, flavor, args.iscc, args.output, args.work)
    print(json.dumps(dict(zip=str(zip_out), setup=str(setup), flavor=flavor, version=PRODUCT_VERSION,
                          runtime=upstream_version)))


if __name__ == "__main__":
    main()
