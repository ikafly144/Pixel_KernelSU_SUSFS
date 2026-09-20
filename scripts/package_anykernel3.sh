#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

KERNEL_VER="${1:-6.6}"
SUBLEVEL="${2:-127}"
BUILD_ID="${3:-CP3A.260905.009}"
ROOT_FLAVOR="${4:-KernelSU-Next}"
INCLUDE_MODULES="${5:-true}"
DEVICE_CHECK="${6:-true}"

echo "===> Packaging AnyKernel3.zip for Pixel 10 (muzel)..."

WORKSPACE_DIR="${GITHUB_WORKSPACE:-$(pwd)}"
KERNEL_DIR="${WORKSPACE_DIR}/kernel"
AK3_DIR="${WORKSPACE_DIR}/AnyKernel3"

DIST_DIR="${KERNEL_DIR}/out/muzel/dist"
if [ ! -d "${DIST_DIR}" ] && [ -d "${KERNEL_DIR}/out/dist" ]; then
    DIST_DIR="${KERNEL_DIR}/out/dist"
fi

if [ ! -d "${DIST_DIR}" ]; then
    echo "ERROR: Dist directory ${DIST_DIR} not found!" >&2
    exit 1
fi

cd "${AK3_DIR}"

# Ensure AnyKernel3 tools are 64-bit arm64 for Pixel 10 (Tensor G5 pure 64-bit)
if [ -f "tools/busybox" ] && file "tools/busybox" | grep -q "32-bit"; then
    echo "--- Detected 32-bit tools in AnyKernel3; updating to arm64 binaries..."
    git clone --depth 1 --branch arm64-tools https://github.com/osm0sis/AnyKernel3.git "${WORKSPACE_DIR}/arm64_tools_tmp"
    cp -f "${WORKSPACE_DIR}/arm64_tools_tmp"/* tools/
    chmod +x tools/*
    rm -rf "${WORKSPACE_DIR}/arm64_tools_tmp"
fi

# Patch update-binary and ak3-core.sh for KernelSU-Next / spoofed packages / vendor_dlkm support
if [ -f "META-INF/com/google/android/update-binary" ]; then
    echo "--- Patching update-binary for KernelSU-Next and vendor_dlkm support..."
    python3 -c '
with open("META-INF/com/google/android/update-binary", "r") as f:
    content = f.read()

target1 = "if [ -d /data/adb/magisk -a -f $AKHOME/magisk_patched ] || [ -d /data/data/me.weishu.kernelsu -a -f $AKHOME/kernelsu_patched ]; then"
repl1 = "if [ -d /data/adb/magisk -a -f $AKHOME/magisk_patched ] || [ -f $AKHOME/kernelsu_patched ] || [ -d /data/adb/ksu ] || [ -f /data/adb/ksud ] || [ -d /data/adb/modules ] || [ -d /data/data/me.weishu.kernelsu -a -f $AKHOME/kernelsu_patched ]; then"

target2 = "mv -f vendor system;"
repl2 = "mv -f vendor system; mv -f vendor_dlkm system;"

target3 = "cp -f /data/app/*/me.weishu.kernelsu*/lib/*/libksud.so /data/adb/ksud;"
repl3 = "cp -f /data/app/*/*kernelsu*/lib/*/libksud.so /data/adb/ksud 2>/dev/null || cp -f /data/app/*/*ksunext*/lib/*/libksud.so /data/adb/ksud 2>/dev/null || cp -f /data/app/*/lib/*/libksud.so /data/adb/ksud 2>/dev/null || true;"

if target1 in content:
    content = content.replace(target1, repl1)
if target2 in content:
    content = content.replace(target2, repl2)
if target3 in content:
    content = content.replace(target3, repl3)

with open("META-INF/com/google/android/update-binary", "w") as f:
    f.write(content)
'
fi

if [ -f "tools/ak3-core.sh" ]; then
    echo "--- Patching ak3-core.sh for KernelSU-Next detection..."
    python3 -c '
with open("tools/ak3-core.sh", "r") as f:
    content = f.read()

target1 = "elif [ -d /data/data/me.weishu.kernelsu ]"
repl1 = "elif [ -d /data/adb/ksu -o -f /data/adb/ksud -o -d /data/adb/modules -o -d /data/data/me.weishu.kernelsu -o -d /data/data/com.rifsxd.ksunext ]"

if target1 in content:
    content = content.replace(target1, repl1)

with open("tools/ak3-core.sh", "w") as f:
    f.write(content)
'
fi

# Clean previous zip or old Image
rm -f *.zip Image Image.lz4 dtb dtbo.img
rm -rf modules/

# Copy kernel image
if [ -f "${DIST_DIR}/Image" ]; then
    echo "--- Copying Image..."
    cp "${DIST_DIR}/Image" ./Image
elif [ -f "${DIST_DIR}/Image.lz4" ]; then
    echo "--- Copying Image.lz4..."
    cp "${DIST_DIR}/Image.lz4" ./Image.lz4
fi

# Copy DTB/DTBO if available
if [ -f "${DIST_DIR}/dtbo.img" ]; then
    echo "--- Copying dtbo.img..."
    cp "${DIST_DIR}/dtbo.img" ./dtbo.img
fi

# Copy vendor modules if requested
DOMODULES_VAL=0
if [ "${INCLUDE_MODULES}" = "true" ]; then
    DOMODULES_VAL=1
    echo "--- Copying vendor kernel modules (*.ko)..."
    mkdir -p modules/vendor/lib/modules
    mkdir -p modules/vendor_dlkm/lib/modules
    find "${DIST_DIR}" -type f -name "*.ko" -exec cp {} modules/vendor/lib/modules/ \;
    cp -r modules/vendor/lib/modules/* modules/vendor_dlkm/lib/modules/
    MODULE_COUNT=$(find modules/vendor/lib/modules -name "*.ko" | wc -l)
    echo "Copied ${MODULE_COUNT} vendor modules into AnyKernel3 (modules/vendor/lib/modules & modules/vendor_dlkm/lib/modules)."
fi

DEVICECHECK_VAL=0
if [ "${DEVICE_CHECK}" = "true" ]; then
    DEVICECHECK_VAL=1
fi

# Generate customized anykernel.sh
cat << 'EOF' > anykernel.sh
### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
# global properties
properties() { '
kernel.string=Google Pixel 10 (muzel) KernelSU-Next + SUSFS
EOF

cat << EOF >> anykernel.sh
do.devicecheck=${DEVICECHECK_VAL}
do.modules=${DOMODULES_VAL}
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=frankel
device.name2=blazer
device.name3=mustang
device.name4=muzel
device.name5=
supported.versions=
supported.patchlevels=
'; } # end properties

### AnyKernel install
## boot shell variables
BLOCK=boot;
IS_SLOT_DEVICE=auto;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;

# boot install
split_boot;

flash_boot;
flash_generic dtbo;
## end boot install
EOF

chmod +x anykernel.sh

ZIP_NAME="AnyKernel3-Pixel10-muzel-${KERNEL_VER}.${SUBLEVEL}-${BUILD_ID}-${ROOT_FLAVOR}.zip"

echo "--- Creating AnyKernel3 zip: ${ZIP_NAME}..."
zip -r9 "${WORKSPACE_DIR}/${ZIP_NAME}" * -x "*.git*" "README.md" "*.zip"

cd "${WORKSPACE_DIR}"
echo "ZIP_PATH=${WORKSPACE_DIR}/${ZIP_NAME}" >> "${GITHUB_ENV:-/dev/null}"
echo "ZIP_NAME=${ZIP_NAME}" >> "${GITHUB_ENV:-/dev/null}"
echo "SUCCESS: Created ${ZIP_NAME} ($(du -h "${ZIP_NAME}" | cut -f1))"
