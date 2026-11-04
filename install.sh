#!/bin/zsh
# Build, install to ~/Applications and register a LaunchAgent.
# Optional: pass bundle IDs to watch, e.g.  ./install.sh com.apple.Music com.spotify.client
set -e
cd "${0:A:h}"
./build.sh
LABEL=local.airpods-keepalive
DEST=~/Applications/AirPodsKeepAlive.app
PLIST=~/Library/LaunchAgents/$LABEL.plist
launchctl bootout gui/$UID $PLIST 2>/dev/null || true
pkill -x AirPodsKeepAlive 2>/dev/null || true
mkdir -p ~/Applications ~/Library/LaunchAgents
rm -rf $DEST && cp -R build/AirPodsKeepAlive.app $DEST
rm -rf build   # avoid a second copy showing up in Spotlight/Launchpad
ARGS=""
for a in "$@"; do ARGS+="<string>$a</string>"; done
cat > $PLIST <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$DEST/Contents/MacOS/AirPodsKeepAlive</string>$ARGS</array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ProcessType</key><string>Interactive</string>
  <key>StandardOutPath</key><string>/tmp/airpods-keepalive.log</string>
  <key>StandardErrorPath</key><string>/tmp/airpods-keepalive.log</string>
</dict></plist>
P
# this install uses a LaunchAgent, so the app should not also register itself as a Login Item
defaults write local.airpods-keepalive SkipLoginSetup -bool true
launchctl bootstrap gui/$UID $PLIST
echo "Installed and running (look for the AirPods icon in the menu bar)."
echo "Log: ~/Library/Logs/AirPodsKeepAlive.log"
