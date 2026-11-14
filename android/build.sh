#!/usr/bin/env bash
# Builds the Keybots Android preview APK with the plain SDK tools (no Gradle).
#   ./android/build.sh  →  android/build/keybots.apk
# Needs: the Android SDK (build-tools 35.0.0, platform android-36) and JDK 17.
set -euo pipefail
cd "$(dirname "$0")"
SDK="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
BT="$SDK/build-tools/35.0.0"
JAR="$SDK/platforms/android-36/android.jar"
export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@17}"
export PATH="$JAVA_HOME/bin:$PATH"
OUT=build
rm -rf "$OUT" && mkdir -p "$OUT/gen" "$OUT/classes" "$OUT/dex"

# Launcher icons from the brand icon (the white key mascot).
ICON=../landing/brand/out/icon.png
for d in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  mkdir -p "res/mipmap-${d%%:*}"
  sips -s format png -z "${d##*:}" "${d##*:}" "$ICON" --out "res/mipmap-${d%%:*}/ic_launcher.png" >/dev/null
done

"$BT/aapt2" compile --dir res -o "$OUT/res.zip"
"$BT/aapt2" link -I "$JAR" --manifest AndroidManifest.xml -o "$OUT/base.apk" "$OUT/res.zip" \
  --java "$OUT/gen" --min-sdk-version 24 --target-sdk-version 35 --version-code 1 --version-name 0.1-preview
javac --release 8 -classpath "$JAR" -Xlint:-options -d "$OUT/classes" $(find src "$OUT/gen" -name '*.java')
"$BT/d8" --min-api 24 --lib "$JAR" --output "$OUT/dex" $(find "$OUT/classes" -name '*.class')
cp "$OUT/base.apk" "$OUT/unsigned.apk"
(cd "$OUT/dex" && zip -qj ../unsigned.apk classes.dex)
"$BT/zipalign" -f 4 "$OUT/unsigned.apk" "$OUT/aligned.apk"

# A local signing key for the preview (kept out of git).
KS=keybots-preview.jks
[ -f "$KS" ] || keytool -genkeypair -keystore "$KS" -storepass keybots -keypass keybots -alias keybots \
  -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Keybots preview" >/dev/null 2>&1
"$BT/apksigner" sign --ks "$KS" --ks-pass pass:keybots --out "$OUT/keybots.apk" "$OUT/aligned.apk"
"$BT/apksigner" verify "$OUT/keybots.apk"
ls -l "$OUT/keybots.apk"
