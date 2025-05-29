@echo off
REM Get the directory of this script
set SCRIPT_DIR=%~dp0

REM Set SCOOP environment variable to local scoop folder inside script directory
set "SCOOP=%SCRIPT_DIR%\scoop"
set "SCOOP_GLOBAL=%SCRIPT_DIR%\scoop-global"

REM Update PATH to use local scoop shims ONLY (prepend so it takes priority)
set "PATH=%SCOOP%\shims;%PATH%"
echo Local Scoop Enabled.

scoop config
