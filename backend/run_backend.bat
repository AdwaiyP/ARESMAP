@echo off
set "PATH=C:\Windows\System32;C:\Windows;C:\Windows\System32\WindowsPowerShell\v1.0;C:\Python314;C:\Python314\Scripts;%PATH%"
cd /d "%~dp0"
C:\Python314\python.exe -m uvicorn app.main:app --host 0.0.0.0 --port 8006

