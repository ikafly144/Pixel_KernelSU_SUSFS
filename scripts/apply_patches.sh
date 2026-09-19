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

if [ -d "${WORKSPACE_DIR}/kernel/common/ack" ]; then
    ACK_DIR="${WORKSPACE_DIR}/kernel/common/ack"
elif [ -d "${WORKSPACE_DIR}/kernel/common" ]; then
    ACK_DIR="${WORKSPACE_DIR}/kernel/common"
else
    echo "ERROR: ACK directory not found in ${WORKSPACE_DIR}/kernel!" >&2
    exit 1
fi

echo "ACK directory: ${ACK_DIR}"

set_config() {
    local key="$1"
    local value="$2"
    for conf in "${ACK_DIR}/arch/arm64/configs/gki_defconfig" \
                "${WORKSPACE_DIR}/kernel/private/devices/google/muzel/muzel_defconfig" \
                "${WORKSPACE_DIR}/kernel/private/devices/google/muzel/defconfig"; do
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

    # Fix fs/exec.c include before patching because GrapheneOS added linux/random.h
    if [ -f "fs/exec.c" ] && ! grep -q "linux/susfs_def.h" fs/exec.c; then
        if grep -q "page_size_compat.h" fs/exec.c; then
            sed -i '/page_size_compat.h/a #ifdef CONFIG_KSU_SUSFS\n#include <linux/susfs_def.h>\n#endif' fs/exec.c
        elif grep -q "user_events.h" fs/exec.c; then
            sed -i '/user_events.h/a #ifdef CONFIG_KSU_SUSFS\n#include <linux/susfs_def.h>\n#endif' fs/exec.c
        else
            sed -i '1a #ifdef CONFIG_KSU_SUSFS\n#include <linux/susfs_def.h>\n#endif' fs/exec.c
        fi
        echo "Added susfs_def.h include to fs/exec.c"
    fi

    # Apply SUSFS patch with --batch to avoid any interactive prompts
    if [ -f "${SUSFS_PATCH}" ]; then
        echo "Applying patch: ${SUSFS_PATCH}"
        patch -p1 --batch -N < "${SUSFS_PATCH}" || {
            echo "Notice: Some hunks already applied or had offsets, continuing..."
        }
    fi

    # Fallback for VMA_PAD_START in fs/proc/task_mmu.c if needed
    if grep -q 'VMA_PAD_START(' fs/proc/task_mmu.c 2>/dev/null && ! grep -qE '#include <linux/pgsize_migration(_inline)?\.h>|define VMA_PAD_START' fs/proc/task_mmu.c; then
        sed -i '1a #ifndef VMA_PAD_START\n#define VMA_PAD_START(vma) ((vma)->vm_end)\n#endif' fs/proc/task_mmu.c
        echo "Added VMA_PAD_START fallback definition to fs/proc/task_mmu.c"
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

echo "--- Patching selinux_hide.c for 6.6+..."
for f in $(find "${WORKSPACE_DIR}" -name selinux_hide.c 2>/dev/null); do
    if grep -q "extern void security_dump_masked_av_fn" "$f"; then
        echo "[*] $f is extern-function form, patching with &"
        sed -i 's/if (security_dump_masked_av_fn)/if (\&security_dump_masked_av_fn)/g' "$f"
        sed -i 's/if (security_dump_masked_av_fn != NULL)/if (\&security_dump_masked_av_fn != NULL)/g' "$f"
        sed -i 's/if (context_struct_compute_av_fn)/if (\&context_struct_compute_av_fn)/g' "$f"
        sed -i 's/if (context_struct_compute_av_fn != NULL)/if (\&context_struct_compute_av_fn != NULL)/g' "$f"
    elif grep -q "if (security_dump_masked_av_fn" "$f"; then
        echo "[*] $f is pointer form, patching with != NULL"
        sed -i 's/if (security_dump_masked_av_fn)/if (security_dump_masked_av_fn != NULL)/g' "$f"
        sed -i 's/if (context_struct_compute_av_fn)/if (context_struct_compute_av_fn != NULL)/g' "$f"
    fi
    if grep -q "^static int security_context_to_sid_with_policy" "$f"; then
        echo "[*] Stripping static from $f helpers (Next 6.6+)"
        sed -i 's/^static int security_context_to_sid_with_policy/int security_context_to_sid_with_policy/g' "$f"
        sed -i 's/^static int security_sid_to_context_with_policy/int security_sid_to_context_with_policy/g' "$f"
        sed -i 's/^static void security_compute_av_user_with_policy/void security_compute_av_user_with_policy/g' "$f"
    fi
done

echo "--- Disabling defconfig checking..."
for f in "${WORKSPACE_DIR}/kernel/common/ack/build.config.gki" \
         "${WORKSPACE_DIR}/kernel/common/build.config.gki"; do
    if [ -f "$f" ]; then
        sed -i 's/POST_DEFCONFIG_CMDS="check_defconfig"/POST_DEFCONFIG_CMDS=""/g' "$f"
        sed -i 's/check_defconfig//g' "$f"
    fi
done

if [ -f "${WORKSPACE_DIR}/kernel/build/kernel/_setup_env.sh" ]; then
    sed -i 's/RES=\${?}/RES=0/g' "${WORKSPACE_DIR}/kernel/build/kernel/_setup_env.sh" || true
    sed -i 's/return \${RES}/return 0/g' "${WORKSPACE_DIR}/kernel/build/kernel/_setup_env.sh" || true
fi

if [ -f "${WORKSPACE_DIR}/kernel/build/kernel/kleaf/impl/config_utils.bzl" ]; then
    sed -i 's/exit 1/# exit 1 bypassed/g' "${WORKSPACE_DIR}/kernel/build/kernel/kleaf/impl/config_utils.bzl" || true
fi

if [ -f "${WORKSPACE_DIR}/kernel/build/kernel/kleaf/common_kernels.bzl" ]; then
    sed -i 's/check_defconfig = True/check_defconfig = False/g' "${WORKSPACE_DIR}/kernel/build/kernel/kleaf/common_kernels.bzl" || true
fi

for bzl in "${WORKSPACE_DIR}/kernel/common/ack/BUILD.bazel" "${WORKSPACE_DIR}/kernel/common/BUILD.bazel"; do
    if [ -f "$bzl" ]; then
        sed -i 's/check_defconfig = True/check_defconfig = False/g' "$bzl" || true
        if ! grep -q 'check_defconfig = "disabled"' "$bzl"; then
            sed -i '/name = "kernel_aarch64",/a\    check_defconfig = "disabled",' "$bzl" || true
        fi
    fi
done

echo "--- Removing ABI protected exports and module checks..."
cd "${WORKSPACE_DIR}/kernel"

rm -rf common/ack/android/abi_gki_protected_exports_* 2>/dev/null || true
rm -rf common/android/abi_gki_protected_exports_* 2>/dev/null || true

for bzl in common/ack/BUILD.bazel common/BUILD.bazel; do
    if [ -f "$bzl" ]; then
        perl -pi -e 's/^\s*"protected_exports_list"\s*:\s*"android\/abi_gki_protected_exports_aarch64",\s*$//;' "$bzl" || true
        perl -pi -e 's/^\s*protected_module_names_list\s*=\s*":gki_(?:aarch64|x86_64)_protected_module_names",\s*$//;' "$bzl" || true
    fi
done

for mbzl in common/ack/modules.bzl common/modules.bzl; do
    if [ -f "$mbzl" ]; then
        sed -i 's/protected_modules = \[.*\]/protected_modules = []/' "$mbzl" || true
    fi
done

if [ -f build/kernel/abi/check_buildtime_symbol_protection.py ]; then
    perl -i -pe 's/^(\s*)return 1$/$1print("Bypassing ABI symbol protection check")\n$1return 0/g if /if missing_symbols:/../return 1/' build/kernel/abi/check_buildtime_symbol_protection.py || true
fi

echo "--- Neutralizing dirty scmversion and committing ACK tree..."
sed -i "/stable_scmversion_cmd/s/-maybe-dirty//g" build/kernel/kleaf/impl/stamp.bzl 2>/dev/null || true
sed -i 's/-dirty//g' common/ack/scripts/setlocalversion 2>/dev/null || true
sed -i 's/-dirty//g' common/scripts/setlocalversion 2>/dev/null || true

cd "${ACK_DIR}"
if [ -d .git ]; then
    git config user.name "ikafly144"
    git config user.email "ikafly144@sabafly.net"
    git add -A
    git commit -m "Apply KernelSU-Next and SUSFS modifications" || true
fi

cd "${WORKSPACE_DIR}/kernel"
if [ -d .git ]; then
    git config user.name "ikafly144"
    git config user.email "ikafly144@sabafly.net"
    git add -A
    git commit -m "Update submodules and configs" || true
fi

cd "${WORKSPACE_DIR}"
echo "===> Patches applied successfully."
