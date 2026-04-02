@echo off
setlocal EnableExtensions

rem =============================================================================
rem bin\cfxlua.cmd  -  CfxLua Standalone Interpreter Wrapper (Windows cmd)
rem =============================================================================
rem Usage:
rem   cfxlua <script.lua> [arg1 arg2 ...]
rem   cfxlua --version
rem   cfxlua --help
rem
rem Environment variables:
rem   CFXLUA_VM        Override path to Lua VM executable
rem   CFXLUA_RUNTIME   Override path to runtime\ directory
rem   CFXLUA_RESOURCE  Resource name override
rem =============================================================================

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "PROJECT_DIR=%%~fI"

if defined CFXLUA_VM (
    set "VM_BIN=%CFXLUA_VM%"
    goto :vm_selected
)

if exist "%PROJECT_DIR%\vm\build\cfxlua-vm.exe" (
    set "VM_BIN=%PROJECT_DIR%\vm\build\cfxlua-vm.exe"
    goto :vm_selected
)

if exist "%PROJECT_DIR%\vm\build\lua.exe" (
    set "VM_BIN=%PROJECT_DIR%\vm\build\lua.exe"
    goto :vm_selected
)

for %%I in (cfxlua-vm.exe cfxlua-vm lua54.exe lua54 lua.exe lua) do (
    if not defined VM_BIN (
        for /f "delims=" %%P in ('where %%I 2^>NUL') do (
            if not defined VM_BIN set "VM_BIN=%%P"
        )
    )
)

:vm_selected
if not defined VM_BIN (
    echo [cfxlua] FATAL: no Lua interpreter found.
    echo   Set CFXLUA_VM to a Lua executable, or build the VM for Windows.
    exit /b 1
)

if defined CFXLUA_RUNTIME (
    set "RUNTIME_DIR=%CFXLUA_RUNTIME%"
) else (
    set "RUNTIME_DIR=%PROJECT_DIR%\runtime"
)

set "BOOTSTRAP=%RUNTIME_DIR%\bootstrap.lua"
if not exist "%BOOTSTRAP%" (
    echo [cfxlua] FATAL: bootstrap.lua not found at "%BOOTSTRAP%"
    echo   Set CFXLUA_RUNTIME to the correct runtime directory.
    exit /b 1
)

if "%~1"=="--version" goto :show_version
if "%~1"=="-v" goto :show_version
if "%~1"=="--help" goto :show_help
if "%~1"=="-h" goto :show_help
if "%~1"=="" goto :show_help

goto :run_script

:show_version
for /f "tokens=4" %%C in ('chcp') do set "CFXLUA_CP=%%C"
if "%CFXLUA_CP%"=="65001" goto :show_version_utf8
goto :show_version_ascii

:show_version_utf8
echo CfxLua 1.0.0  ·  © 2026 Polaris Naz
<nul set /p "=LuaGLM 5.4  ·  Cfx.re"
goto :show_version_done

:show_version_ascii
echo CfxLua 1.0.0  -  (c) 2026 Polaris Naz
<nul set /p "=LuaGLM 5.4  -  Cfx.re"

:show_version_done
exit /b %ERRORLEVEL%

:show_help
for /f "tokens=4" %%C in ('chcp') do set "CFXLUA_CP=%%C"
if "%CFXLUA_CP%"=="65001" goto :show_help_utf8
goto :show_help_ascii

:show_help_utf8
echo CfxLua 1.0.0  ·  © 2026 Polaris Naz
echo LuaGLM 5.4  ·  Cfx.re
goto :show_help_body

:show_help_ascii
echo CfxLua 1.0.0  -  (c) 2026 Polaris Naz
echo LuaGLM 5.4  -  Cfx.re

:show_help_body
echo.
echo Usage:
echo   cfxlua ^<script.lua^> [arg1 arg2 ...]
echo   cfxlua --version
echo   cfxlua -v
echo   cfxlua --help
echo   cfxlua -h
echo.
echo Arguments:
echo   ^<script.lua^>      Run a Lua script via runtime/bootstrap.lua
echo   [arg1 arg2 ...]   Passed through to the script as arg[1..n]
echo   --version, -v     Print interpreter and VM version banner
echo   --help, -h        Print this help message
echo.
echo Environment:
echo   CFXLUA_VM         Path to Lua VM executable
echo   CFXLUA_RUNTIME    Path to runtime\ directory
echo   CFXLUA_RESOURCE   Resource name override
exit /b 0

:run_script
set "SCRIPT_PATH=%~1"
for %%I in ("%SCRIPT_PATH%") do set "SCRIPT_RESOURCE=%%~nI"

if defined CFXLUA_RESOURCE (
    set "SCRIPT_RESOURCE=%CFXLUA_RESOURCE%"
)

set "CFXLUA_RESOURCE_NAME=%SCRIPT_RESOURCE%"

set "INJECT=__cfx_bootstrapPath = [[%PROJECT_DIR%]]"
"%VM_BIN%" -e "%INJECT%" "%BOOTSTRAP%" %*
exit /b %ERRORLEVEL%
