# PrismWarp System Architecture & Design Specification

- **Project Name:** PrismWarp (`prismwarp`)
- **Author & Maintainer:** Khalil Hasanzade
- **Date:** 2026-10-03
- **Status:** Approved
- **Repository Location:** Current working directory (`/root/wireproxy-pool` -> initialized as `prismwarp`)
- **License:** MIT License

---

## 1. Overview & Motivation

### 1.1 The Problem
When routing high-throughput API traffic (e.g. OpenAI, Anthropic, Google Gemini/Antigravity, DeepSeek) through multi-account API routers (such as 9router, OmniRoute, or custom Nginx gateways), standard datacenter VPS IPv4 addresses quickly trigger HTTP 429 (Rate Limit) or automated bot-detection blocks.

Common community workarounds have catastrophic operational limitations:
1. **Serverless Edge Proxies (Vercel / Deno Subhosting):** Suffer from strict monthly Fast Origin Transfer quotas (e.g., 10 GB limit), after which deployments are suspended or incur steep bills.
2. **Containerized Cloudflare WARP (`caomingjun/warp` / official `warp-svc` in Docker):**
   - Accumulates TCP/TLS socket buffers and C++ glibc arena fragmentation under continuous SSE/WebSocket streaming.
   - Memory balloons to **500–570 MB RAM per instance**.
   - On an 8 GB VPS, running 20 instances consumes >10 GB RAM, completely saturating physical memory and Swap, causing extreme disk I/O thrashing, severe system hangs, and Load Averages spiking above **115.0**.

### 1.2 The PrismWarp Solution
PrismWarp replaces heavyweight Docker containers and the official daemon with an ultra-lightweight, userspace WireGuard implementation written in Go (`wireproxy`) orchestrated via native Linux `systemd` template units:
- **Zero Kernel TUN/TAP:** Operates completely in userspace; requires no `/dev/net/tun`, no root network namespaces, and no modifications to host routing tables or `iptables`.
- **Minimal Footprint:** Uses **~4–11 MB RAM per instance** (~130 MB total for 12 instances vs 6.5 GB in Docker) — a **98% memory reduction**.
- **Native Systemd Supervisor:** Employs template units (`prismwarp@.service`) for automatic restart on failure, resource limits, and independent process lifecycle control.
- **Dedicated Clean Egress:** Each instance provides an isolated local SOCKS5 port (e.g. `127.0.0.1:40001..40012`) tunneling to Cloudflare's Anycast edge with a unique IPv6 egress address.

---

## 2. Performance & Benchmark Matrix

| Metric | Docker `caomingjun/warp` (`warp-svc`) | **PrismWarp (`wireproxy` + `systemd`)** | Difference |
| :--- | :--- | :--- | :--- |
| **RAM per Instance** | ~500 – 570 MB | **~4 – 11 MB** | **~98% reduction** |
| **12-Proxy Pool RAM** | ~6,500 MB (6.5 GB) | **~130 MB** | **50x lighter** |
| **20-Proxy Pool RAM** | >10,500 MB (OOM Crash / Swap Saturation)| **~200 MB** | **Stable on 1 GB VPS** |
| **System Load Average**| Spikes up to 115.0 during I/O thrashing | **0.02 – 0.15 (Idle/Normal)** | **Zero CPU waste** |
| **Kernel Requirements**| `CAP_NET_ADMIN`, `/dev/net/tun` device | **None (Pure Userspace)** | **Zero kernel footprint**|
| **Host Routing Impact**| Virtual interfaces created, route risk | **Untouched (Binds to loopback)**| **Completely isolated** |
| **Container Engine** | Docker & Compose daemon required (~200MB)| **None (Native binary + systemd)** | **Zero overhead** |

---

## 3. System Architecture & Components

```
                          ┌──────────────────────────────────────────────┐
                          │                Local Host                    │
                          │                                              │
  Incoming Client Request │  ┌────────────────────────────────────────┐  │
 (9router / Python / Curl)│  │          PrismWarp Pool                │  │
  ───────────────────────┼─>│  Port 40001 -> prismwarp@01 (wireproxy)│  │
                          │  │  Port 40002 -> prismwarp@02 (wireproxy)│  │
                          │  │  ...                                   │  │
                          │  │  Port 40012 -> prismwarp@12 (wireproxy)│  │
                          │  └──────────────────┬─────────────────────┘  │
                          └─────────────────────┼────────────────────────┘
                                                │ WireGuard Userspace UDP
                                                ▼ (Endpoint: 162.159.192.1:2408)
                          ┌──────────────────────────────────────────────┐
                          │        Cloudflare Edge (WARP Anycast)        │
                          │   Clean Egress: 2a09:bac5:... / 2606:4700:... │
                          └─────────────────────┬────────────────────────┘
                                                │
                                                ▼
                                    Target APIs (OpenAI / Claude / etc.)
```

### 3.1 Component Breakdown

1. **`install.sh`**:
   - Zero-dependency interactive and unattended bash installer.
   - Detects system architecture (`amd64` / `arm64`) and required dependencies (`curl`, `tar`, `systemd`, `jq`).
   - Downloads verified release binaries for `wireproxy` (`github.com/windtf/wireproxy`) and `wgcf` (`github.com/ViRb3/wgcf`).
   - Sequentially registers Cloudflare WARP accounts and generates configurations.
   - **Cloudflare HTTP 429 Handler:** If Cloudflare triggers rate limiting during registration, displays an interactive menu:
     1. Start a 5-minute cooldown timer with live visual countdown before auto-resuming.
     2. Finalize and deploy the pool with currently generated accounts.
     3. Abort cleanly.
   - Configures `/etc/prismwarp/configs/warp-{01..N}/wireproxy.conf` with dedicated loopback SOCKS5 ports.
   - Installs and enables the systemd service template `prismwarp@.service`.
   - Runs validation tests across all generated proxies and outputs a summary table.
   - Symlinks `manage.sh` to `/usr/local/bin/prismwarp`.

2. **`manage.sh` (`prismwarp` CLI)**:
   - `prismwarp status`: Displays tabular process health, CPU, memory footprint, port mapping, and assigned egress IPv6.
   - `prismwarp test`: Concurrently queries Cloudflare trace endpoint (`https://cloudflare.com/cdn-cgi/trace`) through every proxy port and prints latency and egress IP.
   - `prismwarp restart [all|ID]`: Gracefully restarts one or all template units.
   - `prismwarp add [N]`: Adds N additional proxies to the pool starting after the highest current port.
   - `prismwarp export [json|list|9router]`: Generates ready-to-copy proxy lists and configuration snippets.

3. **`uninstall.sh`**:
   - Stops and disables all active `prismwarp@*` systemd units.
   - Removes `/etc/systemd/system/prismwarp@.service` and executes `systemctl daemon-reload`.
   - Cleans up `/etc/prismwarp/` configuration directory.
   - Optionally removes `/usr/local/bin/wireproxy`, `/usr/local/bin/wgcf`, and `/usr/local/bin/prismwarp`.

4. **`systemd/prismwarp@.service`**:
   - Template unit executing `/usr/local/bin/wireproxy -c /etc/prismwarp/configs/warp-%i/wireproxy.conf`.
   - Standard security limits (`LimitNOFILE=65535`, `Restart=always`, `RestartSec=2s`).

5. **`examples/`**:
   - `9router-config.json`: Production configuration snippet for 9router.
   - `python_requests.py`: Python snippet demonstrating round-robin request distribution with SOCKS5 proxies.
   - `node_fetch.js`: Node.js script using `socks-proxy-agent`.
   - `proxychains.conf`: Example configuration for command-line proxy tunneling.

6. **`README.md`**:
   - Built adhering to the celebrated `othneildrew/Best-README-Template` structure:
     - Top anchor (`#readme-top`) and centered badges (License, Go, Bash, Systemd, Linux, Cloudflare).
     - Centered logo/ASCII banner, title, tagline, quick links.
     - Collapsible `<details>` Table of Contents.
     - "About The Project" detailing the root problem (Docker memory exhaustion) and the userspace solution.
     - Detailed benchmark comparison table.
     - One-liner curl installer and manual installation guide.
     - Usage guide with client code samples.
     - CLI reference.
     - Contributing guide and Roadmap.
     - MIT License and Author section (Khalil Hasanzade).
     - Legal and educational compliance disclaimer.

---

## 4. File Layout & Standard Paths

```
/root/wireproxy-pool/ (Git Root -> PrismWarp)
├── LICENSE
├── README.md
├── install.sh
├── manage.sh
├── uninstall.sh
├── systemd/
│   └── prismwarp@.service
├── examples/
│   ├── 9router-config.json
│   ├── python_requests.py
│   ├── node_fetch.js
│   └── proxychains.conf
└── docs/
    └── superpowers/specs/
        └── 2026-10-03-prismwarp-design.md

Runtime System Paths:
├── /usr/local/bin/wireproxy
├── /usr/local/bin/wgcf
├── /usr/local/bin/prismwarp (symlink to manage.sh)
├── /etc/systemd/system/prismwarp@.service
└── /etc/prismwarp/
    ├── prismwarp.env
    └── configs/
        ├── warp-01/wireproxy.conf
        ├── warp-02/wireproxy.conf
        └── ...
```

---

## 5. Security & Legal Considerations
- **Non-Privileged Execution:** Once started, `wireproxy` operates entirely within user-space memory without requiring Linux network admin privileges (`CAP_NET_ADMIN`).
- **Loopback Binding:** SOCKS5 listeners bind strictly to `127.0.0.1` by default to prevent unintentional public exposure.
- **Compliance Disclaimer:** The repository explicitly states that the tool is intended for legitimate high-throughput API routing, developer testing, and educational research, and must be used in accordance with Cloudflare's Terms of Service and applicable laws.
