@echo off
rem Builds dist\d3d9.dll (32-bit) with the MSVC x86 toolset found by vswhere.
setlocal
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
for /f "usebackq tokens=*" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSPATH=%%i"
if not defined VSPATH goto novs
set "PATH=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer;%PATH%"
call "%VSPATH%\VC\Auxiliary\Build\vcvarsall.bat" amd64_x86 >nul
if errorlevel 1 goto novs

cd /d "%~dp0"
if not exist dist mkdir dist
if not exist build mkdir build
rc /nologo /fo build\CivCityFix.res src\CivCityFix.rc
if errorlevel 1 exit /b 1
cl /nologo /O2 /MT /EHsc /W3 /DUNICODE /D_UNICODE /D_CRT_SECURE_NO_WARNINGS /LD src\CivCityFix.cpp build\CivCityFix.res /Fobuild\ /Fe:dist\d3d9.dll /link /IMPLIB:build\d3d9.lib user32.lib gdi32.lib
exit /b %errorlevel%

:novs
echo Could not find an MSVC x86 toolset (Visual Studio C++ build tools).
exit /b 1
