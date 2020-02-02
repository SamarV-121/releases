#!/bin/bash
cd /home/samar/"$rom"
username=samar
export outdir="out/target/product/$device_codename"
BUILD_START=$(date +"%s")
telegram -M "Build ${BUILD_DISPLAY_NAME} started for $device_codename: [See Progress](${BUILD_URL}console)"

# temp turn off path tool checks
# export TEMPORARY_DISABLE_PATH_RESTRICTIONS=true

# Colors makes things beautiful
export TERM=xterm
    red=$(tput setaf 1)             #  red
    grn=$(tput setaf 2)             #  green
    blu=$(tput setaf 4)             #  blue
    cya=$(tput setaf 6)             #  cyan
    txtrst=$(tput sgr0)             #  Reset

# CCACHE UMMM!!! Cooks my builds fast
if [ "$use_ccache" = "yes" ];
then
echo -e ${blu}"CCACHE is enabled for this build"${txtrst}
export CCACHE_EXEC=$(which ccache)
export USE_CCACHE=1
export CCACHE_DIR=/home/ccache/$username
ccache -M 50G
fi

if [ "$use_ccache" = "clean" ];
then
export CCACHE_EXEC=$(which ccache)
export CCACHE_DIR=/home/ccache/$username
ccache -C
export USE_CCACHE=1
ccache -M 50G
wait
echo -e ${grn}"CCACHE Cleared"${txtrst};
fi

# Its Clean Time
if [ "$make_clean" = "yes" ];
then
make clean && make clobber
wait
echo -e ${cya}"OUT dir from your repo deleted"${txtrst};
fi

# Its Images Clean Time
if [ "$make_clean" = "installclean" ];
then
make installclean
wait
echo -e ${cya}"Images deleted from OUT dir"${txtrst};
fi

# Nuke existing rom zip
rm -f "${outdir}"/*2020*.zip

# Build ROM
source build/envsetup.sh
lunch "$lunch_command"_"$device_codename"-"$build_type"
make "$target_command" -j"$jobs"

BUILD_END=$(date +"%s")
BUILD_DIFF=$((BUILD_END - BUILD_START))

# Upload
if [ "$upload" = "why not" ];
then
export release_repo=SamarV-121/releases
export finalzip_path=$(ls "${outdir}"/*2020*.zip | tail -n -1)
export zip__size=$(ls -sh "${outdir}"/*2020*.zip | tail -n -1)
export zip_size=$(echo "${zip__size}" | sed "s|${finalzip_path}||")
export zip_name=$(echo "${finalzip_path}" | sed "s|${outdir}/||")
export tag=$( echo "${zip_name}-$(date +%H%M)" | sed 's|.zip||')
if [ -e "${finalzip_path}" ]; then
    github-release "${release_repo}" "${tag}" "exp" "${ROM} for $device_codename
Date: $(env TZ="${timezone}" date)" "${finalzip_path}"

    telegram -M "Build completed successfully in $((BUILD_DIFF / 3600)) hour and $((BUILD_DIFF / 60)) minute(s)
Filename: **${zip_name}**
Size: ${zip_size}
Download: [Mirror-1]("https://github.com/${release_repo}/releases/download/${tag}/${zip_name}") | [Mirror-2](${BUILD_URL}artifact/${outdir}/${zip_name})"

    curl --data parse_mode=HTML --data chat_id=$TELEGRAM_CHAT --data sticker=CAADBQAD8gADLG6EE1T3chaNrvilFgQ --request POST https://api.telegram.org/bot$TELEGRAM_TOKEN/sendSticker > /dev/null 2>&1
else
    echo "Build failed in $((BUILD_DIFF / 3600)) hour and $((BUILD_DIFF / 60)) minute(s)"

    telegram -N -M "Build failed in $((BUILD_DIFF / 60)) minute(s)"
    curl --data parse_mode=HTML --data chat_id=$TELEGRAM_CHAT --data sticker=CAADBQAD8gADLG6EE1T3chaNrvilFgQ --request POST https://api.telegram.org/bot$TELEGRAM_TOKEN/sendSticker > /dev/null 2>&1
    exit 1
fi
fi
