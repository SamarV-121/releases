#!/bin/bash
#
# Copyright © 2020-2021, Samar Vispute "SamarV-121" <samarvispute121@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0
#
function telegram {
	if [ "$SPAM_TELEGRAM" = Y ]; then
		API=$(curl -s "https://api.telegram.org/bot$TELEGRAM_TOKEN/$1" -d "chat_id=$TELEGRAM_CHAT" -d "message_id=$MESSAGE_ID" -d parse_mode=Markdown -d "sticker=$2" -d "text=$2")
		MESSAGE_ID_TMP=$(echo "$API" | jq '.result.message_id')
		[[ $MESSAGE_ID_TMP =~ ^[0-9]+$ ]] && MESSAGE_ID=$MESSAGE_ID_TMP
	fi
}

function append_dt_commit {
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

[ "$JENKINS_URL" ] && JENKINS=true

if [ "$JENKINS" ]; then
	PROGESS="[Jenkins](${BUILD_URL}console)"
else
	PROGESS="[Tmate]($(tmate show-m | awk 'NR==3 {print $NF}'))"
fi

HOME=/home/samar121
source "$HOME/.TOKENs"
TELEGRAM_CHAT="-1001473502998"

grn="\033[01;32m"
nocol="\033[0m"
bold="\033[1m"
export LINEAGE_VERSION_APPEND_TIME_OF_DAY=true
export CCACHE_EXEC=$(which ccache)
export CCACHE_DIR="$HOME/.ccache"
ccache -M 50G >/dev/null
ccache -o compression=true

if [ -z $JENKINS ]; then
	echo -e "$bold"

	echo "Press Y to setup new config"
	read -t10 -r CONF

	if [ "$CONF" != Y ] && [ -e .config ]; then
		eval "$(cat .config)"
	else
		[ ! -e .config ] && echo "No config file has been found, setup new"

		echo "Enter ROM name"
		read -t5 -r ROM
		echo "export ROM=$ROM" >>.config

		echo "Press Y to include GAPPS in build"
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

		echo "Press Y to enable DEBUGGING"
		read -t5 -r DEBUGGING
		echo "export DEBUGGING=$DEBUGGING" >>.config

		echo "Press Y to Spam Telegram"
		read -t5 -r SPAM_TELEGRAM
		echo "export SPAM_TELEGRAM=$SPAM_TELEGRAM" >>.config

		echo "Press Y to Generate incremental OTA package"
		read -t5 -r INCREMENTAL_OTA
		echo "export INCREMENTAL_OTA=$INCREMENTAL_OTA" >>.config

		if [ "$CLEAN" != Y ]; then
			echo "Press N to not nuke images and staging dirs"
			read -t5 -r INSTALLCLEAN
			echo "export INSTALLCLEAN=$INSTALLCLEAN" >>.config
		fi

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
		read -t10 -r TARGET_COMMAND
		echo "export TARGET_COMMAND=$TARGET_COMMAND" >>.config

		echo "Enter device name(s)"
		read -r DEVICES
		echo "export DEVICES=($DEVICES)" >>.config
	fi

	echo -e "$nocol"
fi

[ "$GAPPS" = Y ] && export WITH_GMS=true
[ "$SU" = Y ] && export WITH_SU=true
[ "$CLEAN" = Y ] && rm -rf out
[ "$DEBUGGING" = Y ] && export WITH_DEBUGGING=true
[ "$CCACHE" != N ] && export USE_CCACHE=1
[ "$CCACHE_" = C ] && ccache -C
[ -z "$ROM_VENDOR" ] && ROM_VENDOR=lineage
[ -z "$BUILD_TYPE" ] && BUILD_TYPE=userdebug
[ -z "$TARGET_COMMAND" ] && TARGET_COMMAND=bacon

source build/envsetup.sh

BUILD_START=$(date +"%s")

function build_progress {
	BUILD_PROGRESS=$(sed -n '/ ninja/,$p' build_"$DEVICE".log | grep -Po '\d+% \d+/\d+' | tail -n1 | sed -e 's/ / \(/' -e 's/$/)/')

	[ "$BUILD_PROGRESS" ] &&
		telegram editMessageText "$ROM
Build started for $DEVICE: $PROGESS
Build type: $BUILD_TYPE
Status: $BUILD_PROGRESS"
}

for DEVICE in "${DEVICES[@]}"; do
	lunch "${ROM_VENDOR}"_"$DEVICE"-"$BUILD_TYPE"
	OUTDIR="$OUT"
	append_dt_commit
	telegram sendMessage "$ROM
Build started for $DEVICE: $PROGESS
Build type: $BUILD_TYPE"

	rm -f "$OUT"/*zip* out/.lock
	[ "$INSTALLCLEAN" != N ] && m installclean
	make "-j$(nproc --all)" "$TARGET_COMMAND" 2>&1 | tee build_"$DEVICE".log &
	while [ -n "$(jobs -r)" ]; do
		build_progress
		sleep 2m
	done

	build_progress

	BUILD_END=$(date +"%s")
	BUILD_DIFF=$((BUILD_END - BUILD_START))
	BUILD_TIME="$((BUILD_DIFF / 3600)) hour and $(($((BUILD_DIFF / 60)) % 60)) minute(s)"

	OTA_PATH=$(find "$OUTDIR"/*2021*.zip)

	if [ -e "$OTA_PATH" ]; then
		OTA_NAME=${OTA_PATH/$OUTDIR\//}
		GH_RELEASE=SamarV-121/mirror && TAG=$(date -u +%Y%m%d_%H%M%S)
		sha256sum "$OTA_PATH" | awk '{print $1}' >"${OTA_PATH}.sha256sum"

		if [ "$INCREMENTAL_OTA" = Y ]; then
			OLD_TARGET_FILES_PATH=$(find ./*"$DEVICE"*target_files*.zip)
			NEW_TARGET_FILES_PATH=$(find "$OUTDIR"/obj/PACKAGING/target_files_intermediates/*target_files*.zip)

			OLD_BUILD_DATE=$(unzip -p "$OLD_TARGET_FILES_PATH" SYSTEM/build.prop | grep -Pom1 '\d+_\d+')
			NEW_BUILD_DATE=$(grep -Po '\d+_\d+' <<<"$OTA_NAME")

			INCREMENTAL_OTA_NAME=$(sed "s $NEW_BUILD_DATE $OLD_BUILD_DATE-update-$NEW_BUILD_DATE " <<<"$OTA_NAME")
			INCREMENTAL_OTA_PATH="$OUTDIR/$INCREMENTAL_OTA_NAME"

			echo -e "${grn}Generating incremental OTA package...${nocol}"
			ota_from_target_files -i "$OLD_TARGET_FILES_PATH" "$NEW_TARGET_FILES_PATH" "$INCREMENTAL_OTA_PATH"
			sha256sum "$INCREMENTAL_OTA_PATH" | awk '{print $1}' >"${INCREMENTAL_OTA_PATH}.sha256sum"
			cp "$NEW_TARGET_FILES_PATH" .
			echo -e "Package Complete: $(grep -o 'out.*' <<<"$INCREMENTAL_OTA_PATH")\n\n"
		fi

		if [ "$UPLOAD" = Y ]; then
			FILES=("$OTA_PATH" "${OTA_PATH}.sha256sum")
			[ "$INCREMENTAL_OTA_PATH" ] &&
				FILES+=("$INCREMENTAL_OTA_PATH" "${INCREMENTAL_OTA_PATH}.sha256sum")

			for FILE in "${FILES[@]}"; do
				github-release "$GH_RELEASE" "$TAG" "master" "Date: $(date)" "$FILE"
			done

			telegram sendMessage "Build completed successfully in $BUILD_TIME
Download: [Github](https://github.com/$GH_RELEASE/releases/tag/$TAG)"
			telegram sendSticker "CAADBQAD8gADLG6EE1T3chaNrvilFgQ"
		else
			# Flash
			if ! [ "$JENKINS" ] || [ "$(wc -w <<<"$DEVICES")" -gt 1 ]; then
				eat
			fi
		fi
	else
		telegram sendMessage "Build failed in $BUILD_TIME"
		telegram sendSticker "CAADBQAD8gADLG6EE1T3chaNrvilFgQ"
		exit 1
	fi
done
