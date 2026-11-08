@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

rem 双击运行：找到 Git Bash 后执行同目录的 push.sh
rem 也可以带参数：push.cmd 用户名 仓库名 ghp_xxx --watch

set "BASH="
if exist "%ProgramFiles%\Git\bin\bash.exe" set "BASH=%ProgramFiles%\Git\bin\bash.exe"
if not defined BASH if exist "%ProgramFiles(x86)%\Git\bin\bash.exe" set "BASH=%ProgramFiles(x86)%\Git\bin\bash.exe"
if not defined BASH if exist "%LOCALAPPDATA%\Programs\Git\bin\bash.exe" set "BASH=%LOCALAPPDATA%\Programs\Git\bin\bash.exe"
if not defined BASH for /f "delims=" %%i in ('where bash 2^>nul') do if not defined BASH set "BASH=%%i"

if not defined BASH (
  echo.
  echo 没有找到 Git Bash。
  echo 请先安装 Git for Windows: https://git-scm.com/download/win
  echo 安装时保持默认选项，装完再双击本文件。
  echo.
  pause
  exit /b 1
)

cd /d "%~dp0"
"%BASH%" "%~dp0push.sh" %*

echo.
pause
