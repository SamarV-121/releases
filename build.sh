#!/bin/bash
source ../.TOKENS
USER=SamarV-121
export KBUILD_BUILD_USER=SamarV-121
export KBUILD_BUILD_HOST=localhost
export LINEAGE_VERSION_APPEND_TIME_OF_DAY=true
USE_CCACHE=1
ccache -M 50G
outdir=out/target/product/$device_codename
BUILD_START=$(date +"%s")
if [ $tg_spam = y ]; then
curl -s https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage -d parse_mode=Markdown -d text="$ROM Build $BUILD_DISPLAY_NAME started for $device_codename: [See Progress](${BUILD_URL}console)" -d chat_id=$TELEGRAM_CHAT > /dev/null
fi

if [ $make_clean = y ]; then
rm -rf out
wait
echo OUT dir from your repo deleted
fi

if [ $make_clean = installclean ]; then
make installclean
wait
echo Images deleted from OUT dir
fi

rm -f $outdir/*zip*
rm -f out/.lock
source build/envsetup.sh
lunch "$lunch_command"_$device_codename-$build_type
make $target_command -j$jobs 2>&1 | tee build.log

BUILD_END=$(date +"%s")
BUILD_DIFF=$((BUILD_END - BUILD_START))

if [ $upload = y ]; then
release_repo=SamarV-121/releases
if [ $lunch_command = lineage ]; then
mv $(ls $outdir/*2020*.zip) $(ls $outdir/*2020*.zip | sed 's|_|-|g')
fi
finalzip_path=$(ls $outdir/*2020*.zip)
zip__size=$(ls -sh $outdir/*2020*.zip)
zip_size=$(echo $zip__size | sed "s|$finalzip_path||")
zip_name=$(echo $finalzip_path | sed "s|$outdir/||")
tag=$( echo "$zip_name-$(date +%H%M)" | sed 's|.zip||')
if [ -e $finalzip_path ]; then
gdrive upload -p 1H1BaCSoUJ2S28LL4mH4RZ9ua364MRhVT $finalzip_path
github-release "$release_repo" "$tag" "exp" "Date: $(env TZ="$timezone" date)" "$finalzip_path"
if [ $tg_spam = y ]; then
curl -s https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage -d parse_mode=Markdown -d text="Build completed successfully in $((BUILD_DIFF / 3600)) hour and $((BUILD_DIFF / 60)) minute(s)
Filename: $zip_name
Size: $zip_size
Download: [Github](https://github.com/$release_repo/releases/download/$tag/$zip_name) | [GoogleDrive](https://samarv121.priv.workers.dev/$device_codename/$zip_name) | [Jenkins](${BUILD_URL}artifact/$outdir/$zip_name)" -d chat_id=$TELEGRAM_CHAT
fi
curl --data parse_mode=HTML --data chat_id=$TELEGRAM_CHAT --data sticker=CAADBQAD8gADLG6EE1T3chaNrvilFgQ --request POST https://api.telegram.org/bot$TELEGRAM_TOKEN/sendSticker > /dev/null
else
echo "Build failed in $((BUILD_DIFF / 3600)) hour and $((BUILD_DIFF / 60)) minute(s)"
if [ $tg_spam = y ]; then
curl -s https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage -d text="Build failed in $((BUILD_DIFF / 60)) minute(s)" -d chat_id=$TELEGRAM_CHAT
curl --data parse_mode=HTML --data chat_id=$TELEGRAM_CHAT --data sticker=CAADBQAD8gADLG6EE1T3chaNrvilFgQ --request POST https://api.telegram.org/bot$TELEGRAM_TOKEN/sendSticker > /dev/null
fi
exit 1
fi
fi
