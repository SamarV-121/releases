#!/bin/bash
#
# Copyright © 2021, Samar Vispute "SamarV-121" <samarvispute121@gmail.com>
#
# SPDX-License-Identifier: Apache-2.0
# --
# export GITHUB_TOKEN=token
# github-release.sh repo tag branch "description" filename
# eg.
# export GITHUB_TOKEN=2345htrvdcse234rbfbgn345
# github-release.sh SamarV-121/releases 1.0.2 master "Test release" test.zip
#

if [ "$5" ]; then
	REPO="$1"
	TAG="$2"
	BRANCH="$3"
	DESC="$4"
	FILE="$5"

	GITHUB_REPO="https://api.github.com/repos/$REPO"
	AUTH="Authorization: token $GITHUB_TOKEN"

	# Create new release
	ID=$(curl -X POST "$GITHUB_REPO/releases" -H "$AUTH" -d "{\"tag_name\": \"$TAG\", \"target_commitish\": \"$BRANCH\", \"name\": \"$TAG\", \"body\": \"$DESC\"}" | jq '.id')

	# Upload file
	GITHUB_ASSET="https://uploads.github.com/repos/$REPO/releases/$ID/assets?name=$(basename "$FILE")"
	echo "Uploading $FILE... "
	LOG=$(curl --data-binary @"$FILE" -H "$AUTH" -H "Content-Type: application/octet-stream" "$GITHUB_ASSET")
	DLOAD_URL=$(echo "$LOG" | jq '.browser_download_url')
	DLOAD_URL="${DLOAD_URL//\"/}"
	if [ "$DLOAD_URL" = null ]; then
		echo -e "Failed to upload\n$(<"$LOG")"
	else
		echo -e "Succesfully uploaded\nDownload URL: $DLOAD_URL"
	fi
else
	sed -n '/^$/q;/# --/,$ s/^#*//p' "$0"
fi
