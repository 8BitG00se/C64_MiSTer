@echo off
rem  OCTOPHONIC 64 core. Puts this core on the MiSTer (hidden in _Computer, where Computer -
rem  Octophonic 64 finds it), then restarts the MiSTer. It never replaces a NEWER core without
rem  asking, and deletes nothing: the core that was there goes to /media/fat/_Octophonic/old cores.
rem  The password is 1 each time.
cd /d "%~dp0"
set /p ORDER=<core-number.txt
for %%F in (C64_Octophonic_*.rbf) do set "RBF=%%F"
echo Sending the core (%RBF%, core number %ORDER%) ...
scp -o StrictHostKeyChecking=accept-new "%RBF%" install_core.sh root@MiSTer:/tmp/
if errorlevel 1 goto fail
ssh root@MiSTer "sh /tmp/install_core.sh '%RBF%' %ORDER%"
if errorlevel 255 goto fail
if errorlevel 3 goto newer
goto restart
:newer
echo.
set /p ANS=Put this OLDER core in anyway? Y/N 
if /i not "%ANS%"=="Y" goto keep
scp "%RBF%" root@MiSTer:/tmp/
ssh root@MiSTer "sh /tmp/install_core.sh '%RBF%' %ORDER% force"
if errorlevel 1 goto fail
:restart
echo.
echo Restarting the MiSTer ...
ssh root@MiSTer "(sleep 1; reboot) >/dev/null 2>&1 &"
echo Done. In about 15 seconds: the start screen shows the core's name right of OCTOVIC 256,
echo and F1 then F8 shows its name and build date at the top of the settings.
pause
exit /b
:keep
echo Nothing changed - the newer core stays.
pause
exit /b
:fail
echo.
echo That didn't reach the MiSTer - nothing was changed. Check it is on and on the network.
pause
exit /b 1
