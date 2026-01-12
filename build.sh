#!/bin/bash

# ================= COLOR =================
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
white='\033[0m'

# ================= PATH =================
DEFCONFIG=vendor/msm8937-perf_defconfig
ROOTDIR=$(pwd)
OUTDIR="$ROOTDIR/out/arch/arm64/boot"
ANYKERNEL_DIR="$ROOTDIR/AnyKernel"

KIMG_DTB="$OUTDIR/Image.gz-dtb"
KIMG="$OUTDIR/Image.gz"

# ================= TOOLCHAIN (CLANG) =================
export PATH="$ROOTDIR/clang-zyc/bin:$PATH"

# ================= INFO =================
KERNEL_NAME="ReLIFE"
DEVICE="Mi8937"

# ================= DATE (WIB) =================
DATE_TITLE=$(TZ=Asia/Jakarta date +"%d%m%Y")
TIME_TITLE=$(TZ=Asia/Jakarta date +"%H%M%S")
BUILD_DATETIME=$(TZ=Asia/Jakarta date +"%d %B %Y")

# ================= TELEGRAM =================
TG_BOT_TOKEN="7443002324:AAFpDcG3_9L0Jhy4v98RCBqu2pGfznBCiDM"
TG_CHAT_ID="-1003520316735"

# ================= GLOBAL =================
BUILD_TIME="unknown"
KERNEL_VERSION="unknown"
TC_INFO="unknown"
IMG_USED="unknown"
MD5_HASH="unknown"
ZIP_NAME=""

# ================= FUNCTION =================

clone_anykernel() {
    [ -d "$ANYKERNEL_DIR" ] || git clone https://github.com/rahmatsobrian/AnyKernel3.git "$ANYKERNEL_DIR"
}

get_toolchain_info() {
    if command -v clang >/dev/null 2>&1; then
        CLANG_VER=$(clang --version | head -n1)
        TC_INFO="$CLANG_VER"
    fi
}

get_kernel_version() {
    VERSION=$(grep -E '^VERSION =' Makefile | awk '{print $3}')
    PATCHLEVEL=$(grep -E '^PATCHLEVEL =' Makefile | awk '{print $3}')
    SUBLEVEL=$(grep -E '^SUBLEVEL =' Makefile | awk '{print $3}')
    KERNEL_VERSION="${VERSION}.${PATCHLEVEL}.${SUBLEVEL}"
}

send_telegram_error() {
    curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d chat_id="${TG_CHAT_ID}" \
        -d parse_mode=Markdown \
        -d text="❌ *Kernel CI Build Failed*"
    exit 1
}

send_telegram_start() {
    curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d chat_id="${TG_CHAT_ID}" \
        -d parse_mode=Markdown \
        -d text="🚀 *Kernel CI Build Started*"
}

# ================= BUILD =================

build_kernel() {
    send_telegram_start
    get_toolchain_info

    echo -e "$yellow[+] Preparing build environment...$white"
    rm -rf out && mkdir -p out

    echo -e "$yellow[+] Loading defconfig...$white"
    make O=out ARCH=arm64 ${DEFCONFIG} || send_telegram_error

    echo -e "$yellow[+] Merging config fragments...$white"
    scripts/kconfig/merge_config.sh -m \
        out/.config \
        arch/arm64/configs/vendor/common.config \
        arch/arm64/configs/vendor/feature/lto.config \
        arch/arm64/configs/vendor/xiaomi/msm8937/mi8937.config || send_telegram_error

    echo -e "$yellow[+] Finalizing config (olddefconfig)...$white"
    make O=out ARCH=arm64 olddefconfig </dev/null || send_telegram_error

    BUILD_START=$(TZ=Asia/Jakarta date +%s)

    echo -e "$yellow[+] Compiling kernel...$white"
    make -j$(nproc --all) \
        O=out \
        ARCH=arm64 \
        CC=clang \
        LD=ld.lld \
        LLVM=1 \
        LLVM_IAS=1 \
        CROSS_COMPILE=aarch64-linux-gnu- \
        CROSS_COMPILE_ARM32=arm-linux-gnueabi- || send_telegram_error

    BUILD_END=$(TZ=Asia/Jakarta date +%s)
    DIFF=$((BUILD_END - BUILD_START))
    BUILD_TIME="$((DIFF / 60)) min $((DIFF % 60)) sec"

    get_kernel_version
    ZIP_NAME="${KERNEL_NAME}-${DEVICE}-${KERNEL_VERSION}-${DATE_TITLE}-${TIME_TITLE}.zip"
}

# ================= PACK =================

pack_kernel() {
    clone_anykernel
    cd "$ANYKERNEL_DIR" || exit 1

    rm -f Image* *.zip

    if [ -f "$KIMG_DTB" ]; then
        cp "$KIMG_DTB" Image.gz-dtb
        IMG_USED="Image.gz-dtb"
    else
        cp "$KIMG" Image.gz
        IMG_USED="Image.gz"
    fi

    zip -r9 "$ZIP_NAME" .
    MD5_HASH=$(md5sum "$ZIP_NAME" | awk '{print $1}')
}

# ================= UPLOAD =================

upload_telegram() {
    curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendDocument" \
        -F chat_id="${TG_CHAT_ID}" \
        -F document=@"$ANYKERNEL_DIR/$ZIP_NAME" \
        -F caption="✅ *Build Success*
Kernel: ${KERNEL_NAME}
Device: ${DEVICE}
Version: ${KERNEL_VERSION}
Time: ${BUILD_TIME}"
}

# ================= RUN =================

START=$(date +%s)
build_kernel
pack_kernel
upload_telegram
END=$(date +%s)

echo -e "$green[✓] Done in $((END - START)) seconds$white"
