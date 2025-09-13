#!/bin/bash

# Check if bundle id is provided
if [ -z "$1" ]
then
    echo "No bundle id provided. Usage: ./patch_perseus.sh bundle.id.com.xy"
    exit 1
fi

# Set bundle id
bundle_id=$1

# Download apkeep
get_artifact_download_url () {
    # Usage: get_download_url <repo_name> <artifact_name> <file_type>
    local api_url="https://api.github.com/repos/$1/releases/latest"
    local result=$(curl $api_url | jq ".assets[] | select(.name | contains(\"$2\") and contains(\"$3\") and (contains(\".sig\") | not)) | .browser_download_url")
    echo ${result:1:-1}
}

# Artifacts associative array aka dictionary
declare -A artifacts

artifacts["apkeep"]="EFForg/apkeep apkeep-x86_64-unknown-linux-gnu"
artifacts["apktool.jar"]="iBotPeaches/Apktool apktool .jar"

# Fetch all the dependencies
for artifact in "${!artifacts[@]}"; do
    if [ ! -f $artifact ]; then
        echo "Downloading $artifact"
        curl -L -o $artifact $(get_artifact_download_url ${artifacts[$artifact]})
    fi
done

chmod +x apkeep

# Download Azur Lane
download_azurlane () {
    if [ ! -f "${bundle_id}.xapk" ]; then
    ./apkeep -a ${bundle_id} .
    fi
}

if [ ! -f "${bundle_id}.apk" ]; then
    echo "Get Azur Lane apk"
    download_azurlane
    unzip -o ${bundle_id}.xapk ${bundle_id}.apk -d AzurLane
    unzip -o ${bundle_id}.xapk manifest.json -d AzurLane
    cp AzurLane/${bundle_id}.apk .
fi

echo "Decompile Azur Lane apk"
# apktool expects the command (d|b) before options. Some apktool builds do not support -q.
# Use the documented syntax: "d -f <apk>" to force overwrite if needed.
java -jar apktool.jar d -f ${bundle_id}.apk

echo "Copy Perseus libs"
# Ensure target lib directory exists before copying
mkdir -p ${bundle_id}/lib/
if [ -d "Perseus/src/libs" ]; then
    cp -r Perseus/src/libs/. ${bundle_id}/lib/
else
    echo "Warning: Perseus/src/libs not found. Skipping library copy."
fi

echo "Patching Azur Lane with Perseus"
# Try to locate UnityPlayerActivity.smali in a few common locations. Use find as a fallback.
target_smali=""
possible_paths=("${bundle_id}/smali_classes2/com/unity3d/player/UnityPlayerActivity.smali" "${bundle_id}/smali/com/unity3d/player/UnityPlayerActivity.smali")
for p in "${possible_paths[@]}"; do
    if [ -f "$p" ]; then
        target_smali="$p"
        break
    fi
done
if [ -z "$target_smali" ]; then
    echo "UnityPlayerActivity.smali not found in common locations, searching..."
    target_smali=$(find ${bundle_id} -type f -name 'UnityPlayerActivity.smali' -print -quit || true)
fi

if [ -z "$target_smali" ]; then
    echo "Error: UnityPlayerActivity.smali not found. Skipping smali patch." >&2
else
    echo "Found smali: $target_smali"
    # Backup original smali before editing
    cp "$target_smali" "${target_smali}.bak"
    oncreate=$(grep -n -m 1 'onCreate' "$target_smali" | sed 's/^[0-9]*:\(.*\)/\1/')
    if [ -z "$oncreate" ]; then
        echo "Could not locate onCreate line in $target_smali. Skipping insertion." >&2
    else
        # Insert native method declaration before onCreate
        sed -i -r "s#($oncreate)#.method private static native init(Landroid/content/Context;)V\n.end method\n\n\\1#" "$target_smali"
        # Insert loadLibrary and init call after the onCreate line
        sed -i -r "s#($oncreate)#\\1\n    const-string v0, \"Perseus\"\n\n    invoke-static {v0}, Ljava/lang/System;->loadLibrary(Ljava/lang/String;)V\n\n    invoke-static {p0}, Lcom/unity3d/player/UnityPlayerActivity;->init(Landroid/content/Context;)V\n#" "$target_smali"
    fi
fi

echo "Build Patched Azur Lane apk"
# Ensure build directory exists
mkdir -p build
java -jar apktool.jar b -f ${bundle_id} -o build/${bundle_id}.patched.apk

echo "Set Github Release version"
version=($(jq -r '.version_name' AzurLane/manifest.json))
echo "PERSEUS_VERSION=$(echo ${version})" >> $GITHUB_ENV
