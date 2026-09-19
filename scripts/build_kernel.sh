#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

echo "===> Starting Pixel 10 (muzel) kernel build..."

WORKSPACE_DIR="${GITHUB_WORKSPACE:-$(pwd)}"
KERNEL_DIR="${WORKSPACE_DIR}/kernel"
cd "${KERNEL_DIR}"

# Build Pixel 10 distribution package using Kleaf Bazel wrapper with fast config
echo "--- Executing build_muzel.sh with --config=fast..."
./build_muzel.sh --config=fast

# Locate outputs
DIST_DIR="${KERNEL_DIR}/out/muzel/dist"

if [ ! -d "${DIST_DIR}" ]; then
    # In some bazel configurations dist may be in out/dist or bazel-bin
    if [ -d "${KERNEL_DIR}/out/dist" ]; then
        DIST_DIR="${KERNEL_DIR}/out/dist"
    fi
fi

echo "--- Dist directory: ${DIST_DIR}"
ls -la "${DIST_DIR}" || true

if [ -f "${DIST_DIR}/Image" ]; then
    echo "SUCCESS: Found kernel Image at ${DIST_DIR}/Image"
elif [ -f "${DIST_DIR}/Image.lz4" ]; then
    echo "SUCCESS: Found compressed kernel Image.lz4 at ${DIST_DIR}/Image.lz4"
else
    echo "ERROR: Kernel Image not found in dist directory!" >&2
    exit 1
fi

echo "===> Build completed successfully."
