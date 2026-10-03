#!/usr/bin/env bash
# Copy common/postiz-ha-common.sh into every app's build context.
# Usage: scripts/sync-common.sh          (write copies)
#        scripts/sync-common.sh --check  (exit 1 if any copy differs; used by CI)
set -euo pipefail
cd "$(dirname "$0")/.."
src="common/postiz-ha-common.sh"
status=0
for app in postiz_postgres postiz_redis postiz_temporal postiz postiz_temporal_ui; do
    dst="${app}/rootfs/usr/local/lib/postiz-ha/common.sh"
    if [ "${1:-}" = "--check" ]; then
        if ! cmp -s "${src}" "${dst}"; then
            echo "OUT OF SYNC: ${dst} (run scripts/sync-common.sh)" >&2
            status=1
        fi
    else
        mkdir -p "$(dirname "${dst}")"
        cp "${src}" "${dst}"
        echo "updated ${dst}"
    fi
done
exit "${status}"
