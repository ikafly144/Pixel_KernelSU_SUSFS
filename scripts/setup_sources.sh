#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

KERNEL_VER="${1:-6.6}"
ROOT_FLAVOR="${2:-next}"
ROOT_COMMIT="${3:-}"
SUSFS_COMMIT="${4:-}"
BUILD_TAG="${5:-}"

echo "===> Setting up sources for Pixel 10 (muzel) - Kernel ${KERNEL_VER} (Root: ${ROOT_FLAVOR})..."

WORKSPACE_DIR="${GITHUB_WORKSPACE:-$(pwd)}"
cd "${WORKSPACE_DIR}"

if [ "${KERNEL_VER}" = "6.6" ]; then
    GITLAB_REPO="https://gitlab.com/grapheneos/kernel_pixel_6.6.git"
    GIT_REF="2026090500" # Target: CP3A.260905.009 (2026-09-05)
    if [ -n "${BUILD_TAG}" ] && [ "${BUILD_TAG}" != "All" ]; then
        CLEANED_TAG=$(echo "${BUILD_TAG}" | tr -d '-')
        if [ ${#CLEANED_TAG} -eq 8 ]; then
            GIT_REF="${CLEANED_TAG}00"
        elif [ ${#CLEANED_TAG} -eq 10 ]; then
            GIT_REF="${CLEANED_TAG}"
        fi
    fi
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
        git submodule update --init --depth 1
    fi
    cd "${WORKSPACE_DIR}"
else
    echo "kernel directory already exists, skipping clone."
fi

echo "--- Cloning root implementation (${ROOT_FLAVOR})..."
rm -rf root_src
case "${ROOT_FLAVOR}" in
    next)
        git clone --depth 1 --branch dev-susfs https://github.com/pershoot/KernelSU-Next.git root_src
        ;;
    kernelsu)
        git clone --depth 1 https://github.com/tiann/KernelSU.git root_src
        ;;
    resukisu)
        git clone --depth 1 https://github.com/ReSukiSU/ReSukiSU.git root_src
        ;;
    sukisu-ultra)
        git clone --depth 1 https://github.com/SukiSU-Ultra/SukiSU-Ultra.git root_src
        ;;
    *)
        echo "Defaulting to KernelSU-Next (dev-susfs)..."
        git clone --depth 1 --branch dev-susfs https://github.com/pershoot/KernelSU-Next.git root_src
        ;;
esac

if [ -n "${ROOT_COMMIT}" ]; then
    echo "Checking out root commit ${ROOT_COMMIT}..."
    cd root_src
    git fetch --depth 1 origin "${ROOT_COMMIT}" || true
    git checkout "${ROOT_COMMIT}" || true
    cd "${WORKSPACE_DIR}"
fi

echo "--- Cloning susfs4ksu (${SUSFS_BRANCH})..."
if [ ! -d "susfs4ksu" ]; then
    git clone --depth 1 --branch "${SUSFS_BRANCH}" https://gitlab.com/simonpunk/susfs4ksu.git susfs4ksu
    if [ -n "${SUSFS_COMMIT}" ]; then
        cd susfs4ksu
        git fetch --depth 1 origin "${SUSFS_COMMIT}" || true
        git checkout "${SUSFS_COMMIT}" || true
        cd "${WORKSPACE_DIR}"
    fi
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
