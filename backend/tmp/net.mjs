import net from "net";
import dns from "dns/promises";

function tcp(host, port, timeout = 10000) {
  return new Promise((resolve) => {
    const s = new net.Socket();
    let done = false;
    const finish = (r) => { if (!done) { done = true; try { s.destroy(); } catch {} resolve(r); } };
    s.setTimeout(timeout);
    s.once("connect", () => finish("CONNECT_OK"));
    s.once("timeout", () => finish("TIMEOUT"));
    s.once("error", (e) => finish("ERR:" + (e.code || e.message)));
    s.connect(port, host);
  });
}

const url = process.env.DATABASE_URL || "";
const m = url.match(/@([^:]+):(\d+)\//);
const dbHost = m ? m[1] : null;
const dbPort = m ? Number(m[2]) : null;
console.log("parsed db host/port:", dbHost, dbPort);

try {
  const a = await dns.lookup(dbHost);
  console.log("DNS", dbHost, "->", a.address);
} catch (e) { console.log("DNS FAIL", e.code); }

console.log("TCP db:", await tcp(dbHost, dbPort));
// control: a well-known always-up TLS host
console.log("TCP google:443:", await tcp("www.google.com", 443));
console.log("TCP railway-generic:443:", await tcp("railway.app", 443));
process.exit(0);
