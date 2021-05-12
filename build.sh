#!/bin/bash
#
# Copyright © 2020-2021, Samar Vispute "SamarV-121" <samarvispute121@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0
#
# Append last dt commit hash to OTA package
append_dt_commit() {
	eval "$(grep "export DEVICE_COMMON" device/*/"$DEVICE"/extract-files.sh)"
	TARGET_UNOFFICIAL_BUILD_ID=$(
		if [ "$DEVICE_COMMON" ]; then
			cd device/*/"$DEVICE_COMMON" || exit
		else
			cd device/*/"$DEVICE" || exit
		fi
		git rev-parse --short HEAD
	)
	export TARGET_UNOFFICIAL_BUILD_ID
}

telegram() {
	case $1 in
	--sendmsg)
		[ "$SPAM_TELEGRAM" = Y ] && curl -s "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" -d "chat_id=$TELEGRAM_CHAT" -d "parse_mode=Markdown" -d "text=${*:2}" >/dev/null
		;;
	--sendsticker)
		[ "$SPAM_TELEGRAM" = Y ] && curl -s "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendSticker" -d "chat_id=$TELEGRAM_CHAT" -d "sticker=$2" >/dev/null
		;;
	esac
}

[ "$(whoami)" = jenkins ] && JENKINS=true && read() { :; } && echo() { :; }

if [ "$JENKINS" ]; then
	HOME=$(dirname "$WORKSPACE")
	PROGESS="${BUILD_URL}console"
else
	PROGESS=$(tmate show-m | awk 'NR==3 {print $NF}')
fi

source "$HOME/.TOKENs"
# TELEGRAM_CHAT="-1001473502998"

red="\033[01;31m"
nocol="\033[0m"
bold="\033[1m"
export LINEAGE_VERSION_APPEND_TIME_OF_DAY=true

echo -e "$bold"

# Configs
echo "Press Y to setup new config"
read -t10 -r CONF

if [ "$CONF" != Y ] && [ -e .config ]; then
	eval "$(cat .config)"
	[ "$*" ] && [ "$*" != upload-only ] && DEVICES="$*"
else
	[ ! -e .config ] && echo "No config file has been found, setup new"
	rm -f .config
	echo Press Y to include GAPPS in build
	read -t5 -r GAPPS
	echo "export GAPPS=$GAPPS" >>.config

	echo "Press Y to include SU"
	read -t5 -r SU
	echo "export SU=$SU" >>.config

	echo "Press Y to upload build"
	read -t5 -r UPLOAD
	echo "export UPLOAD=$UPLOAD" >>.config

	echo "Press Y to nuke outdir"
	read -t5 -r CLEAN
	echo "export CLEAN=$CLEAN" >>.config

	# https://github.com/SamarV-121/android_vendor_extra/blob/lineage-18.1/product.mk#L18
	echo "Press Y to enable DEBUGGING"
	read -t5 -r DEBUGGING
	echo "export DEBUGGING=$DEBUGGING" >>.config

	if [ "$CLEAN" != Y ]; then
		echo "Press N to not nuke images and staging dirs"
		read -t5 -r INSTALLCLEAN
		echo "export INSTALLCLEAN=$INSTALLCLEAN" >>.config
	fi

	echo "Press Y to Spam Telegram"
	read -t5 -r SPAM_TELEGRAM
	echo "export SPAM_TELEGRAM=Y" >>.config

	echo "Press N to disable CCACHE"
	read -t5 -r CCACHE
	echo "export CCACHE=$CCACHE" >>.config

	echo "Press C to clear CCACHE"
	read -t5 -r CCACHE_
	echo "export CCACHE_=$CCACHE_" >>.config

	echo "Type lunch command (default: lineage)"
	read -t10 -r ROM_VENDOR
	echo "export ROM_VENDOR=$ROM_VENDOR" >>.config

	echo "Type build type (default: userdebug)"
	read -t10 -r BUILD_TYPE
	echo "export BUILD_TYPE=$BUILD_TYPE" >>.config

	echo "Type target command (default: bacon)"
	read -t10 -r TARGET_CMD
	echo "export TARGET_CMD=$TARGET_CMD" >>.config

	echo "Enter device name(s)"
	read -r DEVICES
	echo "export DEVICES=$DEVICES" >>.config
fi

echo -e "$nocol"

[ "$GAPPS" = Y ] && export WITH_GAPPS=true
[ "$SU" = Y ] && export WITH_SU=true
[ "$CLEAN" = Y ] && rm -rf out
[ "$DEBUGGING" = Y ] && export WITH_DEBUGGING=true
if [ "$CCACHE" != N ]; then
	export USE_CCACHE=1
	export CCACHE_EXEC=/usr/bin/ccache
	ccache -M 50G >/dev/null
	ccache -o compression=true
fi
[ "$CCACHE_" = C ] && ccache -C
[ -z "$ROM_VENDOR" ] && ROM_VENDOR=lineage
[ -z "$BUILD_TYPE" ] && BUILD_TYPE=userdebug
[ -z "$TARGET_CMD" ] && TARGET_CMD=bacon

source build/envsetup.sh

unset -f echo

BUILD_START=$(date +"%s")

COUNT_DEVICES=$(echo "$DEVICES" | wc -w)
while [ "$COUNT_DEVICES" -gt 0 ]; do
	DEVICE=$(tac -s' ' <<<"$DEVICES" | xargs | cut -d " " -f"$COUNT_DEVICES")
	lunch "${ROM_VENDOR}"_"$DEVICE"-"$BUILD_TYPE"
	OUTDIR="$OUT"
	append_dt_commit
	telegram --sendmsg "Build started for $DEVICE: [See Progress]($PROGESS)
ROM VENDOR: $ROM_VENDOR
BUILD TYPE: $BUILD_TYPE" >/dev/null
	if [[ $* =~ upload-only ]]; then
		UPLOAD=Y
	else
		rm -f "$OUT/*zip*" out/.lock
		[ "$INSTALLCLEAN" != N ] && m installclean
		make -j "$(nproc --all)" "$TARGET_CMD" 2>&1 | tee build_"$DEVICE".log
	fi
	BUILD_END=$(date +"%s")
	BUILD_DIFF=$((BUILD_END - BUILD_START))
	OTA_PATH=$(find "$OUTDIR"/*2021*.zip)
	if [ -e "$OTA_PATH" ]; then
		OTA_NAME=${OTA_PATH/$OUTDIR\//}
		OTA_SIZE=$(du -h "$OTA_PATH" | head -n1 | awk '{print $1}')
		OTA_SHA256=$(sha256sum "$OTA_PATH" | awk '{print $1}')
		GH_RELEASE=SamarV-121/releases && TAG=$(date -u +%Y%m%d_%H%M%S)
		if [ "$UPLOAD" = Y ]; then
			echo Uploading "$OTA_NAME"...
			LINK=$(github-release.sh "$GH_RELEASE" "$TAG" "master" "Date: $(date)" "$OTA_PATH" | tail -n1 | awk '{print $3}')
			echo "Download links:
GitHub: $LINK
Sha256sum: $OTA_SHA256"
			telegram --sendmsg "Build completed successfully in $((BUILD_DIFF / 3600)) hour and $((BUILD_DIFF / 60)) minute(s)
Filename: [${OTA_NAME}](https://github.com/$GH_RELEASE/releases/download/$TAG/$OTA_NAME)
Size: \`$OTA_SIZE\`
Sha256sum: \`$OTA_SHA256\`
Download: [Github]($LINK)"
			telegram --sendsticker "CAADBQAD8gADLG6EE1T3chaNrvilFgQ"
		else
			# Flash
			if ! [ "$JENKINS" ] || [ "$COUNT_DEVICES" -gt 1 ]; then
				eat
			fi
		fi
	else
		echo -e "${red}#### build failed in $((BUILD_DIFF / 60)) minute(s) ####${nocol}"
		telegram --sendmsg "Build failed in $((BUILD_DIFF / 60)) minute(s)"
		telegram --sendsticker "CAADBQAD8gADLG6EE1T3chaNrvilFgQ"
		exit 1
	fi
	COUNT_DEVICES=$((COUNT_DEVICES - 1))
done
