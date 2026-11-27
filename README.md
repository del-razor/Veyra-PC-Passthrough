<!-- Logo goes here once the OverRez mark is final. -->

# OverRez

**Beyond Ultra.**

*New Game+ for Your Graphics.* Real-time frame generation, super resolution, neural rendering
and color grading layered on top of any PC game. It only captures your screen and never touches
the game or its memory.

## What it does

OverRez captures a game window or a whole monitor and plays it back enhanced, in real time, on
your GPU:

- **Frame generation** for smoother motion.
- **Super resolution** for a sharper picture.
- **Neural rendering and denoising** to clean up the image.
- **Color grading** with presets, plus a node editor for full control.
- **Game mode**: the enhanced picture sits over your game while your mouse and keyboard go
  straight to the game. Press **Home** for adjustments and **Ctrl+Alt+Home** to leave.
- **Capture your play**: screenshots, recording, Instant Replay and live translation captions.
- **Streaming ready**: send the enhanced picture to OBS and other streaming apps through the
  OverRez virtual camera (it shows up as "Veyra Virtual Camera").

OverRez is about making games look their best, not about gaining an edge. Because it works only
from what is already on your screen, it adds nothing to the game itself.

## Download

Get the latest version from this repository's **Releases** page and pick the package for your
GPU:

| GPU | Installer | Portable |
| --- | --- | --- |
| NVIDIA | `OverRez-<version>-NVIDIA-win64-setup.exe` | `OverRez-<version>-NVIDIA-win64-portable.zip` |
| AMD | `OverRez-<version>-AMD-win64-setup.exe` | `OverRez-<version>-AMD-win64-portable.zip` |

Requires Windows 11 x64 and DirectX 12. Unzip the portable package into a writable folder and
run **OverRez.exe**. `SHA256SUMS.txt` lists the checksum of every download. The installers are
not code-signed yet.

## How releases are made

- `main` is an unchanged copy of the original Veyra repository's `main`.
- `passthrough` holds the Veyra release OverRez is based on, plus the OverRez changes. Every
  push to it runs `.github/workflows/passthrough-release.yml`, which builds the player on GitHub
  Actions, puts it into the official NVIDIA and AMD packages of that Veyra release
  (`scripts/passthrough/repack.py`), builds the installers and creates a draft release.
- The OverRez version is in `OVERREZ_VERSION`; release notes come from `RELEASE-NOTES.md`.

## Credits and licence

OverRez is based on Veyra by Likely7 and its contributors. Like Veyra, it is free software
under the GNU General Public License v3.0 (see `LICENSE`); third-party components keep their own
licences (see `THIRD_PARTY_NOTICES.md` and `licenses/`).
