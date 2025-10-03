#!/usr/bin/env bash
#
# check_pipecat_sync.sh
#
# DEPRECATED: This script is no longer needed as pipecat version is now
# automatically synchronized during Docker build using build arguments.
#
# The Dockerfile now accepts PIPECAT_COMMIT as a build argument, and the
# GitHub workflow automatically extracts and passes the correct commit SHA.
#
# For local development, use scripts/docker-build-local.sh or set the
# PIPECAT_COMMIT environment variable before running docker-compose build.
#

echo "⚠️  This script is deprecated!"
echo ""
echo "Pipecat version synchronization is now automatic:"
echo "• GitHub Actions: Automatically extracts and uses submodule commit"
echo "• Local builds: Use scripts/docker-build-local.sh"
echo ""
echo "No manual Dockerfile updates are needed anymore! 🎉"
exit 0