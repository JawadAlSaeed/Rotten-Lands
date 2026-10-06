@echo off
rem Starts the game. The console window shows errors and logs.
rem Imports new or changed files first, so dropped-in art and sounds just work.
setlocal
if "%GODOT%"=="" set "GODOT=C:\Users\Drago\Godot\Godot_v4.7.2-stable_win64_console.exe"
cd /d "%~dp0"
"%GODOT%" --headless --path . --import >nul 2>&1
"%GODOT%" --path . %*
