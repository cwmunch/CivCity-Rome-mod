CivCityFix __VERSION__ - CivCity: Rome on Windows 10/11
=======================================================

Unofficial fan fix. Not affiliated with or endorsed by Firefly Studios, Firaxis Games or 2K.
Contains no game files.

Project page, downloads and bug reports: https://github.com/cwmunch/CivCity-Rome-mod

WHAT IT FIXES
-------------
* Startup crash: on modern Windows and graphics drivers the game closes about ten seconds
  after you press "Play". CivCityFix runs the game's Direct3D 9 graphics through DXVK
  (Direct3D 9 -> Vulkan), which avoids the crash.
* Stretched picture on widescreen and ultrawide monitors: the game is shown as a sharp
  4:3 picture at your monitor's full height, centered with black bars. The game really
  renders at that resolution (for example 1920x1440 on a 1440p monitor), so it is not
  an upscaled 1024x768.
* Borderless window instead of exclusive fullscreen: your desktop resolution never
  changes, and Alt+Tab is instant.
* Vertical sync, so the old renderer does not keep your graphics card at full load.

REQUIREMENTS
------------
* CivCity: Rome, Steam version (tested with Steam build 250770). The installer finds the
  Steam folder by itself. Other versions: see "Other install locations".
* Windows 10 or 11.
* A graphics card with Vulkan 1.3 support and current drivers (NVIDIA, AMD and Intel GPUs
  from roughly the last ten years).

INSTALL
-------
1. Close the game.
2. Unpack the zip anywhere (for example your Downloads folder).
3. Double-click Install.cmd.
4. Start CivCity: Rome from Steam as usual.

The installer picks 4:3 at your screen's full height:
  1080p -> 1440x1080   1440p -> 1920x1440   4K (2160p) -> 2880x2160

To choose a resolution yourself, open a command prompt in this folder and run, e.g.:
  Install.cmd -Resolution 1600x1200

The game's own startup dialog cannot show resolutions above 1600x1200 and would replace
yours, so the installer turns it off for larger resolutions. Graphics options inside the
game still work. To get the dialog back, set <settingsDialog enabled="true"/> in
  Documents\CivCity Rome\CivCityRome.GraphicsSettings.xml
(the dialog then limits you to 1600x1200).

UNINSTALL
---------
Double-click Uninstall.cmd. It removes all files the installer added and restores
everything it changed (backups are made during installation).

  Uninstall.cmd -KeepDxvk    keeps only the crash fix (plain DXVK, game's own fullscreen)

OTHER INSTALL LOCATIONS
-----------------------
If the game is not found automatically, the installer asks for the folder that contains
"CivCity Rome.exe". You can also unpack this zip inside the game folder, or run:
  Install.cmd -GamePath "D:\Games\CivCity Rome"
Only the Steam version has been tested.

FILES ADDED TO THE GAME FOLDER
------------------------------
  d3d9.dll                  CivCityFix (borderless window, extra resolutions, loads DXVK)
  dxvk_d3d9.dll             DXVK 3.1.1, 32-bit d3d9.dll, unmodified (renamed)
  dxvk.conf                 DXVK settings (vertical sync)
  CivCityFix.ini            CivCityFix settings
  CivCityFix.install.json   what the installer did (used by the uninstaller)
  CivCityFix.log, CivCity Rome_d3d9.log   log files, useful when reporting problems

SETTINGS (CivCityFix.ini)
-------------------------
  Borderless=1        0 = use the game's real exclusive fullscreen instead
  ExtraModes=auto,1600x1200
                      resolutions offered to the game in addition to your monitor's own

TROUBLESHOOTING
---------------
* "No write access": right-click Install.cmd and choose "Run as administrator".
* Antivirus warnings: d3d9.dll replacements are a common technique for game fixes
  (DXVK, ReShade). The CivCityFix source code is included in the "source" folder.
* Report problems at https://github.com/cwmunch/CivCity-Rome-mod/issues and include
  CivCityFix.log and "CivCity Rome_d3d9.log" from the game folder, plus your Windows
  version, graphics card and monitor resolution.

Tested on: Windows 11, NVIDIA GeForce RTX 3070, 3440x1440 monitor.
Not yet tested: AMD and Intel graphics, the GOG version, multiple monitors.

CREDITS AND LICENSES
--------------------
CivCityFix: MIT license, see LICENSE.txt. Source code in the "source" folder.
DXVK (https://github.com/doitsujin/dxvk): zlib/libpng license, see THIRD-PARTY-NOTICES.txt.
