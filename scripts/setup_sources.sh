#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

KERNEL_VER="${1:-6.6}"
echo "===> Setting up sources for Pixel 10 (muzel) - Kernel ${KERNEL_VER}..."

WORKSPACE_DIR="${GITHUB_WORKSPACE:-$(pwd)}"
cd "${WORKSPACE_DIR}"

if [ "${KERNEL_VER}" = "6.6" ]; then
    GITLAB_REPO="https://gitlab.com/grapheneos/kernel_pixel_6.6.git"
    GIT_REF="2026090500" # Target: CP3A.260905.009 (2026-09-05)
    SUSFS_BRANCH="gki-android15-6.6"
elif [ "${KERNEL_VER}" = "6.12" ]; then
    GITLAB_REPO="https://gitlab.com/grapheneos/kernel_pixel_6.12.git"
    GIT_REF="17-qpr2-base" # Target: Android 17 QPR2 preview
    SUSFS_BRANCH="gki-android16-6.12"
else
    echo "ERROR: Unsupported kernel version: ${KERNEL_VER}" >&2
    exit 1
fi

echo "--- Cloning GrapheneOS Pixel kernel repository (${GIT_REF})..."
if [ ! -d "kernel" ]; then
    git clone --depth 1 --branch "${GIT_REF}" "${GITLAB_REPO}" kernel
    cd kernel
    if [ "${KERNEL_VER}" = "6.6" ]; then
        echo "--- Initializing submodules (common/ack)..."
        git submodule update --init --depth 1 --recursive
    fi
    cd "${WORKSPACE_DIR}"
else
    echo "kernel directory already exists, skipping clone."
fi

echo "--- Cloning KernelSU-Next (pershoot dev-susfs fork)..."
if [ ! -d "KernelSU-Next" ]; then
    git clone --depth 1 --branch dev-susfs https://github.com/pershoot/KernelSU-Next.git KernelSU-Next
else
    echo "KernelSU-Next directory already exists, skipping clone."
fi

echo "--- Cloning susfs4ksu (${SUSFS_BRANCH})..."
if [ ! -d "susfs4ksu" ]; then
    git clone --depth 1 --branch "${SUSFS_BRANCH}" https://gitlab.com/simonpunk/susfs4ksu.git susfs4ksu
else
    echo "susfs4ksu directory already exists, skipping clone."
fi

echo "--- Cloning AnyKernel3..."
if [ ! -d "AnyKernel3" ]; then
    git clone --depth 1 https://github.com/osm0sis/AnyKernel3.git AnyKernel3
else
    echo "AnyKernel3 directory already exists, skipping clone."
fi

echo "===> Source setup complete."
