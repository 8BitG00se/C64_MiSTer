@echo off
rem OCTOPHONIC - after flashing the Fusion card: updates the MiSTer's front screen to firmware OCTO4, so each demo's own
rem animation (.oled) plays on it. Runs the card's own recipe over the network (step 088). It does NOT restart the
rem MiSTer. THE FRONT SCREEN GOES DARK FOR ABOUT 4 MINUTES - leave it alone. The password is 1 if it asks.
cd /d "%~dp0"
set "HOST=MiSTer"
set "SSHO=-o StrictHostKeyChecking=accept-new"
echo.
echo  OCTOPHONIC - front screen firmware OCTO4
echo  =========================================
echo  The MiSTer is NOT restarted. The FRONT SCREEN goes DARK for about 4 minutes - leave it alone.
echo  Its old firmware is saved first and put back if anything goes wrong.
echo.
pause
ssh %SSHO% root@%HOST% "sh -s" < update-front-screen.sh
if errorlevel 255 goto fail
if errorlevel 1 goto stepfail
echo.
echo Done. Run a demo that has a .oled (Demos - Night City build 3) and watch the front screen.
pause
exit /b
:stepfail
echo.
echo A step stopped (see above). The MiSTer was NOT restarted. The log is octophonic/update.log on the MiSTer.
pause
exit /b 1
:fail
echo.
echo That did not reach the MiSTer - nothing was changed. Check it is on and on the network.
pause
exit /b 1
