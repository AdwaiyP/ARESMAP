@echo off
set "PATH=C:\Windows\System32;C:\Windows;C:\Windows\System32\WindowsPowerShell\v1.0;C:\Program Files\Git\cmd;C:\Users\ASUS\flutter\bin;C:\Users\ASUS\AppData\Local\Android\Sdk\platform-tools;C:\Users\ASUS\AppData\Local\Android\Sdk\emulator;%PATH%"
set "JAVA_HOME=C:\Program Files\Java\jdk-21.0.10"
set "ANDROID_HOME=C:\Users\ASUS\AppData\Local\Android\Sdk"

echo [1/4] Starting ares_tablet Android Emulator...
start "" "C:\Users\ASUS\AppData\Local\Android\Sdk\emulator\emulator.exe" -avd ares_tablet

echo [2/4] Waiting for emulator to come online...
"C:\Users\ASUS\AppData\Local\Android\Sdk\platform-tools\adb.exe" wait-for-device

:wait_boot
for /f "delims=" %%i in ('"C:\Users\ASUS\AppData\Local\Android\Sdk\platform-tools\adb.exe" shell getprop sys.boot_completed 2^>nul') do set BOOT=%%i
if not "%BOOT%"=="1" (
    timeout /t 2 /nobreak >nul
    goto wait_boot
)

echo [3/4] Installing ARES MAP Tablet APK...
"C:\Users\ASUS\AppData\Local\Android\Sdk\platform-tools\adb.exe" install -r "%~dp0build\app\outputs\flutter-apk\app-debug.apk"

echo [4/4] Launching ARES MAP on tablet...
"C:\Users\ASUS\AppData\Local\Android\Sdk\platform-tools\adb.exe" shell am start -n com.ares.ares_tablet/.MainActivity
echo Done! ARES MAP is now running on the emulator.

