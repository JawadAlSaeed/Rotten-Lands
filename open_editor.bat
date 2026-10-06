@echo off
rem Opens this project in the Godot editor.
setlocal
if "%GODOT_EDITOR%"=="" set "GODOT_EDITOR=C:\Users\Drago\Godot\Godot_v4.7.2-stable_win64.exe"
cd /d "%~dp0"
start "" "%GODOT_EDITOR%" --path . -e
