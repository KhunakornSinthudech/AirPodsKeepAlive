#!/bin/zsh
LABEL=local.airpods-keepalive
launchctl bootout gui/$UID ~/Library/LaunchAgents/$LABEL.plist 2>/dev/null
pkill -x AirPodsKeepAlive 2>/dev/null
rm -f ~/Library/LaunchAgents/$LABEL.plist
rm -rf ~/Applications/AirPodsKeepAlive.app /Applications/AirPodsKeepAlive.app 2>/dev/null
defaults delete local.airpods-keepalive 2>/dev/null
rm -f ~/Library/Logs/AirPodsKeepAlive.log
rm -f /tmp/airpods-keepalive.log /tmp/airpods-keepalive.lock
rm -rf "${0:A:h}/build"
echo "Uninstalled."
