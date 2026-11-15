# 09 — Local Hosting & Cloudflare Tunnel Guide

This guide explains how to host the ARES backend from your PC so teammates can access both the **Web App** and the **Flutter Tablet App (`ares_tablet`)** — either on the same Wi-Fi/LAN or remotely over the internet.

---

## 1. Start the Backend Server (`0.0.0.0:8000`)

From the **`backend/`** directory in PowerShell:

```powershell
cd backend
.\.venv\Scripts\python.exe -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Verify it is running locally:

```powershell
Invoke-RestMethod http://127.0.0.1:8000/api/v1/health
# Expected: {"status":"ok","service":"ARES"}
```

### Local & Same-Network URLs
- **This PC (Web Browser):** `http://127.0.0.1:8000`
- **Android Emulator (on this PC):** `http://10.0.2.2:8000`
- **Teammates on the same Wi-Fi / LAN:** `http://<YOUR-LAN-IP>:8000`
  - Find your LAN IPv4 address with `ipconfig` (look for `IPv4 Address` under your active Wi-Fi/Ethernet adapter).
  - If teammates on the same Wi-Fi cannot connect, allow inbound **TCP port `8000`** in Windows Defender Firewall.

---

## 2. Share with Remote Teammates (Cloudflare Quick Tunnel)

When teammates are **not** on the same Wi-Fi, use a free Cloudflare Quick Tunnel (no Cloudflare account required).

### One-Time Install (Windows)
```powershell
winget install --id Cloudflare.cloudflared --accept-source-agreements --accept-package-agreements
```

### Start the Tunnel
Keep the uvicorn server from Step 1 running, open a **second** terminal, and run:

```powershell
& "C:\Program Files (x86)\cloudflared\cloudflared.exe" tunnel --url http://127.0.0.1:8000
```
*(If `cloudflared` is already on your `PATH`, you can simply run `cloudflared tunnel --url http://127.0.0.1:8000`.)*

Look for the generated URL in the terminal output:

```text
+--------------------------------------------------------------------------------------------+
|  Your quick Tunnel has been created! Visit it at (it may take some time to be reachable):  |
|  https://<random-subdomain>.trycloudflare.com                                              |
+--------------------------------------------------------------------------------------------+
```

Test the public URL:

```powershell
Invoke-RestMethod https://<random-subdomain>.trycloudflare.com/api/v1/health
```

> [!NOTE]
> A Quick Tunnel URL changes each time you restart `cloudflared`, and stays active only while both `uvicorn` and `cloudflared` remain running on your PC.

---

## 3. Connect Teammate Clients

- **Web App:** Open `https://<random-subdomain>.trycloudflare.com/` in any browser.
- **Flutter App (`ares_tablet`):** Pass the tunnel URL via `--dart-define`:
  ```powershell
  cd ares_tablet
  flutter run --dart-define=ARES_API_BASE=https://<random-subdomain>.trycloudflare.com
  ```
  *(Or build an APK with `flutter build apk --debug --android-skip-build-dependency-validation --dart-define=ARES_API_BASE=https://<random-subdomain>.trycloudflare.com`.)*
