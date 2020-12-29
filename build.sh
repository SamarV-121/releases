#!/bin/bash
#
# Copyright © 2020, Samar Vispute "SamarV-121" <samarvispute121@gmail.com>
#
# Custom build script
#
# This software is licensed under the terms of the GNU General Public
# License version 2, as published by the Free Software Foundation, and
# may be copied, distributed, and modified under those terms.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#

gofile() {
	if [[ $* ]]; then
		SRV=$(curl -s -m 15 https://apiv2.gofile.io/getServer | cut -d'"' -f10)
		LNK=$(curl -F file=@"$1" https://"$SRV".gofile.io/uploadFile | cut -d'"' -f10)
		echo https://gofile.io/d/"$LNK"
	fi
}

# Append last dt commit hash to OTA package
append_dt_commit() {
	eval "$(grep "export DEVICE_COMMON" device/*/"$DEVICE"/extract-files.sh)"
	TARGET_UNOFFICIAL_BUILD_ID=$(
		if [[ $DEVICE_COMMON ]]; then
			cd device/*/"$DEVICE_COMMON" || exit
		else
			cd device/*/"$DEVICE" || exit
		fi
		git rev-parse --short HEAD
	)
	export TARGET_UNOFFICIAL_BUILD_ID
}

[[ $(whoami) == jenkins ]] && JENKINS=true && read() { :; } && echo() { :; }

[[ $JENKINS ]] && HOME=$(dirname "$WORKSPACE")
source "$HOME"/.TOKENs

BOLD="\033[1m"
export KBUILD_BUILD_HOST=ThePASIV
export KBUILD_BUILD_USER=SamarV-121
export LINEAGE_VERSION_APPEND_TIME_OF_DAY=true

# GAPPS
echo -e "$BOLD"Press Y to include GAPPS in build.
read -t5 -r GAPPS
[[ $GAPPS == Y ]] && export WITH_GAPPS=true

# UPLOAD
echo -e """$BOLD""Type Y to upload build (default: No)"
read -t5 -r UPLOAD

# NUKE OUT
echo -e "$BOLD"Press Y to nuke outdir
read -t5 -r CLEAN
[[ $CLEAN == Y ]] && rm -rf out

# Nuke images and staging dirs
[[ $CLEAN != Y ]] && echo -e "$BOLD"Press N to not nuke images and staging dirs; read -t5 -r INSTALLCLEAN

# DEBUGGING (https://github.com/SamarV-121/android_vendor_extra/blob/lineage-18.0/product.mk#7)
echo -e "$BOLD"Press N to disable DEBUGGING
read -t5 -r DEBUGGING
[[ $DEBUGGING != N ]] && export WITH_DEBUGGING=true

# CCACHE
echo -e "$BOLD"Press N to disable CCACHE
read -t5 -r CCACHE
if [[ $CCACHE != N ]]; then
	export USE_CCACHE=1
	export CCACHE_EXEC=/usr/bin/ccache
	ccache -M 50G >/dev/null
	ccache -o compression=true
fi
echo -e "$BOLD"Press C to clear CCACHE
read -t5 -r CCACHE
[[ $CCACHE == C ]] && ccache -C

# ROM VENDOR
echo -e """$BOLD""Type lunch command (default: lineage)"
read -t10 -r ROM_VENDOR
[[ -z $ROM_VENDOR ]] && ROM_VENDOR=lineage

# BUILD TYPE
echo -e """$BOLD""Choose build type (default: userdebug)"
read -t10 -r BUILD_TYPE
[[ -z $BUILD_TYPE ]] && BUILD_TYPE=userdebug

# TARGET COMMAND
echo -e """$BOLD""Type target command (default: bacon)"
read -t10 -r TARGET_CMD
[[ -z $TARGET_CMD ]] && TARGET_CMD=bacon

source build/envsetup.sh

# DEVICE CODENAME(S)
if [[ "$*" ]]; then
	DEVICES="$*"
else
	echo -e """$BOLD""Enter device name(s)"
	read -r DEVICES
fi

unset -f echo

BUILD_START=$(date +"%s")

COUNT_DEVICES=$(echo "$DEVICES" | wc -w)
while [ "$COUNT_DEVICES" -gt 0 ]; do
	DEVICE=$(tac -s' ' <<<"$DEVICES" | xargs | cut -d " " -f"$COUNT_DEVICES")
	lunch "${ROM_VENDOR}"_"$DEVICE"-"${BUILD_TYPE}"
	OUTDIR="$OUT"
	append_dt_commit
	[[ $SPAM_TELEGRAM == Y ]] && curl -s "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" -d "chat_id=$TELEGRAM_CHAT" -d "parse_mode=Markdown" -d "text=Build started for $DEVICE: [See Progress](${BUILD_URL}console)
ROM\_VENDOR: $ROM_VENDOR
BUILD\_TYPE: $BUILD_TYPE" >/dev/null
	rm "$OUT"/*zip* out/.lock
	[[ $INSTALLCLEAN != N ]] && m installclean
	m "$TARGET_CMD" -j"$(nproc --all)" 2>&1 | tee build_"$DEVICE".log
	BUILD_END=$(date +"%s")
	BUILD_DIFF=$((BUILD_END - BUILD_START))
	OTA_PATH=$(find "$OUTDIR"/*2020*.zip)
	if [[ -e $OTA_PATH ]]; then
		OTA_NAME=$(sed "s#$OUTDIR/##" <<<"$OTA_PATH")
		OTA_SIZE=$(du -h "$OTA_PATH" | head -n1 | awk '{print $1}')
		OTA_MD5=$(awk <"$OTA_PATH".md5sum '{print $1}')
		GH_RELEASE=SamarV-121/releases && TAG=$(date -u +%Y%m%d_%H%M%S)
		if [[ $UPLOAD == Y ]]; then
			echo Uploading "$OTA_NAME"...
			github-release "$GH_RELEASE" "$TAG" "master" "Date: $(env TZ="$timezone" date)" "$OTA_PATH" 2>/dev/null
			gofile "$OTA_PATH" 2>/dev/null >gofile
			echo "Download links:
GitHub: https://github.com/$GH_RELEASE/releases/download/$TAG/$OTA_NAME
GoFile: $(<gofile)
Md5sum: $OTA_MD5"
			[[ $SPAM_TELEGRAM == Y ]] && curl -s "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" -d "chat_id=$TELEGRAM_CHAT" -d "parse_mode=Markdown" -d "text=Build completed successfully in $((BUILD_DIFF / 3600)) hour and $((BUILD_DIFF / 60)) minute(s)
Filename: [${OTA_NAME}](https://github.com/$GH_RELEASE/releases/download/$TAG/$OTA_NAME)
Size: \`$OTA_SIZE\`
Md5sum: \`$OTA_MD5\`
Download: [Github](https://github.com/$GH_RELEASE/releases/download/$TAG/$OTA_NAME) | [GoFile]($(cat gofile))" >/dev/null
			[[ $SPAM_TELEGRAM == Y ]] && curl -s "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendSticker" -d "chat_id=$TELEGRAM_CHAT" -d "sticker=CAADBQAD8gADLG6EE1T3chaNrvilFgQ" >/dev/null
		else
			# Flash
			if ! [[ $JENKINS ]] || [[ $COUNT_DEVICES -gt 1 ]]; then
				echo -e "$BOLD"Press F to flash the build
				read -r FLASH
				[[ $FLASH == F ]] && eat
			fi
		fi
	else
		echo -e """$BOLD""Build failed in $((BUILD_DIFF / 60)) minute(s)"
		[[ $SPAM_TELEGRAM == Y ]] && curl -s "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" -d "chat_id=$TELEGRAM_CHAT" -d "parse_mode=Markdown" -d "text=Build failed in $((BUILD_DIFF / 60)) minute(s)" >/dev/null
		[[ $SPAM_TELEGRAM == Y ]] && curl -s "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendSticker" -d "chat_id=$TELEGRAM_CHAT" -d "sticker=CAADBQAD8gADLG6EE1T3chaNrvilFgQ" >/dev/null
		exit 1
	fi
	COUNT_DEVICES=$((COUNT_DEVICES - 1))
done
