#!/usr/bin/env python3
"""
PrismWarp Python Client Example
Demonstrates round-robin and random proxy rotation using PrismWarp SOCKS5 endpoints.
Requirements: pip install requests[socks]
"""

import random
import requests

# Define local PrismWarp proxy pool range
PRISM_PROXIES = [f"socks5h://127.0.0.1:{port}" for port in range(40001, 40013)]

def test_proxy(proxy_url: str):
    proxies = {
        "http": proxy_url,
        "https": proxy_url,
    }
    try:
        response = requests.get(
            "https://cloudflare.com/cdn-cgi/trace",
            proxies=proxies,
            timeout=5,
        )
        data = dict(line.split("=", 1) for line in response.text.strip().split("\n") if "=" in line)
        print(f"[{proxy_url}] -> Egress IP: {data.get('ip')} | Cloudflare Colo: {data.get('colo')}")
    except Exception as e:
        print(f"[{proxy_url}] -> Request Failed: {e}")

if __name__ == "__main__":
    print("Testing random proxy dispatch across PrismWarp pool:")
    for _ in range(5):
        selected_proxy = random.choice(PRISM_PROXIES)
        test_proxy(selected_proxy)
