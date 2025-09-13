#!/bin/bash

# Ensure ANDROID_HOME is set or fall back to ANDROID_SDK_ROOT
if [ -z "$ANDROID_HOME" ]; then
    if [ -n "$ANDROID_SDK_ROOT" ]; then
        export ANDROID_HOME="$ANDROID_SDK_ROOT"
    fi
fi

export PATH="$PATH:$ANDROID_HOME/build-tools/32.0.0:$ANDROID_HOME/platform-tools"

# Check for zipalign
if ! command -v zipalign >/dev/null 2>&1; then
    echo "Error: zipalign not found in PATH. Ensure Android build-tools are installed and ANDROID_HOME is set." >&2
    exit 127
fi

# Check for apksigner
if ! command -v apksigner >/dev/null 2>&1; then
    echo "Error: apksigner not found in PATH. Ensure Android build-tools are installed and ANDROID_HOME is set." >&2
    exit 127
fi

# Find APKs
shopt -s nullglob
apks=(build/*.apk)
if [ ${#apks[@]} -eq 0 ]; then
    echo "Error: No APKs found in build/. Nothing to zipalign/sign." >&2
    exit 1
fi

for f in "${apks[@]}"; do
        unsigned="${f%.apk}.apk.unsigned"
        mv "$f" "$unsigned"
        echo "Zipaligning $f"
        zipalign -pvf 4 "$unsigned" "$f" || { echo "zipalign failed for $f" >&2; exit 1; }
        rm "$unsigned"
        echo "Signing $f"
        apksigner --version || true
        apksigner sign --key testkey.pk8 --cert testkey.x509.pem "$f" || { echo "apksigner failed for $f" >&2; exit 1; }
done

echo "All APKs aligned and signed."
