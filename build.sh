#!/bin/bash
#
# Copyright © 2020-2021, Samar Vispute "SamarV-121" <samarvispute121@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0

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

echo -e "$BOLD"Press Y to setup new config
read -t10 -r CONF

if [[ $CONF != Y && -e .config ]]; then
	eval "$(cat .config)"
else
	[[ ! -e .config ]] && echo -e "$BOLD"No config file has been found, setup new
	rm -f .config
	echo -e "$BOLD"Press Y to include GAPPS in build
	read -t5 -r GAPPS
	echo "export GAPPS=$GAPPS" >>.config

	echo -e "$BOLD"Press Y to upload build
	read -t5 -r UPLOAD
	echo "export UPLOAD=$UPLOAD" >>.config

	echo -e "$BOLD"Press Y to nuke outdir
	read -t5 -r CLEAN
	echo "export CLEAN=$CLEAN" >>.config

	# https://github.com/SamarV-121/android_vendor_extra/blob/lineage-18.1/product.mk#7
	echo -e "$BOLD"Press Y to enable DEBUGGING
	read -t5 -r DEBUGGING
	echo "export DEBUGGING=$DEBUGGING" >>.config

	if [[ $CLEAN != Y ]]; then
		echo -e "$BOLD"Press N to not nuke images and staging dirs
		read -t5 -r INSTALLCLEAN
		echo "export INSTALLCLEAN=$INSTALLCLEAN" >>.config
	fi

	echo -e "$BOLD"Press N to disable CCACHE
	read -t5 -r CCACHE
	echo "export CCACHE=$CCACHE" >>.config

	echo -e "$BOLD"Press C to clear CCACHE
	read -t5 -r CCACHE_
	echo "export CCACHE_=$CCACHE_" >>.config

	echo -e """$BOLD""Type lunch command (default: lineage)"
	read -t10 -r ROM_VENDOR
	echo "export ROM_VENDOR=$ROM_VENDOR" >>.config

	echo -e """$BOLD""Type build type (default: userdebug)"
	read -t10 -r BUILD_TYPE
	echo "export BUILD_TYPE=$BUILD_TYPE" >>.config

	echo -e """$BOLD""Type target command (default: bacon)"
	read -t10 -r TARGET_CMD
	echo "export TARGET_CMD=$TARGET_CMD" >>.config

	# DEVICE CODENAME(S)
	if [[ "$*" ]]; then
		DEVICES="$*"
	else
		echo -e """$BOLD""Enter device name(s)"
		read -r DEVICES
	fi
	echo "export DEVICES=$DEVICES" >>.config
fi

[[ $GAPPS == Y ]] && export WITH_GAPPS=true
[[ $CLEAN == Y ]] && rm -rf out
[[ $DEBUGGING == Y ]] && export WITH_DEBUGGING=true
if [[ $CCACHE != N ]]; then
	export USE_CCACHE=1
	export CCACHE_EXEC=/usr/bin/ccache
	ccache -M 50G >/dev/null
	ccache -o compression=true
fi
[[ $CCACHE_ == C ]] && ccache -C
[[ -z $ROM_VENDOR ]] && ROM_VENDOR=lineage
[[ -z $BUILD_TYPE ]] && BUILD_TYPE=userdebug
[[ -z $TARGET_CMD ]] && TARGET_CMD=bacon

source build/envsetup.sh

unset -f echo

BUILD_START=$(date +"%s")

COUNT_DEVICES=$(echo "$DEVICES" | wc -w)
while [ "$COUNT_DEVICES" -gt 0 ]; do
	DEVICE=$(tac -s' ' <<<"$DEVICES" | xargs | cut -d " " -f"$COUNT_DEVICES")
	lunch "${ROM_VENDOR}"_"$DEVICE"-"$BUILD_TYPE"
	OUTDIR="$OUT"
	append_dt_commit
	[[ $SPAM_TELEGRAM == Y ]] && curl -s "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" -d "chat_id=$TELEGRAM_CHAT" -d "parse_mode=Markdown" -d "text=Build started for $DEVICE: [See Progress](${BUILD_URL}console)
ROM\_VENDOR: $ROM_VENDOR
BUILD\_TYPE: $BUILD_TYPE" >/dev/null
	if [[ $* =~ upload-only ]]; then
		UPLOAD=Y
	else
		rm -f "$OUT"/*zip* out/.lock
		[[ $INSTALLCLEAN != N ]] && m installclean
		make "$TARGET_CMD" -j"$(nproc --all)" 2>&1 | tee build_"$DEVICE".log
	fi
	BUILD_END=$(date +"%s")
	BUILD_DIFF=$((BUILD_END - BUILD_START))
	OTA_PATH=$(find "$OUTDIR"/*2021*.zip)
	if [[ -e $OTA_PATH ]]; then
		OTA_NAME=$(sed "s#$OUTDIR/##" <<<"$OTA_PATH")
		OTA_SIZE=$(du -h "$OTA_PATH" | head -n1 | awk '{print $1}')
		OTA_MD5=$(awk <"$OTA_PATH".md5sum '{print $1}')
		GH_RELEASE=SamarV-121/releases && TAG=$(date -u +%Y%m%d_%H%M%S)
		if [[ $UPLOAD == Y ]]; then
			echo Uploading "$OTA_NAME"...
			github-release "$GH_RELEASE" "$TAG" "master" "Date: $(env TZ="$timezone" date)" "$OTA_PATH" 2>/dev/null
			echo "Download links:
GitHub: https://github.com/$GH_RELEASE/releases/download/$TAG/$OTA_NAME
Md5sum: $OTA_MD5"
			[[ $SPAM_TELEGRAM == Y ]] && curl -s "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" -d "chat_id=$TELEGRAM_CHAT" -d "parse_mode=Markdown" -d "text=Build completed successfully in $((BUILD_DIFF / 3600)) hour and $((BUILD_DIFF / 60)) minute(s)
Filename: [${OTA_NAME}](https://github.com/$GH_RELEASE/releases/download/$TAG/$OTA_NAME)
Size: \`$OTA_SIZE\`
Md5sum: \`$OTA_MD5\`
Download: [Github](https://github.com/$GH_RELEASE/releases/download/$TAG/$OTA_NAME))" >/dev/null
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
