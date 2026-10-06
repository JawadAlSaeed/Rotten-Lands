@echo off
rem Runs every unit test headless (no window). Results are printed below.
setlocal
if "%GODOT%"=="" set "GODOT=C:\Users\Drago\Godot\Godot_v4.7.2-stable_win64_console.exe"
cd /d "%~dp0"
set "LOG=%TEMP%\rotten_lands_tests.log"
echo Importing project files...
"%GODOT%" --headless --path . --import >nul 2>&1
echo Running tests...
"%GODOT%" --headless --path . -s addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json -gexit > "%LOG%" 2>&1
set "RESULT=%ERRORLEVEL%"
type "%LOG%"
findstr /C:"SCRIPT ERROR" /C:"Parse Error" /C:"Ignoring script" /C:"have not been imported" "%LOG%" >nul && set "RESULT=1"
echo.
if "%RESULT%"=="0" (echo ALL TESTS PASSED) else (echo SOME TESTS FAILED - see above)
if not "%1"=="--no-pause" pause
exit /b %RESULT%
