# CivCityFix: CivCity: Rome on Windows 10/11

**CivCityFix** is an unofficial fix that makes *CivCity: Rome* (Firefly Studios / Firaxis, 2006) playable on modern PCs.

- **No more startup crash.** On current Windows and graphics drivers the game closes about ten seconds after you press **Play**. CivCityFix runs the game's Direct3D 9 graphics through [DXVK](https://github.com/doitsujin/dxvk) (Direct3D 9 → Vulkan), which avoids the crash.
- **Sharp 4:3 at full screen height.** Instead of being stretched across a widescreen or ultrawide monitor, the game is shown as a centered 4:3 picture with black bars. It really renders at that resolution (e.g. 1920×1440 on a 1440p monitor), so it is not an upscaled 1024×768.
- **Borderless window.** Your desktop resolution never changes, and Alt+Tab is instant.
- **Vertical sync**, so the old renderer doesn't keep your graphics card at full load.

The download contains no game files. You need your own copy of the game.

## Install

1. Download the zip from the [latest release](https://github.com/cwmunch/CivCity-Rome-mod/releases/latest).
2. Close the game and unpack the zip anywhere (for example in Downloads).
3. Double-click **`Install.cmd`**.
4. Start CivCity: Rome from Steam as usual.

The installer finds the game in your Steam library and picks 4:3 at your monitor's full height:

| Monitor | Game resolution |
|---|---|
| 1080p | 1440×1080 |
| 1440p (also 3440×1440 ultrawide) | 1920×1440 |
| 4K | 2880×2160 |

To pick a resolution yourself, run `Install.cmd -Resolution 1600x1200` from a command prompt in the unpacked folder. If the game is installed outside Steam, use `Install.cmd -GamePath "D:\Games\CivCity Rome"`, or unpack the zip inside the game folder.

The game's own startup dialog ("CivCity Rome v1.1") cannot show resolutions above 1600×1200 and would overwrite yours, so the installer turns it off for larger resolutions. The graphics options inside the game still work.

## Uninstall

Double-click **`Uninstall.cmd`**. It removes everything the installer added and restores what it changed (the installer keeps backups and a record in `CivCityFix.install.json`).

`Uninstall.cmd -KeepDxvk` keeps only the crash fix (plain DXVK with the game's own fullscreen).

## Settings

`CivCityFix.ini` in the game folder:

| Setting | Meaning |
|---|---|
| `Borderless=1` | `0` uses the game's real exclusive fullscreen instead of the borderless window |
| `ExtraModes=auto,1600x1200` | Resolutions offered to the game in addition to your monitor's own. `auto` = 4:3 at full monitor height |

DXVK options go in `dxvk.conf` next to it.

## Requirements and compatibility

- CivCity: Rome, Steam version (tested with build 250770)
- Windows 10 or 11
- A graphics card with Vulkan 1.3 support and current drivers

Tested on Windows 11 with an NVIDIA GeForce RTX 3070 and a 3440×1440 monitor. Not yet tested: AMD and Intel graphics, the GOG version, multiple monitors. Reports are very welcome.

## Reporting problems

Open an [issue](https://github.com/cwmunch/CivCity-Rome-mod/issues) and attach `CivCityFix.log` and `CivCity Rome_d3d9.log` from the game folder, plus your Windows version, graphics card and monitor resolution.

- "No write access": right-click `Install.cmd` and choose *Run as administrator*.
- Antivirus warnings: replacing `d3d9.dll` is a common technique for game fixes (DXVK, ReShade). The full source code is in this repository and in the zip.

## How it works

The game loads `d3d9.dll` from its own folder. CivCityFix's `d3d9.dll` loads DXVK (shipped as `dxvk_d3d9.dll`), forwards all calls to it and changes three things:

- extra display modes (such as 1920×1440) are added to the list the game can choose from;
- the game's fullscreen request becomes a windowed device;
- the game window is made borderless and centered on a black full-screen backdrop.

Building from source and packaging: see [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## Credits and license

- CivCityFix: [MIT License](LICENSE), © 2026 Christian Munch.
- [DXVK](https://github.com/doitsujin/dxvk) by Philip Rebohle and contributors, zlib/libpng license (see [third_party/dxvk-3.1.1/LICENSE](third_party/dxvk-3.1.1/LICENSE)). The release zip contains the unmodified 32-bit `d3d9.dll` from DXVK 3.1.1, renamed to `dxvk_d3d9.dll`.

CivCityFix is an unofficial fan project, not affiliated with or endorsed by Firefly Studios, Firaxis Games or 2K. *CivCity: Rome* is a trademark of its respective owners.
