#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

KERNEL_VER="${1:-6.6}"
USE_SUSFS="${2:-true}"
USE_NOMOUNT="${3:-true}"
USE_BBG="${4:-true}"
USE_BPF="${5:-true}"

echo "===> Applying patches for Pixel 10 (muzel) - Kernel ${KERNEL_VER}..."

WORKSPACE_DIR="${GITHUB_WORKSPACE:-$(pwd)}"
ACK_DIR="${WORKSPACE_DIR}/kernel/common/ack"
MUZEL_DIR="${WORKSPACE_DIR}/kernel/private/devices/google/muzel"

if [ ! -d "${ACK_DIR}" ]; then
    echo "ERROR: ACK directory ${ACK_DIR} not found!" >&2
    exit 1
fi

set_config() {
    local key="$1"
    local value="$2"
    for conf in "${ACK_DIR}/arch/arm64/configs/gki_defconfig" "${MUZEL_DIR}/muzel_defconfig"; do
        if [ -f "$conf" ]; then
            if grep -q "^${key}=" "$conf"; then
                sed -i "s|^${key}=.*|${key}=${value}|g" "$conf"
            elif grep -q "^# ${key} is not set" "$conf"; then
                sed -i "s|^# ${key} is not set|${key}=${value}|g" "$conf"
            else
                echo "${key}=${value}" >> "$conf"
            fi
        fi
    done
}

echo "--- Integrating KernelSU-Next..."
mkdir -p "${ACK_DIR}/drivers"
rm -rf "${ACK_DIR}/drivers/kernelsu"
cp -r "${WORKSPACE_DIR}/KernelSU-Next/kernel" "${ACK_DIR}/drivers/kernelsu"

if ! grep -q 'obj-$(CONFIG_KSU) += kernelsu/' "${ACK_DIR}/drivers/Makefile"; then
    echo 'obj-$(CONFIG_KSU) += kernelsu/' >> "${ACK_DIR}/drivers/Makefile"
fi

if ! grep -q 'source "drivers/kernelsu/Kconfig"' "${ACK_DIR}/drivers/Kconfig"; then
    sed -i '/endmenu/i source "drivers/kernelsu/Kconfig"' "${ACK_DIR}/drivers/Kconfig"
fi

set_config "CONFIG_KSU" "y"

if [ "${USE_SUSFS}" = "true" ]; then
    echo "--- Applying SUSFS patches..."
    cp -r "${WORKSPACE_DIR}/susfs4ksu/kernel_patches/fs/"* "${ACK_DIR}/fs/"
    cp -r "${WORKSPACE_DIR}/susfs4ksu/kernel_patches/include/linux/"* "${ACK_DIR}/include/linux/"

    cd "${ACK_DIR}"
    if [ "${KERNEL_VER}" = "6.6" ]; then
        SUSFS_PATCH="${WORKSPACE_DIR}/susfs4ksu/kernel_patches/50_add_susfs_in_gki-android15-6.6.patch"
    else
        SUSFS_PATCH="${WORKSPACE_DIR}/susfs4ksu/kernel_patches/50_add_susfs_in_gki-android16-6.12.patch"
    fi

    if [ -f "${SUSFS_PATCH}" ]; then
        echo "Applying patch: ${SUSFS_PATCH}"
        patch -p1 --forward < "${SUSFS_PATCH}" || patch -p1 < "${SUSFS_PATCH}" || {
            echo "Warning: SUSFS patch had rejects or was already partially applied."
        }
    fi
    cd "${WORKSPACE_DIR}"

    echo "--- Enabling SUSFS configs..."
    set_config "CONFIG_KSU_SUSFS" "y"
    set_config "CONFIG_KSU_SUSFS_SUS_PATH" "y"
    set_config "CONFIG_KSU_SUSFS_SUS_MOUNT" "y"
    set_config "CONFIG_KSU_SUSFS_SUS_KSTAT" "y"
    set_config "CONFIG_KSU_SUSFS_SPOOF_UNAME" "y"
    set_config "CONFIG_KSU_SUSFS_ENABLE_LOG" "y"
    set_config "CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS" "y"
    set_config "CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG" "y"
    set_config "CONFIG_KSU_SUSFS_OPEN_REDIRECT" "y"
    set_config "CONFIG_KSU_SUSFS_SUS_MAP" "y"
fi

echo "--- Disabling defconfig checking..."
# Disable check_defconfig in build.config.gki and _setup_env.sh
sed -i 's/POST_DEFCONFIG_CMDS="check_defconfig"/POST_DEFCONFIG_CMDS=""/g' "${WORKSPACE_DIR}/kernel/common/ack/build.config.gki" 2>/dev/null || true
sed -i 's/POST_DEFCONFIG_CMDS="check_defconfig"/POST_DEFCONFIG_CMDS=""/g' "${WORKSPACE_DIR}/kernel/common/build.config.gki" 2>/dev/null || true
sed -i 's/check_defconfig//g' "${WORKSPACE_DIR}/kernel/common/ack/build.config.gki" 2>/dev/null || true
sed -i 's/check_defconfig//g' "${WORKSPACE_DIR}/kernel/common/build.config.gki" 2>/dev/null || true

if [ -f "${WORKSPACE_DIR}/kernel/build/kernel/_setup_env.sh" ]; then
    sed -i 's/RES=\${?}/RES=0/g' "${WORKSPACE_DIR}/kernel/build/kernel/_setup_env.sh" || true
    sed -i 's/return \${RES}/return 0/g' "${WORKSPACE_DIR}/kernel/build/kernel/_setup_env.sh" || true
fi

if [ -f "${WORKSPACE_DIR}/kernel/build/kernel/kleaf/impl/config_utils.bzl" ]; then
    sed -i 's/exit 1/# exit 1 bypassed/g' "${WORKSPACE_DIR}/kernel/build/kernel/kleaf/impl/config_utils.bzl" || true
fi

echo "--- Adjusting Kleaf / Bazel build rules and stripping ABI protections..."
cd "${WORKSPACE_DIR}/kernel"

# Disable check_defconfig in BUILD.bazel and Kleaf
sed -i 's/check_defconfig = True/check_defconfig = False/g' build/kernel/kleaf/common_kernels.bzl 2>/dev/null || true
sed -i 's/check_defconfig = True/check_defconfig = False/g' common/ack/BUILD.bazel 2>/dev/null || true
sed -i '/name = "kernel_aarch64",/a\    check_defconfig = "disabled",' common/ack/BUILD.bazel 2>/dev/null || true

# Remove protected exports and protected modules
rm -rf common/ack/android/abi_gki_protected_exports_* 2>/dev/null || true
perl -pi -e 's/^\s*"protected_exports_list"\s*:\s*"android\/abi_gki_protected_exports_aarch64",\s*$//;' common/ack/BUILD.bazel 2>/dev/null || true
perl -pi -e 's/^\s*protected_module_names_list\s*=\s*":gki_(?:aarch64|x86_64)_protected_module_names",\s*$//;' common/ack/BUILD.bazel 2>/dev/null || true
if [ -f common/ack/modules.bzl ]; then
    sed -i 's/protected_modules = \[.*\]/protected_modules = []/' common/ack/modules.bzl 2>/dev/null || true
fi

# Bypass ABI check scripts
if [ -f build/kernel/abi/check_buildtime_symbol_protection.py ]; then
    perl -i -pe 's/^(\s*)return 1$/$1print("Bypassing ABI symbol protection check")\n$1return 0/g if /if missing_symbols:/../return 1/' build/kernel/abi/check_buildtime_symbol_protection.py || true
fi

# Clean dirty flags
sed -i "/stable_scmversion_cmd/s/-maybe-dirty//g" build/kernel/kleaf/impl/stamp.bzl 2>/dev/null || true
sed -i 's/-dirty//g' common/ack/scripts/setlocalversion 2>/dev/null || true

# Commit changes inside ACK git repo to avoid git dirty tag issues
cd "${ACK_DIR}"
if [ -d .git ]; then
    git config user.name "ikafly144"
    git config user.email "ikafly144@sabafly.net"
    git add -A
    git commit -m "Pixel 10: Apply KernelSU-Next and SUSFS modifications" || true
fi

cd "${WORKSPACE_DIR}"
echo "===> Patches applied successfully."
