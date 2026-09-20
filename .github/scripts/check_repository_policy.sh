#!/usr/bin/env bash
set -euo pipefail

while IFS= read -r -d '' shell_file; do
  bash -n "$shell_file"
done < <(find module tests .github/scripts -type f -name '*.sh' -print0)

if grep -R -n -- '--no-check-certificate' module; then
  echo 'TLS verification must remain enabled' >&2
  exit 1
fi

if grep -R -E -n '/(main|master|universal-binary)/ksu_susfs_arm64' module; then
  echo 'Runtime binaries must use immutable source references' >&2
  exit 1
fi

if grep -R -E -n 'tar[[:space:]]+x[z]?f' webui; then
  echo 'The WebUI must not extract archives directly' >&2
  exit 1
fi

if grep -E -n 'https?://' webui/utils/docs.js; then
  echo 'WebUI documentation must use packaged local content' >&2
  exit 1
fi

invalid_builtin=$(
  find module/configs/scripts -maxdepth 1 -type f ! -name 'SusAF_*.sh' -print -quit
)
if [ -n "$invalid_builtin" ]; then
  echo "Packaged built-in must use Sus'AF naming: $invalid_builtin" >&2
  exit 1
fi

if grep -E -n '/dev/input|keyevent' module/customize.sh; then
  echo 'Installation must remain noninteractive' >&2
  exit 1
fi

test ! -e .github/FUNDING.yml
