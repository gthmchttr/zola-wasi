#!/usr/bin/env bash
# Print Markdown release notes for TAG (default: UPSTREAM's ZOLA_TAG) to stdout.
# Reads the patch subjects from patches/ and checksums from dist/release/SHA256SUMS (scripts/package.sh).
. "$(dirname "$0")/common.sh"

tag="${1:-$ZOLA_TAG}"
sums="$DIST_DIR/release/SHA256SUMS"
[ -f "$sums" ] || die "$sums missing: run scripts/package.sh first"

cat <<EOF
[Zola ${ZOLA_TAG}](https://github.com/getzola/zola/releases/tag/${ZOLA_TAG}) compiled to WebAssembly (\`wasm32-wasip1\`).

It's the real \`zola\` CLI: \`build\`, \`check\`, \`init\` and \`completion\` work as they do natively, in any WASI runtime. \`serve\` isn't available, and nothing reaches the network (external link checks are skipped, remote \`load_data\` fails).

### Use it

\`\`\`sh
wasmtime run --dir ./my-site::/site zola.wasm --root /site build
\`\`\`

In a web page, serve \`zola-wasi.js\` (the library with a WASI runtime built in, no dependencies) next to \`zola.wasm\`:

\`\`\`html
<script type="module">
  import { loadZola } from "./zola-wasi.js";
  const zola = await loadZola(new URL("zola.wasm", import.meta.url));
  const { ok, files, stderr } = await zola.build({ files: { "zola.toml": "...", "content/_index.md": "..." } });
</script>
\`\`\`

With npm, install the JavaScript package from this release (\`zola.wasm\` included):

\`\`\`sh
npm install https://github.com/${GITHUB_REPOSITORY:-OWNER/zola-wasi}/releases/download/${tag}/zola-wasi-${ZOLA_TAG#v}.tgz
\`\`\`

\`\`\`js
import { loadZola } from "zola-wasi";
const zola = await loadZola(new URL("zola-wasi/zola.wasm", import.meta.url)); // or its bytes
const { ok, files, stderr } = await zola.build({ files: { "zola.toml": "...", "content/_index.md": "..." } });
\`\`\`

### Patches on top of Zola ${ZOLA_TAG}

EOF
patch_files "$ZOLA_TAG" | while read -r patch; do
  subject="$(sed -n 's/^Subject: \(\[PATCH[^]]*\] \)\{0,1\}//p' "$patch" | head -1)"
  echo "- $subject"
done
cat <<EOF

### Checksums (SHA-256)

\`\`\`
$(cat "$sums")
\`\`\`
EOF
