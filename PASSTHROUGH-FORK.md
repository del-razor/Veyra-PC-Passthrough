# Veyra PC Passthrough fork

This fork follows [Likely7/Veyra-NRVideo](https://github.com/Likely7/Veyra-NRVideo) release by release,
with the same version numbers. Its only change is that Screen Capture keeps its **Game mode**
(mouse passthrough for PC and 3D games), which upstream removed in 2.2.1.

- `main` is an untouched copy of upstream `main`.
- `passthrough` is the upstream release tag plus this fork's changes:
  - a revert of upstream commit `f1c4d3a` ("Route screen capture to viewing and retire game passthrough"),
  - `.github/workflows/passthrough-release.yml` and `scripts/passthrough/repack.py`, which build the
    player on GitHub Actions and put it into the official NVIDIA and AMD packages of the same version.

## Releases

Every push to `passthrough` builds a draft release `vX.Y.Z` with
`Veyra-X.Y.Z-{NVIDIA,AMD}-win64-portable.zip`, `Veyra-X.Y.Z-{NVIDIA,AMD}-win64-setup.exe` and
`SHA256SUMS.txt`. Publishing the draft creates the tag.

Current limits: the rebuilt player has no PS5 Remote Play, Xbox or Moonlight streaming; the
installers are unsigned; the in-app updater still points at the official releases.

## Updating to a new upstream release

1. Sync `main` with upstream.
2. Rebuild `passthrough` from the new upstream tag: cherry-pick this fork's tooling commit, then
   revert `f1c4d3a` again (or re-apply the passthrough if upstream changed that code), and fix conflicts.
3. Push `passthrough`, check the draft release, then publish it.
