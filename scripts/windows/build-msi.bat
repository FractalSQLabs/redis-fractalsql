@echo off
REM scripts/windows/build-msi.bat
REM
REM Packages fractalsql.dll (pre-built by build.bat) plus LICENSE
REM files and a small README into a Windows MSI using the WiX Toolset.
REM
REM One MSI per (Memurai major, arch) pair. The resulting MSI
REM installs into Memurai's default install tree:
REM
REM     C:\Program Files\Memurai\modules\fractalsql.dll
REM     C:\Program Files\Memurai\share\doc\redis-fractalsql\LICENSE
REM     C:\Program Files\Memurai\share\doc\redis-fractalsql\LICENSE-THIRD-PARTY
REM     C:\Program Files\Memurai\share\doc\redis-fractalsql\README.txt
REM     C:\Program Files\Memurai\share\doc\redis-fractalsql\load_module.conf
REM
REM WixUI_InstallDir lets the user retarget the Memurai root. Silent
REM install uses /qn MEMURAIROOT="D:\Memurai" if Memurai was not
REM installed at the default path. A RegistrySearch auto-populates
REM the default from HKLM\SOFTWARE\Memurai\InstallPath when present.
REM
REM If ADDLOADMODULE=1 (default), a deferred custom action appends
REM     loadmodule "<MEMURAIROOT>\modules\fractalsql.dll"
REM to <MEMURAIROOT>\memurai.conf (idempotent — duplicate lines are
REM skipped). ADDLOADMODULE=0 on the msiexec command line suppresses
REM the edit. The installer does NOT restart the Memurai service —
REM that is the operator's responsibility on a shared host.
REM
REM Prerequisites
REM   * WiX Toolset v3.x installed (candle.exe / light.exe on PATH).
REM   * dist\windows\memurai^<MEMURAI_MAJOR^>\fractalsql.dll already
REM     produced by scripts\windows\build.bat.
REM
REM Environment
REM   MEMURAI_MAJOR 4 — selects UpgradeCode and install-folder name
REM   MSI_ARCH      x64 — passed to candle -arch
REM   MSI_VERSION   overrides Product Version (default 1.0.0)

setlocal ENABLEEXTENSIONS ENABLEDELAYEDEXPANSION

set REPO_ROOT=%~dp0..\..
pushd %REPO_ROOT%

if "%MEMURAI_MAJOR%"==""    (
    echo ==^> ERROR: MEMURAI_MAJOR must be set ^(e.g. 4^)
    popd ^& exit /b 1
)
if "%MSI_ARCH%"==""    set MSI_ARCH=x64
if "%MSI_VERSION%"=="" set MSI_VERSION=1.0.0

set DLL=dist\windows\memurai%MEMURAI_MAJOR%\fractalsql.dll
if not exist "%DLL%" (
    echo ==^> ERROR: %DLL% missing — run build.bat with MEMURAI_MAJOR=%MEMURAI_MAJOR% first
    popd ^& exit /b 1
)

REM Per-(major, arch) staging dir so candle can reference a stable
REM "dist\windows\staging-...\fractalsql.dll" path from the wxs. Avoids
REM threading MEMURAI_MAJOR through every File/@Source attribute.
set STAGE=dist\windows\staging-memurai%MEMURAI_MAJOR%-%MSI_ARCH%
if exist "%STAGE%" rmdir /s /q "%STAGE%"
mkdir "%STAGE%"

copy /Y "%DLL%"                 "%STAGE%\fractalsql.dll"     > nul
copy /Y LICENSE                 "%STAGE%\LICENSE"            > nul
copy /Y LICENSE-THIRD-PARTY     "%STAGE%\LICENSE-THIRD-PARTY" > nul
copy /Y scripts\load_module.conf "%STAGE%\load_module.conf"  > nul

REM Per-cell README ships in the MSI so users who only grab the .msi
REM still see the "which Memurai major, which arch" pairing without
REM hopping to GitHub.
(
  echo FractalSQL for Memurai %MEMURAI_MAJOR%, Community Edition %MSI_VERSION%
  echo Architecture: %MSI_ARCH%
  echo.
  echo This MSI installs the fractalsql Redis module DLL into the
  echo canonical Memurai Windows install root:
  echo     C:\Program Files\Memurai\modules\fractalsql.dll
  echo.
  echo If ADDLOADMODULE=1 ^(default^), the installer appends
  echo     loadmodule "C:\Program Files\Memurai\modules\fractalsql.dll"
  echo to C:\Program Files\Memurai\memurai.conf ^(idempotent^).
  echo The Memurai service is NOT restarted by the installer — do
  echo it yourself when convenient:
  echo     Restart-Service Memurai
  echo.
  echo Verify after restart:
  echo     memurai-cli MODULE LIST
  echo     memurai-cli FRACTALSQL.EDITION       -^> "Community"
  echo     memurai-cli FRACTALSQL.VERSION       -^> "%MSI_VERSION%"
) > "%STAGE%\README.txt"

if not exist obj mkdir obj
REM candle preprocessor can't take a dotted major without escaping;
REM expose two sanitized variants:
REM   MAJOR_TAG   — underscore-safe, used in WiX Ids and filenames
REM   MAJOR_HEX   — 4-digit hex-safe, padded, used inside GUID strings
REM                 which MUST be pure hex [0-9A-F].
set MAJOR_TAG=%MEMURAI_MAJOR:.=_%
if "%MEMURAI_MAJOR%"=="3"   set MAJOR_HEX=0003
if "%MEMURAI_MAJOR%"=="4"   set MAJOR_HEX=0004
if "%MEMURAI_MAJOR%"=="5"   set MAJOR_HEX=0005
if "%MAJOR_HEX%"==""    (
    echo ==^> ERROR: no MAJOR_HEX mapping for MEMURAI_MAJOR=%MEMURAI_MAJOR%
    popd ^& exit /b 1
)
set OBJ=obj\fractalsql-memurai%MAJOR_TAG%-%MSI_ARCH%.wixobj

set MSI=dist\windows\FractalSQL-Memurai-%MEMURAI_MAJOR%-%MSI_VERSION%-%MSI_ARCH%.msi
if not exist "dist\windows" mkdir "dist\windows"

set WXS=scripts\windows\fractalsql.wxs

echo ==^> MEMURAI_MAJOR = %MEMURAI_MAJOR%
echo ==^> MSI_ARCH      = %MSI_ARCH%
echo ==^> MSI_VERSION   = %MSI_VERSION%
echo ==^> STAGE         = %STAGE%
echo ==^> MSI           = %MSI%

REM -arch propagates into $(sys.BUILDARCH) inside the WXS — used
REM there to set <Package Platform="..."/> and keep ICE80 happy
REM about the component/directory bitness pairing.
candle -nologo -arch %MSI_ARCH% ^
    -dMEMURAI_MAJOR=%MEMURAI_MAJOR% ^
    -dMEMURAI_MAJOR_TAG=%MAJOR_TAG% ^
    -dMEMURAI_MAJOR_HEX=%MAJOR_HEX% ^
    -dSTAGE_DIR=%STAGE% ^
    -dMSI_VERSION=%MSI_VERSION% ^
    -out %OBJ% %WXS%
if errorlevel 1 (
    echo ==^> candle failed
    popd ^& exit /b 1
)

light -nologo ^
      -ext WixUIExtension ^
      -ext WixUtilExtension ^
      -out "%MSI%" ^
      %OBJ%
if errorlevel 1 (
    echo ==^> light failed
    popd ^& exit /b 1
)

echo ==^> Built %MSI%
dir "%MSI%"

popd
endlocal
