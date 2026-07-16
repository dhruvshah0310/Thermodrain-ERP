#!/usr/bin/env python3
"""
Builds the client-side-only preview (npm run build:preview --workspace
client) and inlines its output into one self-contained HTML file — no
external <script src>/<link href>, so it can be opened directly or published
as a Claude Artifact. This build has no backend: it runs entirely against
the embedded client/src/preview/snapshot.json (see scripts/export_snapshot.py).

Run with: python3 scripts/build_preview_artifact.py
"""
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CLIENT_DIR = REPO_ROOT / "client"
DIST_PREVIEW = CLIENT_DIR / "dist-preview"
OUTPUT_DIR = CLIENT_DIR / "artifact-build"
OUTPUT_FILE = OUTPUT_DIR / "thermodrain-erp-preview.html"


def main():
    print("Building preview bundle (single JS/CSS file, no code-splitting)...")
    subprocess.run(["npm", "run", "build:preview"], cwd=CLIENT_DIR, check=True)

    css_files = list((DIST_PREVIEW / "assets").glob("*.css"))
    js_files = list((DIST_PREVIEW / "assets").glob("*.js"))
    if len(css_files) != 1 or len(js_files) != 1:
        sys.exit(
            f"Expected exactly one CSS and one JS asset, got {len(css_files)} CSS / {len(js_files)} JS. "
            "Check vite.config.ts's preview-mode build.rollupOptions (inlineDynamicImports) is still in effect."
        )

    css = css_files[0].read_text()
    js = js_files[0].read_text()

    html = f"""<title>Thermodrain ERP — Purchase Module Preview</title>
<style>
{css}
</style>
<div id="root"></div>
<script type="module">
{js}
</script>
"""

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    OUTPUT_FILE.write_text(html)
    print(f"Wrote {OUTPUT_FILE} ({OUTPUT_FILE.stat().st_size / 1024 / 1024:.2f} MB)")


if __name__ == "__main__":
    main()
