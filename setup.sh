#!/bin/bash
set -euo pipefail
set -a

source koji-setup

# Create koji hub
$KOJI_SETUP_DIR/hub/setup.sh

# Create default koji builder
$KOJI_SETUP_DIR/builder/setup.sh
