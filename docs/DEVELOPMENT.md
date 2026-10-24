# CivCityFix: developer notes

End-user documentation: the repository `README.md` and `package/README.txt` (shipped in the zip).

## Layout

| Path | Contents |
|---|---|
| `src/` | `d3d9.dll` proxy: `CivCityFix.cpp`, version resource, `version.h` (single version number) |
| `package/` | Files shipped in the zip: `Install.cmd`, `Uninstall.cmd`, `scripts/`, `files/` (ini, dxvk.conf), README, licenses |
| `third_party/dxvk-3.1.1/` | DXVK license; `package.ps1` downloads the unmodified 32-bit `d3d9.dll` from the official 3.1.1 release (SHA-256 checked) |
| `docs/steam-guide.txt` | Text for the Steam Community guide (Steam BBCode) |
| `build/`, `dist/`, `release/` | Build output (git-ignored) |

## Build and package

- `build.cmd` compiles `dist/d3d9.dll` with the MSVC x86 toolset (Visual Studio C++ build tools).
- `pwsh -File package.ps1` builds and writes `release/CivCityFix-<version>.zip` plus its SHA-256.

To release a new version: bump `src/version.h`, run `package.ps1`, tag the commit `v<version>`,
and attach the zip to a GitHub release.

## How the proxy works

`d3d9.dll` loads `dxvk_d3d9.dll` from the game folder, forwards all exports, and patches three
`IDirect3D9` vtable entries (`GetAdapterModeCount`, `EnumAdapterModes`, `CreateDevice`) plus
`IDirect3DDevice9::Reset`:

- extra display modes (`auto` = 4:3 at the monitor's full height) are appended to the mode list;
- a fullscreen request becomes a windowed device; the game window is made borderless, centered,
  and owned by a black full-screen backdrop window so the bars stay directly behind it.

The installer computes the same `auto` mode (`Get-AutoMode` in `package/scripts/common.ps1`);
keep it in sync with `AutoMode()` in `CivCityFix.cpp`.

## Findings behind the fix

- Stock game: `APPCRASH c0000005` at offset `0x338a5a` inside `CivCity Rome.exe`, ~10 s after
  "Play" (after the NVIDIA D3D9 driver and audio have loaded). With DXVK it does not occur.
  Root cause not identified; the exe is PECompact-packed.
- The startup dialog lists at most 1600x1200; larger modes only work with the dialog disabled.
