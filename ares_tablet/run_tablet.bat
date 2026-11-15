@echo off
set "PATH=C:\Windows\System32;C:\Windows;C:\Windows\System32\WindowsPowerShell\v1.0;C:\Program Files\Git\cmd;C:\Users\ASUS\flutter\bin;C:\Users\ASUS\AppData\Local\Android\Sdk\platform-tools;C:\Users\ASUS\AppData\Local\Android\Sdk\emulator;%PATH%"
set "JAVA_HOME=C:\Program Files\Java\jdk-21.0.10"
set "ANDROID_HOME=C:\Users\ASUS\AppData\Local\Android\Sdk"
cd /d "%~dp0"
flutter run -d emulator-5554

