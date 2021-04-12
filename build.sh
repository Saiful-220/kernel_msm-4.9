#!/bin/bash

TG_TOKEN=1794828116:AAGb7toh7J5tDg_okEmFDMDLkdZXOeOqjUo
TG_ID="-1001357583756"
COMPILER=clang
DEFCONFIG=sdm670-perf_defconfig
KERNEL=SiLonT
VERSION=Yuki
STATUS=Release
CLANG_VER=silont-project/silont-clang
GCC_VER=
CLEAN=false
BUILDHOST="Drone"

function setupEnv {
  if [[ $COMPILER = clang ]]; then
		[[ ! -d clang ]] && git clone --depth 2 https://github.com/"$CLANG_VER" clang
		export PATH=$(pwd)/clang/bin:$PATH
	elif [[  $COMPILER = gcc ]]; then
		[[ ! -d gcc ]] && git clone https://github.com/"$GCC_VER" gcc
		[[ ! -d gcc32 ]] && git clone https://github.com/arter97/arm32-gcc gcc32
	else
		COMP="'$COMPILER'"
		echo "ERROR: $COMP is not a valid compiler !"
		exit 1
	fi

	export USE_CCACHE=1
	SRC_TOP=$(pwd)
	OUT=$SRC_TOP/out
	ANYKERNEL=$OUT/AnyKernel3

	TIME=$(date +%H%M)
	LOG_FILE="$OUT/log~$TIME.txt"
	touch $LOG_FILE

	if [[ $CLEAN = true ]]; then
		make clean && make mrproper
	else
		[[ -d $OUT ]] && rm -rf $OUT/arch/arm64/boot
	fi

  rm -rf $ANYKERNEL

	FILE_NAME="$KERNEL-$VERSION-$STATUS~$TIME.zip"

	[[ ! -d out ]] && mkdir out

	jq --help > /dev/null || echo "ERROR: 'jq' not installed !"
}

function tgMsg {
	curl -s -X POST https://api.telegram.org/bot${TG_TOKEN}/sendMessage -d chat_id=${TG_ID} -d parse_mode=html -d text="$@"
}

function tgEdit {
	curl -s -X POST https://api.telegram.org/bot${TG_TOKEN}/editMessageText -d chat_id=${TG_ID} -d message_id="${MSG_ID}" -d parse_mode=html -d text="$@"
}

function tgFile {
	curl -s -F chat_id="${TG_ID}" -F document=@"$1" -F caption="$2" https://api.telegram.org/bot"${TG_TOKEN}"/sendDocument
}

function tgSticker {
	curl -s -F chat_id="${TG_ID}" -F sticker="$@" https://api.telegram.org/bot"${TG_TOKEN}"/sendSticker > /dev/null
}

function tgCast {
	if [[ ${MSG_ID} = "" ]]; then
		MSG_ID=$(tgMsg \
"<b>Compilation initialized</b>
<b>Host</b>: <code>$BUILDHOST</code>
<b>Kernel</b>: ${KERNEL}
<b>Version</b>: ${VERSION}
<b>Status</b>: ${STATUS}
<b>Linux stable tag</b>: <code>$(make kernelversion)</code>
<b>Compiler</b>: <code>${COMPILER}</code>
<b>Head</b>: <code>$(git log --oneline -1)</code>

<b>Status</b>: <code>$@</code>" | jq .result.message_id)
	else
		tgEdit \
"<b>Compilation initialized</b>
<b>Host</b>: <code>$BUILDHOST</code>
<b>Kernel</b>: ${KERNEL}
<b>Version</b>: ${VERSION}
<b>Status</b>: ${STATUS}
<b>Linux stable tag</b>: <code>$(make kernelversion)</code>
<b>Compiler</b>: <code>${COMPILER}</code>
<b>Head</b>: <code>$(git log --oneline -1)</code>

<b>Status</b>: <code>$@</code>"
  fi
}

function success {
	END=$(date +"%s")
    DIFF=$(( END - START ))
    tgCast "Done !"
    tgFile "$ZIP" "✅ Compilation took $((DIFF / 60)) minute(s) and $((DIFF % 60)) seconds!"
    tgSticker "CAACAgQAAxkBAAE4JY5fnM4p6SXDZ_jURwYSmFZiqMBYgwAChgADS2nuEArWtsRFiwWJGwQ"
}

function fail {
	END=$(date +"%s")
    DIFF=$(( END - START ))
    tgCast "Failed on <b>$@</b> !"
    tgFile "$LOG_FILE" "❌ Compilation failed after $((DIFF / 60)) minute(s) and $((DIFF / 60)) seconds !"
    tgSticker "CAACAgQAAxkBAAE4JXpfnM0UIi8P6lbu2WXu7ySXJrTE0AACbAEAAktp7hD3wiHK0fl1zxsE"
    exit 1
}

function makeKernel {
	START=$(date +"%s")
	tgCast "Building defconfig..."
	make \
	O=out \
	ARCH=arm64 \
	$DEFCONFIG

	tgCast "Building kernel image..."
	if [[ $COMPILER = clang ]]; then
		make \
		-j$(nproc --all) \
		O=out \
		ARCH=arm64 \
		CC=clang \
		CROSS_COMPILE=aarch64-linux-gnu- \
		CROSS_COMPILE_ARM32=arm-linux-gnueabi \
		AR=llvm-ar \
		NM=llvm-nm \
		STRIP=llvm-strip \
		OBJCOPY=llvm-objcopy \
		OBJDUMP=llvm-objdump \
		OBJSIZE=llvm-size \
		READELF=llvm-readelf \
		HOSTCC=clang \
		HOSTCXX=clang++ \
		HOSTAR=llvm-ar || fail "kernel image"
	else
		make \
		-j$(nproc --all) \
		ARCH=arm64 \
		CROSS_COMPILE="gcc/bin/aarch64-elf-" \
		CROSS_COMPILE_ARM32="gcc32/bin/aarm-eabi-" || fail "kernel image"
	fi
	pack
}

function pack {
	git clone https://github.com/naonana/AnyKernel3 $ANYKERNEL
    tgCast "Building ZIP..."
    cp $OUT/arch/arm64/boot/Image.gz-dtb $ANYKERNEL/Image.gz-dtb

    cd $ANYKERNEL
    zip -r9 $FILE_NAME ./* || fail "ZIP"

    cd $SRC_TOP

    ZIP="$ANYKERNEL/$FILE_NAME"
    success
}

export TZ=Asia/Jakarta
export KBUILD_BUILD_HOST=Dynazenon
export KBUILD_BUILD_USER=nao

setupEnv
makeKernel
