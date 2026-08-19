#!/usr/bin/env python3
"""Renders game_design.md to the PDF that sits beside it.

The design document is the single source of truth for the game's rules, and
the working agreement asks for the PDF to be re-rendered whenever it changes.
This script is that step, committed so it stops being folklore.

    pip install markdown
    python3 docs/render_pdf.py

Uses the Chromium that ships with the container (Playwright's, or whatever
`chromium`/`google-chrome` is on PATH) to print the HTML to PDF. No network
access and no CDN assets, so it works offline.
"""

from __future__ import annotations

import pathlib
import shutil
import subprocess
import sys
import tempfile

import markdown

DOCS = pathlib.Path(__file__).resolve().parent
SOURCE = DOCS / "game_design.md"
TARGET = DOCS / "Isekai_Strategem_Game_Design_Document.pdf"

# Print styling. Deliberately plain: this is a reference document that gets
# read on a screen and occasionally printed, not a brochure.
CSS = """
@page { size: A4; margin: 18mm 16mm; }
body {
  font-family: "DejaVu Serif", Georgia, "Times New Roman", serif;
  font-size: 10.5pt;
  line-height: 1.5;
  color: #16191d;
}
h1, h2, h3, h4 {
  font-family: "DejaVu Sans", Helvetica, Arial, sans-serif;
  color: #0d1117;
  line-height: 1.25;
  page-break-after: avoid;
}
h1 { font-size: 22pt; border-bottom: 2px solid #0d1117; padding-bottom: 6px; }
h2 { font-size: 15pt; margin-top: 22px; border-bottom: 1px solid #c9ced6;
     padding-bottom: 4px; }
h3 { font-size: 12pt; margin-top: 16px; }
h4 { font-size: 10.5pt; margin-top: 12px; text-transform: uppercase;
     letter-spacing: 0.06em; color: #444c56; }
p, li { orphans: 3; widows: 3; }
code, pre {
  font-family: "DejaVu Sans Mono", "Courier New", monospace;
  font-size: 9pt;
}
code { background: #f2f4f7; padding: 1px 3px; border-radius: 2px; }
pre {
  background: #f6f8fa; border: 1px solid #d8dee4; border-radius: 3px;
  padding: 8px 10px; overflow-x: auto; page-break-inside: avoid;
}
pre code { background: none; padding: 0; }
table {
  border-collapse: collapse; width: 100%; margin: 10px 0; font-size: 9pt;
  page-break-inside: avoid;
}
th, td { border: 1px solid #c9ced6; padding: 4px 7px; text-align: left;
         vertical-align: top; }
th { background: #eef1f5; font-family: "DejaVu Sans", Helvetica, sans-serif; }
blockquote {
  margin: 10px 0; padding: 4px 14px; border-left: 3px solid #c9ced6;
  color: #444c56;
}
hr { border: none; border-top: 1px solid #c9ced6; margin: 18px 0; }
a { color: #0b5cad; text-decoration: none; }
"""


def find_chromium() -> str:
    """The container ships Chromium under Playwright's browser directory."""
    candidates = [
        "/opt/pw-browsers/chromium/chrome-linux/chrome",
        "/opt/pw-browsers/chromium-1194/chrome-linux/chrome",
        "/opt/pw-browsers/chromium_headless_shell-1194/chrome-linux/"
        "headless_shell",
    ]
    for path in candidates:
        if pathlib.Path(path).exists():
            return path
    for name in ("chromium", "chromium-browser", "google-chrome"):
        found = shutil.which(name)
        if found:
            return found
    # Last resort: anything Chromium-shaped under the Playwright directory.
    root = pathlib.Path("/opt/pw-browsers")
    if root.exists():
        for pattern in ("**/chrome", "**/headless_shell"):
            for path in sorted(root.glob(pattern)):
                if path.is_file():
                    return str(path)
    sys.exit("No Chromium found. Install one, or set it on PATH.")


def main() -> None:
    if not SOURCE.exists():
        sys.exit(f"Missing {SOURCE}")

    html_body = markdown.markdown(
        SOURCE.read_text(encoding="utf-8"),
        extensions=["tables", "fenced_code", "toc", "sane_lists"],
    )
    page = (
        "<!doctype html><html><head><meta charset='utf-8'>"
        "<title>Isekai Strategem Game Design Document</title>"
        f"<style>{CSS}</style></head><body>{html_body}</body></html>"
    )

    with tempfile.TemporaryDirectory() as tmp:
        html_path = pathlib.Path(tmp) / "gdd.html"
        html_path.write_text(page, encoding="utf-8")
        chromium = find_chromium()
        subprocess.run(
            [
                chromium,
                "--headless",
                "--disable-gpu",
                "--no-sandbox",
                "--no-pdf-header-footer",
                f"--print-to-pdf={TARGET}",
                html_path.as_uri(),
            ],
            check=True,
            capture_output=True,
        )

    size_kb = TARGET.stat().st_size // 1024
    print(f"Wrote {TARGET.relative_to(DOCS.parent)} ({size_kb} KB)")


if __name__ == "__main__":
    main()
