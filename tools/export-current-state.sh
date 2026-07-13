#!/bin/bash
# Regenerate a staging snapshot of this machine's installed packages and
# enabled services, for manually diffing against the curated packages/ and
# services/ tier files. Never overwrites the curated files directly.
set -euo pipefail

ENIGMA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pkg_out="$ENIGMA_ROOT/packages/_exported"
svc_out="$ENIGMA_ROOT/services/_exported"
mkdir -p "$pkg_out" "$svc_out"

pacman -Qqen > "$pkg_out/native-explicit.txt"
pacman -Qqem > "$pkg_out/aur-explicit.txt"

systemctl list-unit-files --state=enabled --type=service,timer --no-legend \
    | awk '{print $1}' > "$svc_out/system-enabled.txt"
systemctl --user list-unit-files --state=enabled --no-legend \
    | awk '{print $1}' > "$svc_out/user-enabled.txt"

cat <<EOF

Exported to $pkg_out and $svc_out.

Diff against the curated tier files to spot new/removed packages, e.g.:
  comm -23 <(sort $pkg_out/native-explicit.txt) \\
           <(cat "$ENIGMA_ROOT"/packages/core.txt "$ENIGMA_ROOT"/packages/cpu/*.txt \\
                 "$ENIGMA_ROOT"/packages/gpu/*.txt "$ENIGMA_ROOT"/packages/optional/*.txt \\
             2>/dev/null | grep -vE '^\\s*#|^\\s*\$' | sort -u)
Re-file anything new into the appropriate packages/*.txt by hand.
EOF
