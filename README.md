# Veyra PLUS

Veyra PLUS is a build of the Veyra real-time GPU video enhancer for Windows (super resolution,
denoising, HDR and frame generation for video files, capture cards and screen capture), released
with the same version numbers as Veyra.

## What is different from Veyra

- **Screen Capture → Game mode is kept.** Mouse passthrough for PC and 3D games works as it did
  in Veyra 2.2.0: choose a borderless game window or monitor, press **Home** for adjustments and
  **Ctrl+Alt+Home** to leave.
- **Classic look only.** The app always uses the Classic colour scheme, with no startup
  animation or startup music.
- **Its own name and install.** Downloads, the installer and the window title say Veyra PLUS,
  and it installs separately from Veyra.

Everything else in each release is the same as the Veyra release with that number.

## Download

Get the latest version from this repository's **Releases** page. Pick the package for the GPU
Veyra PLUS will use:

| GPU | Installer | Portable |
| --- | --- | --- |
| NVIDIA | `Veyra-PLUS-<version>-NVIDIA-win64-setup.exe` | `Veyra-PLUS-<version>-NVIDIA-win64-portable.zip` |
| AMD | `Veyra-PLUS-<version>-AMD-win64-setup.exe` | `Veyra-PLUS-<version>-AMD-win64-portable.zip` |

Requires Windows 11 x64 and DirectX 12. Unzip the portable package into a writable folder and
run **Veyra.exe**. `SHA256SUMS.txt` lists the checksum of every download.

Not included yet: PS5 Remote Play, Xbox and Moonlight streaming, and Magewell capture-card
support. The installers are not code-signed.

## How releases are made

- `main` is an unchanged copy of the original Veyra repository's `main`.
- `passthrough` holds the Veyra release plus the Veyra PLUS changes. Every push to it runs
  `.github/workflows/passthrough-release.yml`, which builds the player on GitHub Actions, puts it
  into the official NVIDIA and AMD packages of the same version
  (`scripts/passthrough/repack.py`), builds the installers, and creates a draft release.
  Release notes come from `PLUS-CHANGES.md` plus the English part of the Veyra notes
  (`scripts/passthrough/release_notes.py`).
- To follow a new Veyra release: sync `main`, rebuild `passthrough` from the new release tag
  with the Veyra PLUS commits on top, push, check the draft, then publish it.

## Credits and licence

Veyra PLUS is based on Veyra by Likely7 and its contributors. Like Veyra, it is free software
under the GNU General Public License v3.0 (see `LICENSE`); third-party components keep their own
licences (see `THIRD_PARTY_NOTICES.md` and `licenses/`).
