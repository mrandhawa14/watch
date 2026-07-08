// Watch page view-logger.
//   POST /hit   body: {"name": "...", "event": "play"}   -> stores one entry in KV
//   GET  /log?key=SECRET                                 -> shows the log (HTML table)
// The page sends a fire-and-forget beacon on play; you read the log at /log?key=...

const ALLOW_ORIGIN = "https://mrandhawa14.github.io";

function withCors(resp) {
  resp.headers.set("Access-Control-Allow-Origin", ALLOW_ORIGIN);
  resp.headers.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  resp.headers.set("Access-Control-Allow-Headers", "Content-Type");
  return resp;
}

function platformFromUA(ua) {
  ua = ua || "";
  let os = "Unknown", browser = "Unknown";
  if (/iPhone|iPad|iPod/.test(ua)) os = "iPhone/iPad";
  else if (/Android/.test(ua)) os = "Android";
  else if (/Mac OS X/.test(ua)) os = "Mac";
  else if (/Windows/.test(ua)) os = "Windows";
  else if (/Linux/.test(ua)) os = "Linux";
  if (/Edg\//.test(ua)) browser = "Edge";
  else if (/CriOS|Chrome\//.test(ua)) browser = "Chrome";
  else if (/FxiOS|Firefox\//.test(ua)) browser = "Firefox";
  else if (/Safari\//.test(ua)) browser = "Safari";
  return os + " / " + browser;
}

function esc(s) {
  return String(s).replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return withCors(new Response(null, { status: 204 }));
    }

    // Record a view
    if (url.pathname === "/hit" && request.method === "POST") {
      let body = {};
      try { body = JSON.parse((await request.text()) || "{}"); } catch (e) {}
      const ua = request.headers.get("User-Agent") || "";
      const entry = {
        name: String(body.name || "anonymous").slice(0, 60),
        event: String(body.event || "play").slice(0, 20),
        platform: platformFromUA(ua),
        country: request.headers.get("CF-IPCountry") || "??",
        ip: request.headers.get("CF-Connecting-IP") || "",
        time: new Date().toISOString(),
      };
      const key = entry.time + "-" + Math.random().toString(36).slice(2, 8);
      await env.LOGS.put(key, JSON.stringify(entry), { expirationTtl: 60 * 60 * 24 * 365 });
      return withCors(new Response("ok", { status: 200 }));
    }

    // View the log (private — needs the secret)
    if (url.pathname === "/log" && request.method === "GET") {
      if (url.searchParams.get("key") !== env.VIEW_SECRET) {
        return new Response("forbidden", { status: 403 });
      }
      const list = await env.LOGS.list({ limit: 1000 });
      const entries = [];
      for (const k of list.keys) {
        const v = await env.LOGS.get(k.name);
        if (v) { try { entries.push(JSON.parse(v)); } catch (e) {} }
      }
      entries.sort((a, b) => (a.time < b.time ? 1 : -1)); // newest first
      const rows = entries.map(e =>
        `<tr><td>${esc(e.time.replace("T", " ").slice(0, 19))}</td><td>${esc(e.name)}</td>` +
        `<td>${esc(e.platform)}</td><td>${esc(e.country)}</td><td>${esc(e.ip)}</td></tr>`
      ).join("");
      const html = `<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Who watched</title>
<style>body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;background:#0b0b0d;color:#eee;padding:20px;margin:0}
h2{font-weight:700}table{border-collapse:collapse;width:100%;max-width:900px}
td,th{border-bottom:1px solid #2c2c2e;padding:9px 10px;text-align:left;font-size:14px;white-space:nowrap}
th{color:#8e8e93;font-weight:600}tr:hover td{background:#1c1c1e}
.wrap{overflow-x:auto}</style></head><body>
<h2>Who watched &nbsp;·&nbsp; ${entries.length} view${entries.length === 1 ? "" : "s"}</h2>
<div class="wrap"><table>
<tr><th>When (UTC)</th><th>Name</th><th>Platform</th><th>Country</th><th>IP</th></tr>
${rows || '<tr><td colspan="5">No views yet.</td></tr>'}
</table></div></body></html>`;
      return new Response(html, { headers: { "Content-Type": "text/html; charset=utf-8" } });
    }

    return new Response("watch-logger", { status: 200 });
  },
};
