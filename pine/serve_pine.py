#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Serve the Pine indicator, the copy-ready VP block and the Persian guide.

Usage:  python3 pine/serve_pine.py [port]
"""
import html
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
PINE = os.path.join(HERE, "SwingL3_AMD_VP_SuperTrend.pine")
BLOCK = os.path.join(HERE, "VP_BLOCK_REPLACE.pine")
GUIDE = os.path.join(HERE, "GUIDE_FA.md")
ZIP = os.path.join(HERE, "SwingL3_AMD_VP_SuperTrend_Pack.zip")

PAGE = """<!DOCTYPE html>
<html lang="fa" dir="rtl"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>SwingL3 AMD VP SuperTrend - Pine v5</title>
<style>
 body{background:#0e1117;color:#e6edf3;font-family:Tahoma,Verdana,sans-serif;margin:0;padding:16px}
 h1{font-size:18px;margin:0 0 6px}
 .bar{position:sticky;top:0;background:#0e1117;padding:10px 0;border-bottom:1px solid #30363d;z-index:9;display:flex;gap:8px;flex-wrap:wrap;align-items:center}
 button,a.btn{background:#238636;color:#fff;border:0;border-radius:6px;padding:9px 14px;font-size:13.5px;cursor:pointer;text-decoration:none}
 a.btn.blue{background:#1f6feb} a.btn.grey{background:#6e7681} a.btn.orange{background:#bb8009}
 .hint{color:#8b949e;font-size:13px}
 .tabs{display:flex;gap:8px;margin:10px 0 0}
 .tab{background:#21262d;border:1px solid #30363d;border-radius:6px 6px 0 0;padding:7px 12px;cursor:pointer;font-size:13.5px}
 .tab.on{background:#1f6feb;border-color:#1f6feb}
 textarea{width:100%;height:64vh;background:#161b22;color:#c9d1d9;border:1px solid #30363d;border-radius:0 8px 8px 8px;
   font-family:Consolas,Menlo,monospace;font-size:12.5px;line-height:1.45;direction:ltr;padding:10px;white-space:pre;overflow:auto}
</style></head><body>
<h1>Swing L3 + AMD + Volume Profile + SuperTrend - Pine v5</h1>
<div class="hint" id="meta"></div>
<div class="tabs">
  <div class="tab on" id="tFull" onclick="tab('full')">کد کامل فایل</div>
  <div class="tab" id="tBlk" onclick="tab('blk')">فقط بخش ③ VOLUME PROFILE</div>
</div>
<div class="bar">
  <button onclick="copyCur()">📋 کپی متنی که می‌بینید</button>
  <a class="btn blue" href="download.pine">⬇ کل فایل .pine</a>
  <a class="btn orange" href="download.block">⬇ فقط بلوک ③</a>
  <a class="btn grey" href="pack.zip">⬇ پکیج</a>
  <a class="btn grey" href="guide">⬇ راهنما</a>
  <span id="msg" class="hint"></span>
</div>
<textarea id="code" spellcheck="false" readonly></textarea>
<script>
const FULL = __FULL__;
const BLOCK = __BLOCK__;
let cur = 'full';
function paint(){
  const t = document.getElementById('code');
  t.value = cur === 'full' ? FULL : BLOCK;
  document.getElementById('tFull').className = 'tab' + (cur === 'full' ? ' on' : '');
  document.getElementById('tBlk').className  = 'tab' + (cur === 'blk'  ? ' on' : '');
  document.getElementById('meta').textContent = cur === 'full'
    ? 'کد کامل - ' + FULL.split('\\n').length + ' خط'
    : 'بلوک جایگزین بخش ③ - ' + BLOCK.split('\\n').length + ' خط (همین را در Pine Editor جایگزین بخش ③ کنید)';
}
function tab(w){ cur = w; paint(); }
function flash(t){ document.getElementById('msg').textContent = t; setTimeout(function(){ document.getElementById('msg').textContent=''; }, 2500); }
function copyCur(){
  const t = document.getElementById('code');
  t.removeAttribute('readonly'); t.focus(); t.select(); t.setSelectionRange(0, t.value.length);
  let ok = false;
  try { ok = document.execCommand('copy'); } catch (e) { ok = false; }
  if (navigator.clipboard && navigator.clipboard.writeText) {
    navigator.clipboard.writeText(t.value).then(function(){ flash('کپی شد ✓'); }, function(){ flash(ok ? 'کپی شد ✓' : 'کپی نشد - متن را دستی انتخاب کنید'); });
  } else { flash(ok ? 'کپی شد ✓' : 'کپی نشد - متن را دستی انتخاب کنید'); }
  t.setAttribute('readonly','readonly');
}
paint();
</script></body></html>"""


class H(BaseHTTPRequestHandler):
    """Minimal but preview-proxy friendly: answers GET *and* HEAD for every route."""

    protocol_version = "HTTP/1.1"
    server_version = "PineViewer/1.0"

    def _send(self, body, ctype, fname=None, head_only=False, code=200):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Accept-Ranges", "none")
        if fname:
            self.send_header("Content-Disposition", 'attachment; filename="%s"' % fname)
        self.end_headers()
        if not head_only:
            try:
                self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError):
                pass

    def _route(self, head_only=False):
        p = self.path.split("?")[0].rstrip("/") or "/"
        if p in ("/", "/index.html"):
            full = self._read(PINE)
            blk = self._read(BLOCK)
            body = (PAGE.replace("__FULL__", json.dumps(full)).replace("__BLOCK__", json.dumps(blk))).encode("utf-8")
            self._send(body, "text/html; charset=utf-8", head_only=head_only)
        elif p in ("/download.pine", "/raw"):
            self._send(self._read(PINE).encode("utf-8"), "text/plain; charset=utf-8",
                       "SwingL3_AMD_VP_SuperTrend.pine" if p == "/download.pine" else None, head_only)
        elif p == "/download.block":
            self._send(self._read(BLOCK).encode("utf-8"), "text/plain; charset=utf-8", "VP_BLOCK_REPLACE.pine", head_only)
        elif p == "/pack.zip":
            with open(ZIP, "rb") as fh:
                self._send(fh.read(), "application/zip", "SwingL3_AMD_VP_SuperTrend_Pack.zip", head_only)
        elif p == "/guide":
            self._send(self._read(GUIDE).encode("utf-8"), "text/markdown; charset=utf-8", "GUIDE_FA.md", head_only)
        elif p == "/favicon.ico":
            self._send(b"", "image/x-icon", None, head_only, 204)
        elif p == "/healthz":
            self._send(b"ok", "text/plain; charset=utf-8", None, head_only)
        else:
            self._send(b"not found", "text/plain; charset=utf-8", None, head_only, 404)

    def do_GET(self):
        self._route(False)

    def do_HEAD(self):
        self._route(True)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Allow", "GET, HEAD, OPTIONS")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def _read(self, path):
        with open(path, encoding="utf-8") as fh:
            return fh.read()


    def log_message(self, *a):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    print("serving on http://0.0.0.0:%d" % port, flush=True)
    ThreadingHTTPServer(("0.0.0.0", port), H).serve_forever()
