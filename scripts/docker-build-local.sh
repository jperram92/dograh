#!/usr/bin/env bash
#
# docker-build-local.sh
#
# Helper script for building Docker images locally with correct pipecat commit.
# This ensures local builds use the same pipecat version as the submodule.
#

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "🔨 Building Docker images with pipecat submodule..."

# Get the pipecat commit SHA
PIPECAT_COMMIT=$("$SCRIPT_DIR/get_pipecat_commit.sh")
echo -e "${BLUE}📦 Using pipecat commit: ${PIPECAT_COMMIT}${NC}"

# Export for docker-compose
export PIPECAT_COMMIT

# Run docker-compose build with the commit SHA
cd "$PROJECT_ROOT"
docker-compose build "$@"

echo -e "${GREEN}✅ Docker build completed successfully!${NC}"
echo -e "${GREEN}   Pipecat commit: ${PIPECAT_COMMIT}${NC}"