@echo off
rem OCTOPHONIC - checks a MiSTer card after its first install. Only READS the card, changes nothing.
setlocal enabledelayedexpansion
title Octophonic card check
set D=
for %%L in (D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
  if exist "%%L:\MiSTer" if exist "%%L:\octophonic\os.ini" set D=%%L:
)
if "%D%"=="" (
  echo No installed Octophonic card found.
  echo If you see a drive called OCTOFUSION, the install has not run yet: put the card in the
  echo MiSTer, power on and leave it 10 minutes.
  goto end
)
echo Card found at %D%
echo.
set BAD=0
call :need "%D%\MiSTer"
call :need "%D%\menu.rbf"
call :need "%D%\MiSTer.ini"
call :need "%D%\linux\uboot.img"
call :need "%D%\octophonic\os.ini"
call :need "%D%\octophonic\SHELL.PRG"
call :need "%D%\games\C64\Tools\OCTOCODE.PRG"
call :need "%D%\_Computer\Octophonic 64.mgl"
call :need "%D%\octophonic\oled.sh"
call :need "%D%\tty2oled\S60tty2oled"
call :need "%D%\games\C64\Demos\Night City build 3\Night City.oled"
call :need "%D%\games\C64\Demos\DNA Wave build 3\DNA Wave.oled"
call :need "%D%\games\C64\Demos\Pendulum Wave build 1\Pendulum Wave.oled"
call :need "%D%\games\C64\Demos\Mona Lisa build 1\Mona Lisa.oled"
if exist "%D%\linux\linux.img" (
  for %%F in ("%D%\linux\linux.img") do set SZ=%%~zF
  if "!SZ!"=="393216000" (echo   ok       linux\linux.img  393216000 bytes) else (echo   SHORT    linux\linux.img is !SZ! bytes, should be 393216000 & set BAD=1)
) else (echo   MISSING  linux\linux.img & set BAD=1)
dir /a "%D%\_Computer\.C64_Octophonic*_core8.rbf" >nul 2>&1 && (echo   ok       the Octophonic core - Core 8) || (echo   MISSING  Core 8 in _Computer & set BAD=1)
dir /a "%D%\_Computer\.Octophonic64RGB_*.rbf" >nul 2>&1 && (echo   ok       the Octophonic64RGB core - recolour packs) || (echo   MISSING  the Octophonic64RGB core in _Computer & set BAD=1)
echo.
if "%BAD%"=="0" (echo CARD OK - eject it, put it in the MiSTer and power on.) else (echo HALF INSTALLED - the install was cut short. Flash the image again and leave the MiSTer 10 minutes on first power-on.)
goto end
:need
if exist %1 (echo   ok       %~1) else (echo   MISSING  %~1 & set BAD=1)
exit /b
:end
echo.
pause
