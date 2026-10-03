/**
 * PrismWarp Node.js Client Example
 * Demonstrates routing outbound requests through PrismWarp SOCKS5 proxy pool.
 * Requirements: npm install socks-proxy-agent node-fetch
 */

const { SocksProxyAgent } = require('socks-proxy-agent');

// List of active PrismWarp endpoints
const proxies = Array.from({ length: 12 }, (_, i) => `socks5://127.0.0.1:${40001 + i}`);

async function queryViaProxy(proxyUrl) {
  const agent = new SocksProxyAgent(proxyUrl);
  try {
    const res = await fetch('https://cloudflare.com/cdn-cgi/trace', { agent });
    const text = await res.text();
    const ipLine = text.split('\n').find((l) => l.startsWith('ip='));
    const coloLine = text.split('\n').find((l) => l.startsWith('colo='));
    console.log(`[${proxyUrl}] -> ${ipLine} | ${coloLine}`);
  } catch (err) {
    console.error(`[${proxyUrl}] -> Error: ${err.message}`);
  }
}

async function main() {
  console.log('Dispatching concurrent requests through PrismWarp endpoints:');
  for (const proxy of proxies) {
    await queryViaProxy(proxy);
  }
}

main();
