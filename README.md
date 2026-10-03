<a id="readme-top"></a>

<!-- PROJECT SHIELDS -->
<div align="center">

[![Contributors][contributors-shield]][contributors-url]
[![Forks][forks-shield]][forks-url]
[![Stargazers][stars-shield]][stars-url]
[![Issues][issues-shield]][issues-url]
[![MIT License][license-shield]][license-url]
[![Linux][linux-shield]][linux-url]
[![Go][go-shield]][go-url]
[![Cloudflare][cloudflare-shield]][cloudflare-url]

</div>

<!-- PROJECT LOGO / HERO -->
<br />
<div align="center">
  <h1 align="center">🔮 PrismWarp</h1>

  <p align="center">
    <strong>Ultra-lightweight Cloudflare WARP SOCKS5 Multi-Proxy Pool via Userspace WireGuard & Systemd</strong>
    <br />
    Deploy dozens of clean, isolated IPv6 egress proxies using only <b>~10 MB RAM per instance</b> — eliminating Docker overhead, glibc memory fragmentation, and OOM crashes.
    <br />
    <br />
    <a href="#getting-started"><strong>Quick Start »</strong></a>
    ·
    <a href="#benchmark-comparison">View Benchmarks</a>
    ·
    <a href="#usage">Client Integration</a>
    ·
    <a href="https://github.com/hasanzadekhalil/prismwarp/issues/new?labels=bug&template=bug-report---.md">Report Bug</a>
    ·
    <a href="https://github.com/hasanzadekhalil/prismwarp/issues/new?labels=enhancement&template=feature-request---.md">Request Feature</a>
  </p>
</div>

<!-- TABLE OF CONTENTS -->
<details>
  <summary><strong>Table of Contents</strong></summary>
  <ol>
    <li>
      <a href="#about-the-project">About The Project</a>
      <ul>
        <li><a href="#the-underlying-problem">The Underlying Problem</a></li>
        <li><a href="#the-prismwarp-solution">The PrismWarp Solution</a></li>
        <li><a href="#benchmark-comparison">Benchmark Comparison</a></li>
        <li><a href="#built-with">Built With</a></li>
      </ul>
    </li>
    <li>
      <a href="#getting-started">Getting Started</a>
      <ul>
        <li><a href="#prerequisites">Prerequisites</a></li>
        <li><a href="#one-liner-installation">One-Liner Installation</a></li>
        <li><a href="#manual-installation">Manual Installation</a></li>
      </ul>
    </li>
    <li><a href="#cli-management">CLI Management</a></li>
    <li>
      <a href="#usage">Usage & Client Integrations</a>
      <ul>
        <li><a href="#1-9router--omniroute-api-gateways">9router / OmniRoute Gateway</a></li>
        <li><a href="#2-python-requests">Python (Requests + SOCKS5)</a></li>
        <li><a href="#3-nodejs-fetch">Node.js (SocksProxyAgent)</a></li>
        <li><a href="#4-curl--proxychains">cURL & Proxychains</a></li>
      </ul>
    </li>
    <li><a href="#how-it-works">How It Works</a></li>
    <li><a href="#roadmap">Roadmap</a></li>
    <li><a href="#contributing">Contributing</a></li>
    <li><a href="#license">License</a></li>
    <li><a href="#author--maintainer">Author & Maintainer</a></li>
    <li><a href="#disclaimer">Disclaimer</a></li>
  </ol>
</details>

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

<!-- ABOUT THE PROJECT -->
## About The Project

When deploying multi-account AI reverse proxies, LLM gateways (such as **9router**, **OmniRoute**, or custom Nginx gateways), or web scrapers routing traffic to upstream providers (OpenAI, Anthropic Claude, Google Gemini/Antigravity, DeepSeek), datacenter VPS IPv4 addresses rapidly encounter **HTTP 429 (Rate Limit)** or automated bot-detection blocks.

### The Underlying Problem

To bypass datacenter IP restrictions, engineers frequently attempt two common workarounds:

1. **Serverless Edge Proxies (Vercel / Deno Subhosting):** Quickly exhaust monthly Fast Origin Transfer limits (often capped at 10 GB), resulting in sudden service disruptions or abuse suspensions.
2. **Containerized Cloudflare WARP (`caomingjun/warp` or official `warp-svc` in Docker):**
   - The official Cloudflare WARP client is designed as a desktop daemon. Under continuous Server-Sent Events (SSE) streaming and WebSocket traffic, it suffers from severe C++ heap fragmentation, unreleased TCP/TLS buffers, and glibc arena bloat.
   - Each container consumes **500 MB – 570 MB of RAM**.
   - Running 20 instances consumes **>10.5 GB RAM**. On a typical 8 GB VPS, this saturates physical memory and 100% of Swap, triggering catastrophic disk I/O thrashing, system freezing, and **Load Averages spiking over 115.0**.

### The PrismWarp Solution

**PrismWarp** replaces the bulky official daemon and Docker containers with a high-performance, userspace WireGuard engine (`wireproxy`) managed natively by Linux `systemd` template units:

* **Zero Kernel Impact:** Operates purely in userspace memory. Requires no `/dev/net/tun` device, no root network namespaces, and no modifications to host routing tables or `iptables`.
* **Ultra-Lightweight Footprint:** Consumes only **~4 MB – 11 MB RAM per instance** (~130 MB total for a 12-proxy pool vs. 6.5 GB in Docker) — an astonishing **98% memory reduction**.
* **Reliable Process Supervisor:** Native `systemd` templates (`prismwarp@01`, `prismwarp@02`, etc.) handle automated crash recovery (`Restart=always`), non-root security boundaries, and zero background daemon overhead.
* **Dedicated Clean Egress:** Each instance binds to a dedicated loopback SOCKS5 port (`127.0.0.1:40001` through `40012`), routing traffic through a unique Cloudflare Anycast IPv6 address (`2a09:bac5:...`).

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## Benchmark Comparison

The following benchmarks were recorded on an 8-Core, 8 GB RAM Ubuntu 24.04 LTS VPS under identical streaming workloads:

| Metric | Docker `caomingjun/warp` (`warp-svc`) | **PrismWarp (`wireproxy` + `systemd`)** | Improvement |
| :--- | :--- | :--- | :--- |
| **RAM per Instance** | ~500 – 570 MB RAM | **~4 – 11 MB RAM** | **~98% Less RAM** |
| **12-Proxy Pool Memory**| ~6,500 MB (6.5 GB) | **~130 MB** | **50x Lower Footprint** |
| **20-Proxy Pool Memory**| >10,500 MB (OOM Crash / Swap 100%)| **~200 MB** | **Runs easily on a $4 VPS** |
| **System Load Average** | Spikes up to **115.0** (I/O Thrash) | **0.02 – 0.12** | **Negligible CPU impact** |
| **TUN/TAP Interface** | Required (`/dev/net/tun`) | **None (Pure Userspace)** | **No kernel privileges** |
| **Container Engine** | Docker + Compose daemon (~200MB) | **None (Native binary + systemd)**| **Zero runtime overhead** |
| **IPv6 Egress Isolation** | Shared or manually bridged | **Isolated per SOCKS5 port** | **Clean Anycast routing** |

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

### Built With

* [![Go][go-shield]][go-url]
* [![Linux][linux-shield]][linux-url]
* [![Bash][bash-shield]][bash-url]
* [![Cloudflare][cloudflare-shield]][cloudflare-url]
* [wireproxy](https://github.com/windtf/wireproxy) (Userspace WireGuard SOCKS5 implementation in Go)
* [wgcf](https://github.com/ViRb3/wgcf) (Cross-platform Cloudflare WARP account generator)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

<!-- GETTING STARTED -->
## Getting Started

### Prerequisites

* Any Linux distribution with `systemd` (Ubuntu 20.04+, Debian 11+, CentOS/RHEL 8+, Fedora, Arch Linux).
* Root or `sudo` access.
* Basic network utilities (`curl`, `tar`, `jq`, `bc` — automatically installed if missing).

### One-Liner Installation

Deploy a full 12-proxy pool on ports `40001–40012` with a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/hasanzadekhalil/prismwarp/main/install.sh | sudo bash
```

### Manual Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/hasanzadekhalil/prismwarp.git
   cd prismwarp
   ```

2. Make scripts executable:
   ```bash
   chmod +x install.sh manage.sh uninstall.sh
   ```

3. Run the interactive installer:
   ```bash
   sudo ./install.sh
   ```
   *Follow the on-screen prompts to choose the number of proxies (default: `12`) and starting port (default: `40001`).*

4. Unattended / Non-Interactive Deployment:
   ```bash
   sudo ./install.sh --count 12 --start-port 40001 --yes
   ```

> **Note on Cloudflare 429 (Too Many Requests):**  
> Cloudflare limits rapid WARP account registrations to ~6 accounts per burst from a single IP. PrismWarp detects this automatically and offers an interactive 5-minute cooldown timer with a live visual countdown, allowing you to resume seamlessly.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

<!-- CLI MANAGEMENT -->
## CLI Management

PrismWarp installs a global management tool located at `/usr/local/bin/prismwarp`:

```bash
prismwarp <command> [arguments]
```

### Command Reference

| Command | Description |
| :--- | :--- |
| `prismwarp status` | Displays live status, individual RAM usage, port mapping, and egress IP for every instance. |
| `prismwarp test` | Concurrently measures round-trip latency, connection health, and Cloudflare colo location. |
| `prismwarp bind <IP>` | Changes listening/bind IP for all proxies (e.g. `0.0.0.0` or Tailscale IP). |
| `prismwarp restart all` | Gracefully restarts all instances in the pool. |
| `prismwarp restart <id>` | Restarts a single instance (e.g. `prismwarp restart 01`). |
| `prismwarp add <N>` | Dynamically generates and boots `N` additional proxies into the active pool. |
| `prismwarp delete <id>` | Stops and removes a proxy instance from the pool (e.g. `prismwarp delete 08`). |
| `prismwarp prune` | Automatically scans and cleans up broken or unconfigured instances. |
| `prismwarp stop all` | Stops all proxy instances. |
| `prismwarp start all` | Starts all proxy instances. |
| `prismwarp logs <id>` | Streams live journald logs for an instance (e.g. `prismwarp logs 01`). |
| `prismwarp export [format]`| Exports proxy endpoints in `list`, `json`, or `9router` format. |

#### Example: `prismwarp status`

```
==============================================================================
INSTANCE   PORT         STATUS       MEMORY       EGRESS IP                     
==============================================================================
warp-01    40001        active       8.4 MB       2a09:bac5:312c:186::816       
warp-02    40002        active       9.1 MB       2a09:bac5:312c:187::421       
warp-03    40003        active       7.8 MB       2a09:bac5:312c:188::190       
warp-04    40004        active       8.9 MB       2a09:bac5:312c:189::552       
...
==============================================================================
Active Pools: 12/12 instances operational
Total Pool Memory Consumption: 104.2 MB RAM (vs ~6000MB in Docker!)
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

<!-- USAGE EXAMPLES -->
## Usage

### 1. 9router / OmniRoute API Gateways

Integrate PrismWarp directly into your LLM routing gateway to distribute requests across isolated Cloudflare IPv6 addresses. 

Export the ready-to-paste JSON snippet:
```bash
prismwarp export 9router
```

Example `9router-config.json`:
```json
{
  "proxyPool": {
    "enabled": true,
    "strategy": "sticky_account",
    "endpoints": [
      { "id": "warp-01", "url": "socks5://127.0.0.1:40001", "weight": 1 },
      { "id": "warp-02", "url": "socks5://127.0.0.1:40002", "weight": 1 },
      { "id": "warp-03", "url": "socks5://127.0.0.1:40003", "weight": 1 }
    ]
  }
}
```

### 2. Python Requests

```python
import random
import requests

# Define local pool endpoints
PROXIES = [f"socks5h://127.0.0.1:{port}" for port in range(40001, 40013)]

def query_endpoint():
    proxy = random.choice(PROXIES)
    resp = requests.get(
        "https://api.openai.com/v1/models",
        headers={"Authorization": "Bearer YOUR_API_KEY"},
        proxies={"http": proxy, "https": proxy},
        timeout=10
    )
    print(f"Routed via {proxy} -> Status: {resp.status_code}")

query_endpoint()
```

### 3. Node.js (Fetch)

```javascript
import { SocksProxyAgent } from 'socks-proxy-agent';

const proxy = 'socks5://127.0.0.1:40001';
const agent = new SocksProxyAgent(proxy);

const response = await fetch('https://cloudflare.com/cdn-cgi/trace', { agent });
const text = await response.text();
console.log(text);
```

### 4. cURL & Proxychains

**cURL:**
```bash
curl --socks5-hostname 127.0.0.1:40001 https://cloudflare.com/cdn-cgi/trace
```

**Proxychains (`/etc/proxychains.conf`):**
```ini
[ProxyList]
socks5 127.0.0.1 40001
socks5 127.0.0.1 40002
```
```bash
proxychains4 curl https://api.ipify.org
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## How It Works

```
                         ┌──────────────────────────────────────────────┐
                         │                  Host VPS                    │
                         │                                              │
  API Request Dispatcher │   ┌──────────────────────────────────────┐   │
 (9router / Python / App)│   │            PrismWarp Pool            │   │
  ───────────────────────┼──>│  Port 40001 ──> prismwarp@01 (Go)    │   │
                         │   │  Port 40002 ──> prismwarp@02 (Go)    │   │
                         │   │  ...                                 │   │
                         │   │  Port 40012 ──> prismwarp@12 (Go)    │   │
                         │   └──────────────────┬───────────────────┘   │
                         └──────────────────────┼───────────────────────┘
                                                │ WireGuard Userspace UDP
                                                ▼ (162.159.192.1:2408)
                         ┌──────────────────────────────────────────────┐
                         │         Cloudflare Edge (WARP Anycast)       │
                         │    Clean Egress: 2a09:bac5:xxxx:xxxx::/64    │
                         └──────────────────────┬───────────────────────┘
                                                │
                                                ▼
                                    Target APIs (OpenAI / Claude)
```

1. **Userspace Tunneling:** `wireproxy` encapsulates outgoing TCP/UDP traffic directly into WireGuard packets using Go's networking stack, bypassing the Linux kernel network stack entirely.
2. **Loopback Binding:** SOCKS5 proxy listeners bind strictly to `127.0.0.1:<PORT>` to prevent unauthorized external access.
3. **Session Affinity:** When used with gateways like 9router, each API account is mapped to a dedicated proxy port. This preserves Cloudflare cache affinity and eliminates rapid token IP hopping.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

<!-- ROADMAP -->
## Roadmap

- [x] Initial release with automated `wireproxy` + `systemd` orchestration
- [x] Cloudflare HTTP 429 rate-limit backoff handler with live countdown timer
- [x] Comprehensive CLI management tool (`prismwarp status/test/add/export`)
- [x] Pre-configured integration snippets (9router, Python, Node.js, Proxychains)
- [ ] Automated daily WARP key rotation daemon
- [ ] Built-in round-robin HAProxy / Envoy load balancer config generator
- [ ] SOCKS5 basic authentication support

See the [open issues](https://github.com/hasanzadekhalil/prismwarp/issues) for a full list of proposed features (and known issues).

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

<!-- CONTRIBUTING -->
## Contributing

Contributions make the open-source community an amazing place to learn, inspire, and create. Any contributions you make are **greatly appreciated**.

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

<!-- LICENSE -->
## License

Distributed under the MIT License. See [`LICENSE`](LICENSE) for more information.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

<!-- AUTHOR & MAINTAINER -->
## Author & Maintainer

**Khalil Hasanzade**

* GitHub: [@hasanzadekhalil](https://github.com/hasanzadekhalil)
* Project Link: [https://github.com/hasanzadekhalil/prismwarp](https://github.com/hasanzadekhalil/prismwarp)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

<!-- DISCLAIMER -->
## Disclaimer

This software is developed and distributed for educational, research, and legitimate API routing/testing purposes only. Users are solely responsible for complying with Cloudflare's [Terms of Service](https://www.cloudflare.com/terms/) and all applicable local, national, and international laws. The author and contributors assume no liability for misuse, abuse, or damages arising from the use of this tool.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

<!-- MARKDOWN LINKS & IMAGES -->
[contributors-shield]: https://img.shields.io/github/contributors/hasanzadekhalil/prismwarp.svg?style=for-the-badge
[contributors-url]: https://github.com/hasanzadekhalil/prismwarp/graphs/contributors
[forks-shield]: https://img.shields.io/github/forks/hasanzadekhalil/prismwarp.svg?style=for-the-badge
[forks-url]: https://github.com/hasanzadekhalil/prismwarp/network/members
[stars-shield]: https://img.shields.io/github/stars/hasanzadekhalil/prismwarp.svg?style=for-the-badge
[stars-url]: https://github.com/hasanzadekhalil/prismwarp/stargazers
[issues-shield]: https://img.shields.io/github/issues/hasanzadekhalil/prismwarp.svg?style=for-the-badge
[issues-url]: https://github.com/hasanzadekhalil/prismwarp/issues
[license-shield]: https://img.shields.io/github/license/hasanzadekhalil/prismwarp.svg?style=for-the-badge
[license-url]: https://github.com/hasanzadekhalil/prismwarp/blob/main/LICENSE
[linux-shield]: https://img.shields.io/badge/Platform-Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black
[linux-url]: https://www.kernel.org/
[go-shield]: https://img.shields.io/badge/Engine-Go_Wireproxy-00ADD8?style=for-the-badge&logo=go&logoColor=white
[go-url]: https://golang.org/
[bash-shield]: https://img.shields.io/badge/Orchestrator-Bash_%26_Systemd-4EAA25?style=for-the-badge&logo=gnu-bash&logoColor=white
[bash-url]: https://www.gnu.org/software/bash/
[cloudflare-shield]: https://img.shields.io/badge/Network-Cloudflare_WARP-F38020?style=for-the-badge&logo=cloudflare&logoColor=white
[cloudflare-url]: https://www.cloudflare.com/
