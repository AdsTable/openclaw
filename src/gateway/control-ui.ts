import fs from "node:fs";
import os from "node:os";
import type { IncomingMessage, ServerResponse } from "node:http";
import path from "node:path";
import type { OpenClawConfig } from "../config/config.js";
import { resolveControlUiRootSync } from "../infra/control-ui-assets.js";
import { DEFAULT_ASSISTANT_IDENTITY, resolveAssistantIdentity } from "./assistant-identity.js";
import {
  CONTROL_UI_BOOTSTRAP_CONFIG_PATH,
  type ControlUiBootstrapConfig,
} from "./control-ui-contract.js";
import { buildControlUiCspHeader } from "./control-ui-csp.js";
import {
  buildControlUiAvatarUrl,
  CONTROL_UI_AVATAR_PREFIX,
  normalizeControlUiBasePath,
  resolveAssistantAvatarUrl,
} from "./control-ui-shared.js";

const ROOT_PREFIX = "/";

export type ControlUiRequestOptions = {
  basePath?: string;
  config?: OpenClawConfig;
  agentId?: string;
  root?: ControlUiRootState;
};

export type ControlUiRootState =
  | { kind: "resolved"; path: string }
  | { kind: "invalid"; path: string }
  | { kind: "missing" };

function contentTypeForExt(ext: string): string {
  switch (ext) {
    case ".html":
      return "text/html; charset=utf-8";
    case ".js":
      return "application/javascript; charset=utf-8";
    case ".css":
      return "text/css; charset=utf-8";
    case ".json":
    case ".map":
      return "application/json; charset=utf-8";
    case ".svg":
      return "image/svg+xml";
    case ".png":
      return "image/png";
    case ".jpg":
    case ".jpeg":
      return "image/jpeg";
    case ".gif":
      return "image/gif";
    case ".webp":
      return "image/webp";
    case ".ico":
      return "image/x-icon";
    case ".txt":
      return "text/plain; charset=utf-8";
    default:
      return "application/octet-stream";
  }
}

export type ControlUiAvatarResolution =
  | { kind: "none"; reason: string }
  | { kind: "local"; filePath: string }
  | { kind: "remote"; url: string }
  | { kind: "data"; url: string };

type ControlUiAvatarMeta = {
  avatarUrl: string | null;
};

function applyControlUiSecurityHeaders(res: ServerResponse) {
  res.setHeader("X-Frame-Options", "DENY");
  res.setHeader("Content-Security-Policy", buildControlUiCspHeader());
  res.setHeader("X-Content-Type-Options", "nosniff");
  res.setHeader("Referrer-Policy", "no-referrer");
}

function sendJson(res: ServerResponse, status: number, body: unknown) {
  res.statusCode = status;
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.setHeader("Cache-Control", "no-cache");
  res.end(JSON.stringify(body));
}

function isValidAgentId(agentId: string): boolean {
  return /^[a-z0-9][a-z0-9_-]{0,63}$/i.test(agentId);
}

export function handleControlUiAvatarRequest(
  req: IncomingMessage,
  res: ServerResponse,
  opts: { basePath?: string; resolveAvatar: (agentId: string) => ControlUiAvatarResolution },
): boolean {
  const urlRaw = req.url;
  if (!urlRaw) {
    return false;
  }
  if (req.method !== "GET" && req.method !== "HEAD") {
    return false;
  }

  const url = new URL(urlRaw, "http://localhost");
  const basePath = normalizeControlUiBasePath(opts.basePath);
  const pathname = url.pathname;
  const pathWithBase = basePath
    ? `${basePath}${CONTROL_UI_AVATAR_PREFIX}/`
    : `${CONTROL_UI_AVATAR_PREFIX}/`;
  if (!pathname.startsWith(pathWithBase)) {
    return false;
  }

  applyControlUiSecurityHeaders(res);

  const agentIdParts = pathname.slice(pathWithBase.length).split("/").filter(Boolean);
  const agentId = agentIdParts[0] ?? "";
  if (agentIdParts.length !== 1 || !agentId || !isValidAgentId(agentId)) {
    respondNotFound(res);
    return true;
  }

  if (url.searchParams.get("meta") === "1") {
    const resolved = opts.resolveAvatar(agentId);
    const avatarUrl =
      resolved.kind === "local"
        ? buildControlUiAvatarUrl(basePath, agentId)
        : resolved.kind === "remote" || resolved.kind === "data"
          ? resolved.url
          : null;
    sendJson(res, 200, { avatarUrl } satisfies ControlUiAvatarMeta);
    return true;
  }

  const resolved = opts.resolveAvatar(agentId);
  if (resolved.kind !== "local") {
    respondNotFound(res);
    return true;
  }

  if (req.method === "HEAD") {
    res.statusCode = 200;
    res.setHeader("Content-Type", contentTypeForExt(path.extname(resolved.filePath).toLowerCase()));
    res.setHeader("Cache-Control", "no-cache");
    res.end();
    return true;
  }

  serveFile(res, resolved.filePath);
  return true;
}

const SESSION_VIEWER_JS = `
function b64toStr(b64){const bin=atob(b64);const bytes=new Uint8Array(bin.length);for(let i=0;i<bin.length;i++)bytes[i]=bin.charCodeAt(i);return new TextDecoder('utf-8').decode(bytes);}
function sessionLabel(name){if(name.includes('.reset.'))return'[reset] ';if(name.includes('.deleted.'))return'[deleted] ';return'';}
function parseSession(name,b64){const text=b64toStr(b64);const lines=text.split('\\n').filter(l=>l.trim());const messages=[];let firstTs=null;for(const line of lines){try{const e=JSON.parse(line);if(!firstTs&&e.timestamp)firstTs=e.timestamp;if(e.type!=='message')continue;const msg=e.message||{};const role=msg.role;if(role!=='user'&&role!=='assistant')continue;let content='';if(typeof msg.content==='string')content=msg.content;else if(Array.isArray(msg.content)){content=msg.content.filter(c=>c.type==='text').map(c=>c.text||'').join('\\n');}content=content.replace(/Conversation info[\\s\\S]*?\`\`\`\\s*\\n?/g,'');content=content.replace(/\\[\\[reply_to_current\\]\\]\\s*/g,'');const m=content.match(/\\[(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)[^\\]]+\\]\\s+([\\s\\S]+)/);if(m)content=m[1].trim();content=content.trim();if(!content)continue;messages.push({role,content,timestamp:e.timestamp,model:e.model||(msg.model||'')});}catch(ex){}}const date=firstTs?new Date(firstTs).toLocaleString('ru-RU',{day:'2-digit',month:'2-digit',year:'numeric',hour:'2-digit',minute:'2-digit'}):name.substring(0,19);const label=sessionLabel(name);return{name,date,label,messages};}
let cur=-1;
function esc(s){return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');}
function fmt(s){let h=esc(s);h=h.replace(/\`\`\`[\\w]*\\n([\\s\\S]*?)\`\`\`/g,function(_,c){return'<pre><code>'+c.trimEnd()+'</code></pre>';});h=h.replace(/\`([^\`\\n]+)\`/g,'<code>$1</code>');h=h.replace(/\\*\\*([^*\\n]+)\\*\\*/g,'<strong>$1</strong>');return h;}
function fmtTime(t){try{return new Date(t).toLocaleTimeString('ru-RU',{hour:'2-digit',minute:'2-digit'});}catch(e){return '';}}
function renderList(){const list=document.getElementById('list');list.innerHTML=SESSIONS.map(function(s,i){const badge=s.label?'<span style="font-size:10px;color:#cf222e;font-weight:600">'+s.label+'</span>':'';return'<div class="s-item'+(i===cur?' active':'')+'" data-idx="'+i+'">'+'<div class="s-date">'+badge+s.date+'</div>'+'<div class="s-meta">'+s.messages.length+' \\u0441\\u043e\\u043e\\u0431\\u0449\\u0435\\u043d\\u0438\\u0439</div></div>';}).join('');list.querySelectorAll('.s-item').forEach(function(el){el.addEventListener('click',function(){selectSession(parseInt(el.getAttribute('data-idx'),10));});});}
function selectSession(i){cur=i;renderList();const s=SESSIONS[i];document.getElementById('top').innerHTML='<strong>'+s.date+'</strong>'+(s.label?' <span style="color:#cf222e;font-size:11px">'+s.label.trim()+'</span>':'')+' &nbsp;&middot;&nbsp; '+esc(s.name.substring(0,36))+'...';const box=document.getElementById('msgs');box.className='msgs';if(!s.messages.length){box.innerHTML='<div style="margin:auto;text-align:center;color:#8c959f;padding:40px">\\u041d\\u0435\\u0442 \\u0441\\u043e\\u043e\\u0431\\u0449\\u0435\\u043d\\u0438\\u0439</div>';document.getElementById('footer').style.display='none';return;}box.innerHTML=s.messages.map(function(m){const t=fmtTime(m.timestamp);const mod=m.model?m.model.split('/').pop():'';const who=m.role==='user'?'\\u0412\\u044b':'Agent';const meta=who+(mod?' \\u00b7 '+mod:'')+(t?' \\u00b7 '+t:'');const av=m.role==='user'?'&#128100;':'&#129422;';return'<div class="msg '+m.role+'"><div class="av '+m.role+'">'+av+'</div><div class="bub"><div class="meta">'+meta+'</div><div class="txt">'+fmt(m.content)+'</div></div></div>';}).join('');const rev=s.messages.slice().reverse();const lm=rev.find(function(m){return m.role==='assistant'&&m.model;});document.getElementById('fC').textContent=s.messages.length;document.getElementById('fM').textContent=lm?lm.model.split('/').pop():'\\u2014';document.getElementById('footer').style.display='flex';box.scrollTop=box.scrollHeight;}
`;

function buildSessionViewerHtml(basePath: string): string {
  const css = `*{box-sizing:border-box;margin:0;padding:0}body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#f6f8fa;color:#24292f;display:flex;height:100vh;overflow:hidden}.sidebar{width:260px;min-width:260px;background:#fff;border-right:1px solid #d0d7de;display:flex;flex-direction:column}.sidebar h2{padding:12px 16px;font-size:11px;font-weight:600;text-transform:uppercase;letter-spacing:.5px;color:#57606a;border-bottom:1px solid #d0d7de;background:#f6f8fa}.s-list{overflow-y:auto;flex:1}.s-item{padding:11px 16px;border-bottom:1px solid #eaeef2;cursor:pointer;transition:background .1s}.s-item:hover{background:#f6f8fa}.s-item.active{background:#dbeafe;border-left:3px solid #2563eb}.s-date{font-size:13px;font-weight:600;color:#24292f;margin-bottom:2px}.s-meta{font-size:11px;color:#57606a}.chat{flex:1;display:flex;flex-direction:column;overflow:hidden}.chat-top{padding:10px 20px;background:#f6f8fa;border-bottom:1px solid #d0d7de;font-size:12px;color:#57606a}.chat-top strong{color:#24292f}.msgs{flex:1;overflow-y:auto;padding:20px;display:flex;flex-direction:column;gap:14px}.msg{display:flex;gap:10px}.msg.user{flex-direction:row-reverse}.av{width:30px;height:30px;border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:14px;flex-shrink:0;align-self:flex-start;margin-top:16px;background:#e8f4fd}.av.user{background:#fde8f4}.bub{max-width:calc(100% - 48px)}.meta{font-size:11px;color:#8c959f;margin-bottom:4px}.msg.user .meta{text-align:right}.txt{background:#f6f8fa;border:1px solid #d0d7de;border-radius:10px;padding:10px 14px;font-size:13.5px;line-height:1.65;white-space:pre-wrap;word-break:break-word;color:#24292f}.msg.user .txt{background:#eff6ff;border-color:#bfdbfe;color:#1e3a5f}.txt code{background:#e8edf2;padding:1px 5px;border-radius:3px;font-family:Consolas,monospace;font-size:12px;color:#0550ae}.txt pre{background:#f0f3f6;border:1px solid #d0d7de;border-radius:6px;padding:10px;margin:6px 0;overflow-x:auto}.txt pre code{background:none;padding:0;color:#24292f}.txt strong{font-weight:600}.footer{padding:8px 20px;background:#f6f8fa;border-top:1px solid #d0d7de;font-size:12px;color:#57606a;display:flex;gap:20px}.footer span{color:#24292f;font-weight:600}.empty{flex:1;display:flex;align-items:center;justify-content:center;color:#8c959f;font-size:14px}::-webkit-scrollbar{width:5px}::-webkit-scrollbar-track{background:transparent}::-webkit-scrollbar-thumb{background:#d0d7de;border-radius:3px}`;

  const historyJsUrl = basePath ? `${basePath}/history.js` : "/history.js";
  const html = [
    "<!DOCTYPE html><html lang=\"ru\"><head>",
    "<meta charset=\"UTF-8\">",
    "<title>OpenClaw History</title>",
    `<style>${css}</style>`,
    "</head><body>",
    "<div class=\"sidebar\"><h2>&#129422; OpenClaw History</h2><div class=\"s-list\" id=\"list\"></div></div>",
    "<div class=\"chat\">",
    "<div class=\"chat-top\" id=\"top\">&#8592; &#1042;&#1099;&#1073;&#1077;&#1088;&#1080;&#1090;&#1077; &#1089;&#1077;&#1089;&#1089;&#1080;&#1102;</div>",
    "<div class=\"msgs empty\" id=\"msgs\">&#1047;&#1072;&#1075;&#1088;&#1091;&#1079;&#1082;&#1072;...</div>",
    "<div class=\"footer\" id=\"footer\" style=\"display:none\">&#1057;&#1086;&#1086;&#1073;&#1097;&#1077;&#1085;&#1080;&#1081;: <span id=\"fC\"></span> &nbsp; &#1052;&#1086;&#1076;&#1077;&#1083;&#1100;: <span id=\"fM\"></span></div>",
    "</div>",
    `<script src="${historyJsUrl}"></script>`,
    "</body></html>",
  ].join("");
  return html;
}

function handleSessionHistoryRoute(
  req: IncomingMessage,
  res: ServerResponse,
  pathname: string,
  basePath: string,
): boolean {
  const historyPath = basePath ? `${basePath}/history` : "/history";
  const historyJsPath = basePath ? `${basePath}/history.js` : "/history.js";

  if (pathname === historyJsPath) {
    const sessionsDir = path.join(os.homedir(), ".openclaw", "agents", "main", "sessions");
    const files: { name: string; b64: string }[] = [];
    if (fs.existsSync(sessionsDir)) {
      const jsonlFiles = fs.readdirSync(sessionsDir)
        .filter((f) => f.includes(".jsonl") && !f.endsWith(".lock"))
        .map((f) => ({ name: f, mtime: fs.statSync(path.join(sessionsDir, f)).mtimeMs }))
        .sort((a, b) => b.mtime - a.mtime);
      for (const { name } of jsonlFiles) {
        const filePath = path.join(sessionsDir, name);
        const bytes = fs.readFileSync(filePath);
        files.push({ name, b64: bytes.toString("base64") });
      }
    }
    const rawJson = JSON.stringify(files);
    const js = [
      SESSION_VIEWER_JS,
      `var RAW=${rawJson};`,
      "var SESSIONS=RAW.map(function(f){return parseSession(f.name,f.b64);});",
      "renderList();if(SESSIONS.length>0)selectSession(0);",
    ].join("\n");
    res.statusCode = 200;
    res.setHeader("Content-Type", "application/javascript; charset=utf-8");
    res.setHeader("Cache-Control", "no-store, no-cache, must-revalidate");
    res.end(js, "utf8");
    return true;
  }

  if (pathname !== historyPath && pathname !== `${historyPath}/`) {
    return false;
  }

  const html = buildSessionViewerHtml(basePath);
  res.statusCode = 200;
  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.setHeader("Cache-Control", "no-store, no-cache, must-revalidate");
  res.setHeader("Pragma", "no-cache");
  res.end(html, "utf8");
  return true;
}

function respondNotFound(res: ServerResponse) {
  res.statusCode = 404;
  res.setHeader("Content-Type", "text/plain; charset=utf-8");
  res.end("Not Found");
}

function serveFile(res: ServerResponse, filePath: string) {
  const ext = path.extname(filePath).toLowerCase();
  res.setHeader("Content-Type", contentTypeForExt(ext));
  // Static UI should never be cached aggressively while iterating; allow the
  // browser to revalidate.
  res.setHeader("Cache-Control", "no-cache");
  res.end(fs.readFileSync(filePath));
}

function serveIndexHtml(res: ServerResponse, indexPath: string) {
  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.setHeader("Cache-Control", "no-cache");
  res.end(fs.readFileSync(indexPath, "utf8"));
}

function isSafeRelativePath(relPath: string) {
  if (!relPath) {
    return false;
  }
  const normalized = path.posix.normalize(relPath);
  if (normalized.startsWith("../") || normalized === "..") {
    return false;
  }
  if (normalized.includes("\0")) {
    return false;
  }
  return true;
}

export function handleControlUiHttpRequest(
  req: IncomingMessage,
  res: ServerResponse,
  opts?: ControlUiRequestOptions,
): boolean {
  const urlRaw = req.url;
  if (!urlRaw) {
    return false;
  }
  if (req.method !== "GET" && req.method !== "HEAD") {
    res.statusCode = 405;
    res.setHeader("Content-Type", "text/plain; charset=utf-8");
    res.end("Method Not Allowed");
    return true;
  }

  const url = new URL(urlRaw, "http://localhost");
  const basePath = normalizeControlUiBasePath(opts?.basePath);
  const pathname = url.pathname;

  if (!basePath) {
    if (pathname === "/ui" || pathname.startsWith("/ui/")) {
      applyControlUiSecurityHeaders(res);
      respondNotFound(res);
      return true;
    }
  }

  if (basePath) {
    if (pathname === basePath) {
      applyControlUiSecurityHeaders(res);
      res.statusCode = 302;
      res.setHeader("Location", `${basePath}/${url.search}`);
      res.end();
      return true;
    }
    if (!pathname.startsWith(`${basePath}/`)) {
      return false;
    }
  }

  applyControlUiSecurityHeaders(res);

  // Session history viewer — served dynamically from .jsonl files
  if (handleSessionHistoryRoute(req, res, pathname, basePath)) {
    return true;
  }

  const bootstrapConfigPath = basePath
    ? `${basePath}${CONTROL_UI_BOOTSTRAP_CONFIG_PATH}`
    : CONTROL_UI_BOOTSTRAP_CONFIG_PATH;
  if (pathname === bootstrapConfigPath) {
    const config = opts?.config;
    const identity = config
      ? resolveAssistantIdentity({ cfg: config, agentId: opts?.agentId })
      : DEFAULT_ASSISTANT_IDENTITY;
    const avatarValue = resolveAssistantAvatarUrl({
      avatar: identity.avatar,
      agentId: identity.agentId,
      basePath,
    });
    if (req.method === "HEAD") {
      res.statusCode = 200;
      res.setHeader("Content-Type", "application/json; charset=utf-8");
      res.setHeader("Cache-Control", "no-cache");
      res.end();
      return true;
    }
    sendJson(res, 200, {
      basePath,
      assistantName: identity.name,
      assistantAvatar: avatarValue ?? identity.avatar,
      assistantAgentId: identity.agentId,
    } satisfies ControlUiBootstrapConfig);
    return true;
  }

  const rootState = opts?.root;
  if (rootState?.kind === "invalid") {
    res.statusCode = 503;
    res.setHeader("Content-Type", "text/plain; charset=utf-8");
    res.end(
      `Control UI assets not found at ${rootState.path}. Build them with \`pnpm ui:build\` (auto-installs UI deps), or update gateway.controlUi.root.`,
    );
    return true;
  }
  if (rootState?.kind === "missing") {
    res.statusCode = 503;
    res.setHeader("Content-Type", "text/plain; charset=utf-8");
    res.end(
      "Control UI assets not found. Build them with `pnpm ui:build` (auto-installs UI deps), or run `pnpm ui:dev` during development.",
    );
    return true;
  }

  const root =
    rootState?.kind === "resolved"
      ? rootState.path
      : resolveControlUiRootSync({
          moduleUrl: import.meta.url,
          argv1: process.argv[1],
          cwd: process.cwd(),
        });
  if (!root) {
    res.statusCode = 503;
    res.setHeader("Content-Type", "text/plain; charset=utf-8");
    res.end(
      "Control UI assets not found. Build them with `pnpm ui:build` (auto-installs UI deps), or run `pnpm ui:dev` during development.",
    );
    return true;
  }

  const uiPath =
    basePath && pathname.startsWith(`${basePath}/`) ? pathname.slice(basePath.length) : pathname;
  const rel = (() => {
    if (uiPath === ROOT_PREFIX) {
      return "";
    }
    const assetsIndex = uiPath.indexOf("/assets/");
    if (assetsIndex >= 0) {
      return uiPath.slice(assetsIndex + 1);
    }
    return uiPath.slice(1);
  })();
  const requested = rel && !rel.endsWith("/") ? rel : `${rel}index.html`;
  const fileRel = requested || "index.html";
  if (!isSafeRelativePath(fileRel)) {
    respondNotFound(res);
    return true;
  }

  const filePath = path.join(root, fileRel);
  if (!filePath.startsWith(root)) {
    respondNotFound(res);
    return true;
  }

  if (fs.existsSync(filePath) && fs.statSync(filePath).isFile()) {
    if (path.basename(filePath) === "index.html") {
      serveIndexHtml(res, filePath);
      return true;
    }
    serveFile(res, filePath);
    return true;
  }

  // SPA fallback (client-side router): serve index.html for unknown paths.
  const indexPath = path.join(root, "index.html");
  if (fs.existsSync(indexPath)) {
    serveIndexHtml(res, indexPath);
    return true;
  }

  respondNotFound(res);
  return true;
}
