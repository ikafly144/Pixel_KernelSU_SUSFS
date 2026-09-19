#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

KERNEL_VER="${1:-6.6}"
INCLUDE_MODULES="${2:-true}"
DEVICE_CHECK="${3:-true}"

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
    mkdir -p modules/vendor_dlkm
    find "${DIST_DIR}" -type f -name "*.ko" -exec cp {} modules/vendor_dlkm/ \;
    # Also keep a copy directly in modules/
    find "${DIST_DIR}" -type f -name "*.ko" -exec cp {} modules/ \;
    MODULE_COUNT=$(find modules/ -name "*.ko" | wc -l)
    echo "Copied ${MODULE_COUNT} vendor modules into AnyKernel3."
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
block=boot;
is_slot_device=auto;
ramdisk_compression=auto;
patch_vbmeta_flag=auto;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;

# boot install
dump_boot;

write_boot;
## end boot install
EOF

chmod +x anykernel.sh

DATE_TAG=$(date -u +%Y%m%d_%H%M%S)
ZIP_NAME="AnyKernel3-Pixel10-muzel-v${KERNEL_VER}-${DATE_TAG}.zip"

echo "--- Creating AnyKernel3 zip: ${ZIP_NAME}..."
zip -r9 "${WORKSPACE_DIR}/${ZIP_NAME}" * -x "*.git*" "README.md" "*.zip"

cd "${WORKSPACE_DIR}"
echo "ZIP_PATH=${WORKSPACE_DIR}/${ZIP_NAME}" >> "${GITHUB_ENV:-/dev/null}"
echo "ZIP_NAME=${ZIP_NAME}" >> "${GITHUB_ENV:-/dev/null}"
echo "SUCCESS: Created ${ZIP_NAME} ($(du -h "${ZIP_NAME}" | cut -f1))"
