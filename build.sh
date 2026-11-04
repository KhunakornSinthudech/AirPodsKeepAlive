#!/bin/zsh
# Build AirPodsKeepAlive.app into ./build (needs Xcode Command Line Tools)
set -e
cd "${0:A:h}"
APP=build/AirPodsKeepAlive.app/Contents
rm -rf build && mkdir -p $APP/MacOS $APP/Resources
cp src/Info.plist $APP/
cp src/keep.html $APP/Resources/
# app icon: src/AppIcon.png (1024x1024) -> AppIcon.icns
if [ -f src/AppIcon.png ]; then
  IS=build/AppIcon.iconset; mkdir -p $IS
  for s in 16 32 128 256 512; do
    sips -z $s $s src/AppIcon.png --out $IS/icon_${s}x${s}.png >/dev/null
    sips -z $((s*2)) $((s*2)) src/AppIcon.png --out $IS/icon_${s}x${s}@2x.png >/dev/null
  done
  iconutil -c icns $IS -o $APP/Resources/AppIcon.icns && rm -rf $IS
fi
# 30 s of ±2 LSB noise (~ -80 dBFS): inaudible, but not digital silence
perl -e 'open F,">$ARGV[0]" or die; binmode F; $r=44100; $n=$r*30; $d=$n*4;
  print F "RIFF",pack("V",36+$d),"WAVEfmt ",pack("VvvVVvv",16,1,2,$r,$r*4,4,16),"data",pack("V",$d);
  for (1..$n){ $v=int(rand(5))-2; print F pack("ss",$v,$v) }' $APP/Resources/quiet.wav
swiftc -O src/main.swift -o $APP/MacOS/AirPodsKeepAlive -framework Cocoa -framework WebKit -framework CoreAudio
codesign --force --deep -s - build/AirPodsKeepAlive.app >/dev/null 2>&1 || true
echo "Built: $PWD/build/AirPodsKeepAlive.app"
