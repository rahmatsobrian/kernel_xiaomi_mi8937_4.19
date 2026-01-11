#!/bin/bash

# ================= COLOR =================
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
white='\033[0m'

# ================= PATH =================
DEFCONFIG=/vendor/msm8937-perf_defconfig
ROOTDIR=$(pwd)
OUTDIR="$ROOTDIR/out/arch/arm64/boot"
ANYKERNEL_DIR="$ROOTDIR/AnyKernel"

KIMG_DTB="$OUTDIR/Image.gz-dtb"
KIMG="$OUTDIR/Image.gz"

# ================= TOOLCHAIN (CLANG UBUNTU) =================
export PATH="$ROOTDIR/clang-zyc/bin:$PATH"

TC64="aarch64-linux-android-"
TC32="arm-linux-androideabi-"

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
    if [ ! -d "$ANYKERNEL_DIR" ]; then
        echo -e "$yellow[+] Cloning AnyKernel3...$white"
        git clone https://github.com/rahmatsobrian/AnyKernel3.git "$ANYKERNEL_DIR" || exit 1
    fi
}

get_toolchain_info() {
    if command -v clang >/dev/null 2>&1; then
        if clang --version | grep -qi "zyc\|zycromerz"; then
            CLANG_VER=$(clang --version | head -n1 | sed 's/.*version //')
            TC_INFO="ZYC Clang ${CLANG_VER}"
        else
            CLANG_VER=$(clang --version | head -n1)
            TC_INFO="Clang (${CLANG_VER})"
        fi
    else
        TC_INFO="unknown"
    fi
}

get_kernel_version() {
    if [ -f "Makefile" ]; then
        VERSION=$(grep -E '^VERSION =' Makefile | awk '{print $3}')
        PATCHLEVEL=$(grep -E '^PATCHLEVEL =' Makefile | awk '{print $3}')
        SUBLEVEL=$(grep -E '^SUBLEVEL =' Makefile | awk '{print $3}')
        KERNEL_VERSION="${VERSION}.${PATCHLEVEL}.${SUBLEVEL}"
    else
        KERNEL_VERSION="unknown"
    fi
}

send_telegram_error() {
    curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d chat_id="${TG_CHAT_ID}" \
        -d parse_mode=Markdown \
        -d text="❌ *Kernel CI Build Failed*

📄 *Log attached below* "

    send_telegram_log
}

send_telegram_log() {
    LOG_FILE="$ROOTDIR/logs/build.txt"

    [ ! -f "$LOG_FILE" ] && return

    curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendDocument" \
        -F chat_id="${TG_CHAT_ID}" \
        -F document=@"${LOG_FILE}" 
}

build_kernel() {

get_toolchain_info

    echo -e "$yellow[+] Building kernel...$white"

curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d chat_id="${TG_CHAT_ID}" \
        -d parse_mode=Markdown \
        -d text="🚀 *Kernel CI Build Started* "

    rm -rf out
    mkdir -p out
    make O=out ARCH=arm64 ${DEFCONFIG} || {
        send_telegram_error
        exit 1
    }

    BUILD_START=$(TZ=Asia/Jakarta date +%s)

    make -j$(nproc --all) \
        O=out \
        ARCH=arm64 \
        CC=clang \
        LD=ld.lld \
        LLVM=1 \
        LLVM_IAS=1 \
        AR=llvm-ar \
        NM=llvm-nm \
        OBJCOPY=llvm-objcopy \
        OBJDUMP=llvm-objdump \
        STRIP=llvm-strip \
        CROSS_COMPILE=${TC64} \
        CROSS_COMPILE_ARM32=${TC32} || {
        send_telegram_error
        exit 1
    }

    BUILD_END=$(TZ=Asia/Jakarta date +%s)
    DIFF=$((BUILD_END - BUILD_START))
    BUILD_TIME="$((DIFF / 60)) min $((DIFF % 60)) sec"

    get_kernel_version

    ZIP_NAME="${KERNEL_NAME}-${DEVICE}-${KERNEL_VERSION}-${DATE_TITLE}-${TIME_TITLE}.zip"
}

pack_kernel() {
    echo -e "$yellow[+] Packing AnyKernel...$white"

    clone_anykernel
    cd "$ANYKERNEL_DIR" || exit 1

    rm -f Image* *.zip

    if [ -f "$KIMG_DTB" ]; then
        cp "$KIMG_DTB" Image.gz-dtb
        IMG_USED="Image.gz-dtb"
    elif [ -f "$KIMG" ]; then
        cp "$KIMG" Image.gz
        IMG_USED="Image.gz"
    else
        send_telegram_error
        exit 1
    fi

    zip -r9 "$ZIP_NAME" . -x ".git*" "README.md"
    MD5_HASH=$(md5sum "$ZIP_NAME" | awk '{print $1}')

    echo -e "$green[✓] Zip created: $ZIP_NAME ($IMG_USED)$white"
}

upload_telegram() {
    ZIP_PATH="$ANYKERNEL_DIR/$ZIP_NAME"
    [ ! -f "$ZIP_PATH" ] && return

    echo -e "$yellow[+] Uploading to Telegram...$white"

    curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendDocument" \
        -F chat_id="${TG_CHAT_ID}" \
        -F document=@"${ZIP_PATH}" \
        -F parse_mode=Markdown \
        -F caption="🔥 *Kernel CI Build Success*

📱 *Device* : ${DEVICE}
📦 *Kernel Name* : ${KERNEL_NAME}
🍃 *Kernel Version* : ${KERNEL_VERSION}

🛠 *Toolchain* :
\`${TC_INFO}\`

⌛ *Build Time* : ${BUILD_TIME}
🕒 *Build Date* : ${BUILD_DATETIME}

🔐 *MD5* :
\`${MD5_HASH}\`

❓ *Need Test*"

send_telegram_log
}

# ================= RUN =================
START=$(TZ=Asia/Jakarta date +%s)

build_kernel
pack_kernel
upload_telegram

END=$(TZ=Asia/Jakarta date +%s)
echo -e "$green[✓] Done in $((END - START)) seconds$white"
