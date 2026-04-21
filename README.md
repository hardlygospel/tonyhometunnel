# 🏠 Tony's Home Tunnel

[![Stars](https://img.shields.io/github/stars/hardlygospel/home-proxy-tunnel?style=for-the-badge&color=yellow)](https://github.com/hardlygospel/home-proxy-tunnel/stargazers) [![Forks](https://img.shields.io/github/forks/hardlygospel/home-proxy-tunnel?style=for-the-badge&color=blue)](https://github.com/hardlygospel/home-proxy-tunnel/network/members) [![Issues](https://img.shields.io/github/issues/hardlygospel/home-proxy-tunnel?style=for-the-badge&color=red)](https://github.com/hardlygospel/home-proxy-tunnel/issues) [![Last Commit](https://img.shields.io/github/last-commit/hardlygospel/home-proxy-tunnel?style=for-the-badge&color=green)](https://github.com/hardlygospel/home-proxy-tunnel/commits) [![License](https://img.shields.io/badge/License-GPL_v3-blue?style=for-the-badge)](https://github.com/hardlygospel/home-proxy-tunnel/blob/main/LICENSE) [![macOS](https://img.shields.io/badge/macOS-supported-brightgreen?style=for-the-badge&logo=apple)](https://github.com/hardlygospel/home-proxy-tunnel) [![Linux](https://img.shields.io/badge/Linux-supported-brightgreen?style=for-the-badge&logo=linux)](https://github.com/hardlygospel/home-proxy-tunnel) [![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=for-the-badge&logo=gnubash)](https://github.com/hardlygospel/home-proxy-tunnel) [![Docker](https://img.shields.io/badge/Docker-ready-2496ED?style=for-the-badge&logo=docker)](https://github.com/hardlygospel/home-proxy-tunnel) [![Maintained](https://img.shields.io/badge/Maintained-yes-brightgreen?style=for-the-badge)](https://github.com/hardlygospel/home-proxy-tunnel) [![Repo Size](https://img.shields.io/github/repo-size/hardlygospel/home-proxy-tunnel?style=for-the-badge)](https://github.com/hardlygospel/home-proxy-tunnel) [![Code Size](https://img.shields.io/github/languages/code-size/hardlygospel/home-proxy-tunnel?style=for-the-badge)](https://github.com/hardlygospel/home-proxy-tunnel)
### *Browse from anywhere through your home connection*

> A reverse HTTPS proxy tunnel that lets you browse the web through your home internet from work or your phone — no router changes, no static IP, no paid services. 🌐

---

## 🔗 How It Works

```
[Work PC / Phone]  →  HTTPS  →  [Cloudflare Edge]
                                       ↓ tunnel
                              [Your Mac at Home]
                                       ↓
                              [Python HTTP Proxy]
                                       ↓
                              [The Open Internet]
```

- 🖥️ Your Mac runs a local HTTP proxy (port 8888)
- ☁️ Cloudflare Tunnel punches out through your firewall and gives you a free `*.trycloudflare.com` HTTPS URL
- 🔀 Point your work browser/phone proxy settings at that URL
- ✅ All traffic routes through your home internet

No port-forwarding needed. No static IP needed. Free.

---

## ⚡ Quick Start

1. Double-click **HomeTunnel.command** in Finder (or run `bash home_tunnel.sh` in Terminal)
2. Wait ~10 seconds for the green box to appear:

```
╔══════════════════════════════════════════════════════╗
║  ✅  TUNNEL IS LIVE!                                 ║
╠══════════════════════════════════════════════════════╣
║  Proxy URL:                                          ║
║  https://sunny-bird-1234.trycloudflare.com           ║
╚══════════════════════════════════════════════════════╝
```

3. Copy the hostname (e.g. `sunny-bird-1234.trycloudflare.com`)
4. Leave the Terminal window open — closing it stops the tunnel

> ⚠️ The URL changes every time you restart the script. Paste it somewhere handy.

---

## 🛠️ One-Time Setup

### 1️⃣ Download the HomeTunnel folder
Put the `HomeTunnel` folder anywhere convenient — Desktop is fine.

### 2️⃣ Make the script executable
```bash
chmod +x ~/Desktop/HomeTunnel/HomeTunnel.command
```

### 3️⃣ Allow it in macOS Security
First run will be blocked — go to **System Settings → Privacy & Security** and click **"Open Anyway"**.

### 4️⃣ Let Homebrew install (first run only)
If you don't have Homebrew or `cloudflared`, the script installs them automatically (~2 minutes).

---

## 💻 Connecting From Your Devices

### 🍎 macOS
**System Settings → Network → \[connection\] → Details → Proxies**
- Tick **Secure Web Proxy (HTTPS)**
- Server: `sunny-bird-1234.trycloudflare.com` Port: `443`

### 🪟 Windows 10/11
**Settings → Network & Internet → Proxy → Manual proxy setup**
- Address: `sunny-bird-1234.trycloudflare.com` Port: `443`

### 🌐 Chrome / Firefox (browser-only)
**Chrome:** Install **Proxy SwitchyOmega** → New profile → Protocol: HTTPS → your hostname, port 443

**Firefox:** Settings → Network Settings → Manual proxy → HTTPS Proxy: your hostname, port 443

### 📱 iPhone
**Settings → Wi-Fi → (i) → HTTP Proxy → Manual**
- Server: `sunny-bird-1234.trycloudflare.com`
- Port: `443`

### 🤖 Android
**Settings → Wi-Fi → Long-press network → Modify → Advanced → Proxy: Manual**
- Hostname: `sunny-bird-1234.trycloudflare.com`
- Port: `443`

---

## ✅ Requirements

- 🍎 macOS (your home machine)
- 🐳 No router changes needed — Cloudflare Tunnel is outbound-only

You do **not** need to:
- Forward any ports on your router
- Set up a static IP or DDNS
- Open any firewall rules

The only requirement is that your Mac is on and the tunnel window is open.

---

## 😴 Keep Your Mac Awake

macOS may sleep and kill the tunnel. Prevent it:

```bash
caffeinate -dims &
```

Or in **System Settings → Battery → Prevent Mac from sleeping automatically: ON**

---

## 🔗 Optional: Permanent URL

The free URL changes on every restart. For a permanent subdomain:

1. Sign up free at [dash.cloudflare.com](https://dash.cloudflare.com)
2. Run: `cloudflared tunnel login`
3. Run: `cloudflared tunnel create home-proxy`
4. Edit `home_tunnel.sh` and replace the cloudflared line with:
   ```bash
   cloudflared tunnel run --url http://127.0.0.1:$PROXY_PORT home-proxy
   ```

---

## 🔍 Troubleshooting

| Problem | Fix |
|---|---|
| Script says "port in use" | Run `PROXY_PORT=9999 bash home_tunnel.sh` |
| No URL after 30 sec | Check internet connection; try again |
| Proxy works but slow | Normal — traffic routes via Cloudflare servers |
| Site says "proxy error" | That site blocks proxy traffic — try a VPN instead |
| iPhone proxy not working | Ensure port is `443`, not `8888` |
| Work blocks trycloudflare.com | Use a permanent named tunnel (see above) |

**Full logs:** `~/Library/Logs/HomeTunnel/tunnel.log`

---

## 🔒 Security Notes

- 🔑 The tunnel URL is open to anyone who knows it — don't share it publicly
- 🔐 Traffic between you and Cloudflare is encrypted (HTTPS/TLS 1.3)
- 🛡️ For extra security, add HTTP Basic Auth via `cloudflared` credentials

---

## 📄 Licence

This project is licensed under the **GNU General Public License v3.0**.

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg?style=for-the-badge)](https://github.com/hardlygospel/jellyfin-mediastack/blob/main/LICENSE)

You are free to use, modify, and distribute this software under the terms of the GPL-3.0. See the [full licence](https://github.com/hardlygospel/jellyfin-mediastack/blob/main/LICENSE) for details.
