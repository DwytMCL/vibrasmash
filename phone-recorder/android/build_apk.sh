#!/bin/sh
# Builds VibraSmashRecorder.apk in Termux without Gradle.
# Needs: javac, keytool, aapt2, d8, zipalign, apksigner, zip, and android.jar (API 34).
# Usage: sh android/build_apk.sh      (from anywhere)
set -eu
cd "$(dirname "$0")"
ANDROID_JAR=${ANDROID_JAR:-$HOME/.android-sdk/android.jar}
[ -f "$ANDROID_JAR" ] || { echo "android.jar not found at $ANDROID_JAR (set ANDROID_JAR)" >&2; exit 1; }
VERSION_CODE=${VERSION_CODE:-1}
VERSION_NAME=${VERSION_NAME:-1.0}

rm -rf build && mkdir -p build/assets/www build/gen build/obj build/dex
# Single source of truth: the web app one folder up.
cp ../index.html ../icon-192.png ../icon-512.png build/assets/www/

aapt2 compile --dir res -o build/res.zip
aapt2 link -I "$ANDROID_JAR" --manifest AndroidManifest.xml -A build/assets \
    --min-sdk-version 24 --target-sdk-version 34 \
    --version-code "$VERSION_CODE" --version-name "$VERSION_NAME" \
    --java build/gen -o build/unsigned.apk build/res.zip

javac -nowarn -Xlint:-options -source 8 -target 8 -bootclasspath "$ANDROID_JAR" \
    -d build/obj $(find src build/gen -name '*.java')
d8 --release --min-api 24 --lib "$ANDROID_JAR" --output build/dex $(find build/obj -name '*.class')
(cd build/dex && zip -q -j ../unsigned.apk classes.dex)

zipalign -f -p 4 build/unsigned.apk build/aligned.apk

# Local signing key, created once and reused so updates install over the old version.
# It is a personal key for your own phone, not a Play Store key. Keep the file.
KS=vibrasmash.keystore
if [ ! -f "$KS" ]; then
    keytool -genkeypair -keystore "$KS" -storepass vibrasmash -keypass vibrasmash \
        -alias vibrasmash -keyalg RSA -keysize 2048 -validity 10000 \
        -dname "CN=VibraSmash Recorder" >/dev/null 2>&1
fi
apksigner sign --ks "$KS" --ks-pass pass:vibrasmash --key-pass pass:vibrasmash \
    --out VibraSmashRecorder.apk build/aligned.apk
apksigner verify VibraSmashRecorder.apk
echo "Built $(pwd)/VibraSmashRecorder.apk"
