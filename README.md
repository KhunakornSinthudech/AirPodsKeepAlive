# AirPodsKeepAlive

A tiny background helper that works around **AirPods going silent and disconnecting when you press Play in Apple Music, QuickTime or other AVFoundation apps** on Hackintosh machines that use a non-Apple Bluetooth controller (e.g. Intel AX210 with IntelBluetoothFirmware / IntelBTPatcher).

## The problem

On affected machines, AirPods connect fine, all AirPods features work, YouTube in Safari plays fine, but:

- Press Play in **Music / QuickTime / Podcasts** → **no sound**
- About **3 seconds later** the AirPods send AVRCP *Pause* (or AVDTP *Suspend*) and the link drops with *Connection Timeout*, then reconnects
- It happens again **every time playback starts**, including when you change tracks
- Playing something in **Safari first** makes it work, as long as Safari keeps the audio stream open

What we found while debugging (with PacketLogger + a patched IntelBTPatcher):

- The Mac sends AVDTP START and the AAC media packets normally. The AirPods receive them but don't play them, then drop the stream about 3 s later.
- HCI, AVDTP, AVRCP and AACP control traffic is byte-for-byte the same as when Safari starts the stream.
- When a stream started by **WebKit (Safari)** is already running, audio from AVFoundation apps mixed into it plays normally.

The root cause hasn't been found yet. This tool is a workaround, not a fix.

## How the workaround works

`AirPodsKeepAlive` is a small menu bar app (no Dock icon). It hosts an invisible `WKWebView`, the same WebKit audio path Safari uses, and loops a 30-second clip of **±2 LSB noise (~-80 dBFS)**. The clip is inaudible, but it is not digital silence.

It only plays while **both** of these are true (checked every 2 s):

1. One of the watched apps is running (default: `com.apple.Music`, `com.apple.QuickTimePlayerX`, `com.apple.podcasts`)
2. The current default output device is **Bluetooth**

So while the watched apps are closed, or the output isn't Bluetooth, it does nothing.

### Menu bar

- **Menu bar icon**: a pair of AirPods with eyes. **Eyes open** = keeping the stream alive, **eyes closed** = idle, greyed out = disabled
- **Toast** (small banner under the menu bar) when it starts or stops: "AirPods keep-alive: active" / "stopped"
- Menu: current status, watched apps, **Enabled** (pause without quitting), **Start at Login**, **Show Log**, **Quit**
- Only **one instance** can run; launching it again (e.g. from Spotlight) exits immediately
- After **Quit**, open the app again from Applications / Spotlight to restart it

## Requirements

- macOS 13 or later for **Start at Login** (the rest works on macOS 12; tested on macOS 26 Tahoe, x86_64 Hackintosh)

## Install

### Option A: DMG (easiest)

1. Download `AirPodsKeepAlive-x.y.dmg` from [Releases](../../releases), open it and drag **AirPodsKeepAlive** to **Applications**.
2. Open it from Applications. The app is not notarized by Apple, so the first launch is blocked:
   - go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway**, or
   - run `xattr -dr com.apple.quarantine /Applications/AirPodsKeepAlive.app` and open it again.
3. On first launch it turns on **Start at Login** by itself (you'll see a toast). You can switch this off in the menu, or in **System Settings → General → Login Items**.

### Option B: build from source

Needs Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/KhunakornSinthudech/AirPodsKeepAlive.git
cd AirPodsKeepAlive
./install.sh
```

This builds the app, copies it to `~/Applications/AirPodsKeepAlive.app`, and starts it with a LaunchAgent (`~/Library/LaunchAgents/local.airpods-keepalive.plist`) instead of a Login Item, so it also restarts if it crashes. You can pass bundle IDs to watch: `./install.sh com.apple.Music com.spotify.client`.

To build the DMG yourself: `./make-dmg.sh` → `dist/AirPodsKeepAlive-x.y.dmg`.

### Watch other apps

By default it watches Music, QuickTime Player and Podcasts. To change the list (any install method), then quit and reopen the app:

```bash
defaults write local.airpods-keepalive WatchedApps -array com.apple.Music com.spotify.client com.colliderli.iina
```

Back to the default list: `defaults delete local.airpods-keepalive WatchedApps`

Find an app's bundle ID with:

```bash
osascript -e 'id of app "Spotify"'
```

## Check that it works

With AirPods connected, open Music. Within ~2 s you should get the "active" toast and the menu bar icon opens its eyes. Play music and skip tracks a few times; it should not drop.

To verify it really **stops** after you quit Music (wait ~5 s after quitting), there are three independent checks:

```bash
# 1. the app's own log (menu → Show Log): last line should be "keepalive OFF -> paused"
grep keepalive ~/Library/Logs/AirPodsKeepAlive.log | tail -3

# 2. power assertions: no WebKit/audio entry should remain
pmset -g assertions | grep -iE "audio|WebKit"

# 3. Bluetooth stream state reported by coreaudiod: last line should say Idle (not A2DPActive)
log show --last 2m --predicate 'process == "coreaudiod"' 2>/dev/null | grep RemoteStreamState | tail -3
```

## Uninstall

- **DMG install:** click the icon → **Quit**, turn off **Start at Login** first (or remove it in Login Items), then drag the app from Applications to the Trash.
- **Source install** (also cleans up everything from a DMG install): `./uninstall.sh`

## Trade-offs

- **AirPods battery:** while a watched app is open and output is Bluetooth, the A2DP stream stays active, so the AirPods drain like they're playing music. Quit Music when you're done to stop it.
- **Automatic switching:** while the stream is active, AirPods may not switch to your iPhone or iPad automatically, because they see the Mac as playing audio.
- **Mac CPU/power:** negligible (a looping 44.1 kHz clip in WebKit).

## Troubleshooting

| Symptom | Try |
|---|---|
| No menu bar icon | It was quit or failed to start. Open it again from Applications and check `~/Library/Logs/AirPodsKeepAlive.log` |
| "AirPodsKeepAlive is damaged / can't be opened" | Gatekeeper quarantine, see Install → Option A step 2 |
| Icon stays grey | Make sure the output device is the AirPods, a watched app is open, and **Enabled** is checked in the menu |
| `keepalive ON -> NotAllowedError` | WebKit blocked autoplay. Please open an issue with your macOS version. |
| Still drops | Start a watched app first, wait about 3 s, then press Play. Check the log shows `ON -> ok` before playback starts. |

## Context

Tested setup where the bug happens and this works around it:

- Intel AX210 Bluetooth, IntelBluetoothFirmware / IntelBTPatcher (lshbluesky fork 2.5.3), BlueToolFixup
- macOS 26.7 Tahoe, SMBIOS MacPro7,1
- AirPods Pro 2 (USB-C), firmware 9A348
- macOS reports the controller as `THIRD_PARTY_DONGLE`

If you have more information about the root cause, issues and PRs are welcome.

## License

MIT
