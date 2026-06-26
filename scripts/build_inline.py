#!/usr/bin/env python3
"""
build_inline.py — Bundle public/index.template.html into a single self-
contained public/index.html with CSS, JS, and favicon inlined.

WHY: The Bantu/Sua HTTP server (v1.2.2) is single-threaded and crashes
silently when a browser fires parallel requests (HTML + CSS + JS +
favicon) on page load. Inlining all assets into index.html makes the
initial page load a SINGLE request, sidestepping the crash. API calls
are then serialized by app.js so they also arrive one at a time.

USAGE:
    python3 scripts/build_inline.py
    # → rewrites public/index.html with everything inlined

The source-of-truth files are:
    public/index.template.html  (template — has <link href="/styles.css"> etc.)
    public/styles.css
    public/app.js
    public/favicon.svg

Run this script after editing any of those files.
"""
import base64
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PUBLIC = ROOT / "public"

def main():
    tpl_path  = PUBLIC / "index.template.html"
    css_path  = PUBLIC / "styles.css"
    js_path   = PUBLIC / "app.js"
    ico_path  = PUBLIC / "favicon.svg"
    out_path  = PUBLIC / "index.html"

    html = tpl_path.read_text(encoding="utf-8")
    css  = css_path.read_text(encoding="utf-8")
    js   = js_path.read_text(encoding="utf-8")
    ico  = ico_path.read_text(encoding="utf-8")

    # 1) Inline favicon as data URL
    ico_b64 = base64.b64encode(ico.encode("utf-8")).decode("ascii")
    ico_data_url = f"data:image/svg+xml;base64,{ico_b64}"
    html = re.sub(
        r'<link\s+rel="icon"\s+href="/favicon\.svg"[^>]*/?>',
        f'<link rel="icon" href="{ico_data_url}" type="image/svg+xml" />',
        html,
    )

    # 2) Inline <link rel="stylesheet" href="/styles.css"> → <style>...</style>
    html = re.sub(
        r'<link\s+rel="stylesheet"\s+href="/styles\.css"\s*/?>',
        lambda _: "<style>\n" + css + "\n</style>",
        html,
    )

    # 3) Inline <script src="/app.js" defer></script> → <script>...</script>
    #    Keep the jsPDF CDN script as-is (external CDN is fine — handled by
    #    browser, not by Bantu).
    html = re.sub(
        r'<script\s+src="/app\.js"[^>]*></script>',
        lambda _: "<script>\n" + js + "\n</script>",
        html,
    )

    out_path.write_text(html, encoding="utf-8")
    print(f"[build_inline] wrote {out_path} ({len(html):,} bytes)")
    print(f"[build_inline]   css inlined: {len(css):,} bytes")
    print(f"[build_inline]   js  inlined: {len(js):,} bytes")
    print(f"[build_inline]   favicon inlined as data URL ({len(ico_data_url):,} bytes)")

if __name__ == "__main__":
    main()
