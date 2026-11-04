#!/bin/zsh
# Build AirPodsKeepAlive.app and package it as a drag-to-Applications DMG in ./dist
set -e
cd "${0:A:h}"
./build.sh
VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" src/Info.plist)
STAGE=build/dmg
rm -rf $STAGE dist && mkdir -p $STAGE dist
cp -R build/AirPodsKeepAlive.app $STAGE/
ln -s /Applications $STAGE/Applications
cp README.md $STAGE/README.md
hdiutil create -volname "AirPodsKeepAlive" -srcfolder $STAGE -ov -format UDZO "dist/AirPodsKeepAlive-$VER.dmg" >/dev/null
rm -rf build
echo "Created: $PWD/dist/AirPodsKeepAlive-$VER.dmg"
