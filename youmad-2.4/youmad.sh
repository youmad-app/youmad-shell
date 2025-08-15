#!/bin/bash
# YouMAD? - Your Music Album Downloader v2.4

set -euo pipefail

# Get script directory for reliable sourcing
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# Source modules in dependency order
for module in youmad-config youmad-utils youmad-core youmad-metadata; do
    module_path="$SCRIPT_DIR/lib/${module}.sh"
    if [[ -f "$module_path" ]]; then
        source "$module_path"
    else
        echo "ERROR: Cannot find $module_path"
        echo "Current directory: $(pwd)"
        echo "Script directory: $SCRIPT_DIR"
        echo "Available files in lib/:"
        ls -la "$SCRIPT_DIR/lib/" 2>/dev/null || echo "lib/ directory not found"
        exit 1
    fi
done

# Options (will be set by parse_arguments)
DRY_RUN=false
OVERRIDE=false
VERBOSE=false
