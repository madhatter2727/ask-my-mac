#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$HOME/Applications/Ask My Mac.app"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/AskMyMac"
osascript -e 'quit app "Ask My Mac"' >/dev/null 2>&1 || true
sleep 1; pkill -x AskMyMac >/dev/null 2>&1 || true
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/AskMyMac"
PLIST="$APP/Contents/Info.plist"
cp "Resources/Info.plist" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable AskMyMac" "$PLIST" \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string AskMyMac" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.tara.askmymac" "$PLIST" \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.tara.askmymac" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundlePackageType APPL" "$PLIST" \
  || /usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :NSMicrophoneUsageDescription Ask My Mac uses the microphone for push-to-talk. Audio stays on this Mac." "$PLIST" \
  || /usr/libexec/PlistBuddy -c "Add :NSMicrophoneUsageDescription string Ask My Mac uses the microphone for push-to-talk. Audio stays on this Mac." "$PLIST"
/usr/libexec/PlistBuddy -c "Set :NSSpeechRecognitionUsageDescription Ask My Mac turns your speech into text on this Mac. Recognition stays on device." "$PLIST" \
  || /usr/libexec/PlistBuddy -c "Add :NSSpeechRecognitionUsageDescription string Ask My Mac turns your speech into text on this Mac. Recognition stays on device." "$PLIST"
codesign --force --deep -s - -r="designated => identifier \"com.tara.askmymac\"" "$APP"  # stable identity: keeps macOS permissions across updates
open "$APP"
echo "Installed and launched: $APP"
