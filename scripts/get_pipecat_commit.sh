#!/usr/bin/env bash
#
# get_pipecat_commit.sh
#
# Gets the current pipecat submodule commit SHA.
# Used by Docker build process to ensure Dockerfile always uses the correct version.
#

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Check if pipecat submodule exists
if [ ! -d "$PROJECT_ROOT/pipecat/.git" ]; then
    echo "ERROR: pipecat submodule not initialized at $PROJECT_ROOT/pipecat" >&2
    echo "Run: git submodule update --init --recursive" >&2
    exit 1
fi

# Get the commit SHA from the submodule
cd "$PROJECT_ROOT/pipecat"
git rev-parse HEAD