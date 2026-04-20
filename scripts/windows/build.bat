@echo off
REM scripts/windows/build.bat
REM
REM Builds fractalsql.dll on Windows with the MSVC toolchain using
REM static CRT (/MT) and whole-program optimization (/GL), matching
REM the Linux posture — zero runtime dependency on the Visual C++
REM Redistributable, and zero dependency on libluajit at load time.
REM
REM The Redis Modules ABI (REDISMODULE_APIVER_1) has been stable
REM since Redis 4.0, so one fractalsql.dll covers every Memurai
REM major. We still package one MSI per Memurai major for clean
REM per-major UpgradeCode separation.
REM
REM Prerequisites
REM   * Visual Studio Build Tools (cl.exe on PATH — invoke from a
REM     Developer Command Prompt, or `call vcvarsall.bat ^<arch^>` first).
REM   * A static LuaJIT archive (lua51.lib) built with msvcbuild.bat
REM     static against the same host arch as cl.exe.
REM   * include\redismodule.h pre-staged from the pinned Redis source
REM     tag (see release.yml's "Fetch redismodule.h" step).
REM
REM Environment overrides
REM   LUAJIT_DIR     directory holding lua.h / lualib.h / lauxlib.h
REM                  and the static LuaJIT archive (lua51.lib or
REM                  libluajit-5.1.lib)
REM   MEMURAI_MAJOR  Memurai major being targeted (e.g. 4). Used
REM                  only for OUT_DIR selection; the DLL itself is
REM                  identical across majors.
REM   OUT_DIR        output directory for fractalsql.dll
REM
REM Invocation
REM   set LUAJIT_DIR=%CD%\deps\LuaJIT\src
REM   set MEMURAI_MAJOR=4
REM   set OUT_DIR=dist\windows\memurai4
REM   scripts\windows\build.bat

setlocal ENABLEEXTENSIONS ENABLEDELAYEDEXPANSION

if "%LUAJIT_DIR%"=="" set LUAJIT_DIR=%CD%\deps\LuaJIT\src
if "%MEMURAI_MAJOR%"=="" (
    echo ==^> ERROR: MEMURAI_MAJOR must be set ^(e.g. 4^)
    exit /b 1
)
if "%OUT_DIR%"==""    set OUT_DIR=dist\windows\memurai%MEMURAI_MAJOR%

if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"

echo ==^> LUAJIT_DIR     = %LUAJIT_DIR%
echo ==^> MEMURAI_MAJOR  = %MEMURAI_MAJOR%
echo ==^> OUT_DIR        = %OUT_DIR%

REM LuaJIT's msvcbuild.bat static emits lua51.lib; accept the
REM Makefile-style libluajit-5.1.lib name too if present.
set LUAJIT_LIB=%LUAJIT_DIR%\libluajit-5.1.lib
if not exist "%LUAJIT_LIB%" (
    if exist "%LUAJIT_DIR%\lua51.lib" set LUAJIT_LIB=%LUAJIT_DIR%\lua51.lib
)
if not exist "%LUAJIT_LIB%" (
    echo ==^> ERROR: no LuaJIT static library in %LUAJIT_DIR%
    echo         ^(expected libluajit-5.1.lib or lua51.lib^)
    exit /b 1
)
echo ==^> LUAJIT_LIB     = %LUAJIT_LIB%

REM redismodule.h is the only Redis-side include. The module does
REM not link to any server import lib — Redis / Memurai's MODULE
REM LOAD resolves RedisModule_OnLoad by name via GetProcAddress.
if not exist "include\redismodule.h" (
    echo ==^> ERROR: include\redismodule.h missing — stage it from the pinned
    echo         Redis source tag before invoking build.bat.
    exit /b 1
)
echo ==^> REDISMODULE_H  = %CD%\include\redismodule.h

REM cl.exe flags:
REM   /MT     static CRT (no MSVC runtime DLL dependency)
REM   /GL     whole-program optimization (paired with /LTCG at link)
REM   /O2     optimize for speed
REM   /LD     build a DLL
REM   /DWIN32 /D_WINDOWS /D_CRT_SECURE_NO_WARNINGS
REM
REM The module's sole exported entry point (RedisModule_OnLoad)
REM carries __declspec(dllexport) via the FRACTAL_EXPORT macro in
REM src/module.c, so no .def file is needed. Do NOT #define
REM REDISMODULE_CORE — that macro is for Redis core itself.
REM /std:c11 lets MSVC parse C99+ syntax used in redismodule.h (the
REM bare __attribute__ on RedisModuleEvent_ReplBackup is shimmed out
REM via #define inside module.c; /std:c11 covers the rest, including
REM designated initializers and compound literals).
cl.exe /nologo /MT /GL /O2 /std:c11 ^
    /DWIN32 /D_WINDOWS /D_CRT_SECURE_NO_WARNINGS ^
    /I"%LUAJIT_DIR%" ^
    /Iinclude ^
    /LD src\module.c ^
    /Fo"%OUT_DIR%\\" ^
    /Fe"%OUT_DIR%\fractalsql.dll" ^
    /link /LTCG ^
        "%LUAJIT_LIB%"

if errorlevel 1 (
    echo.
    echo ==^> BUILD FAILED for Memurai %MEMURAI_MAJOR%
    exit /b 1
)

echo.
echo ==^> Built %OUT_DIR%\fractalsql.dll ^(Memurai %MEMURAI_MAJOR%^)
dir "%OUT_DIR%\fractalsql.dll"

endlocal
