// AirPodsKeepAlive
// Keeps a Bluetooth A2DP stream open through WebKit (the same path Safari uses)
// while a media app is running, so AVFoundation apps (Music, QuickTime, ...)
// can play to AirPods on Hackintosh setups where they otherwise go silent and
// drop ~3 s after playback starts.

import Cocoa
import WebKit
import CoreAudio
import ServiceManagement

setvbuf(stdout, nil, _IOLBF, 0)

// Log to ~/Library/Logs/AirPodsKeepAlive.log (works no matter how the app was launched)
let logURL = FileManager.default.homeDirectoryForCurrentUser
  .appendingPathComponent("Library/Logs/AirPodsKeepAlive.log")
func log(_ s: String) {
  let line = "\(Date()) \(s)\n"
  print(line, terminator: "")
  guard let data = line.data(using: .utf8) else { return }
  if let h = try? FileHandle(forWritingTo: logURL) {
    h.seekToEndOfFile(); h.write(data); try? h.close()
  } else {
    try? data.write(to: logURL)
  }
}

// ---- single instance (lock is held for the life of the process) ----
let lockFD = open("/tmp/airpods-keepalive.lock", O_CREAT | O_RDWR, 0o644)
if lockFD < 0 || flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
  log("another instance is already running, exiting")
  exit(0)
}

let defaultApps = ["com.apple.Music", "com.apple.QuickTimePlayerX", "com.apple.podcasts"]

// Watched apps: command-line args > `defaults write local.airpods-keepalive WatchedApps -array ...` > default list
func watchedApps() -> [String] {
  let args = Array(CommandLine.arguments.dropFirst()).filter { !$0.hasPrefix("-") }
  if !args.isEmpty { return args }
  if let list = UserDefaults.standard.stringArray(forKey: "WatchedApps"), !list.isEmpty { return list }
  return defaultApps
}

final class KeepAlive: NSObject, NSApplicationDelegate {
  let apps: Set<String>
  var web: WKWebView!
  var hostWindow: NSWindow!
  var statusItem: NSStatusItem!
  var statusLine: NSMenuItem!
  var enabledItem: NSMenuItem!
  var loginItem: NSMenuItem!
  var playing = false
  var enabled = true

  init(apps: [String]) { self.apps = Set(apps) }

  func applicationDidFinishLaunching(_ n: Notification) {
    setupWebView()
    setupMenuBar()
    log("started, watching: \(apps.sorted().joined(separator: ", "))")
    firstRunLoginSetup()
    Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.tick() }
  }

  // ---- WebKit audio ----
  func setupWebView() {
    let cfg = WKWebViewConfiguration()
    cfg.mediaTypesRequiringUserActionForPlayback = []
    web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1, height: 1), configuration: cfg)
    // Invisible 1x1 window keeps the page "visible" so WebKit does not throttle media.
    hostWindow = NSWindow(contentRect: NSRect(x: -100, y: -100, width: 1, height: 1),
                          styleMask: .borderless, backing: .buffered, defer: false)
    hostWindow.alphaValue = 0
    hostWindow.ignoresMouseEvents = true
    hostWindow.contentView = web
    hostWindow.orderFrontRegardless()
    let res = Bundle.main.resourceURL!
    web.loadFileURL(res.appendingPathComponent("keep.html"), allowingReadAccessTo: res)
  }

  // ---- menu bar ----
  func setupMenuBar() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.button?.image = KeepAlive.makeIcon(awake: false)

    let menu = NSMenu()
    statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    statusLine.isEnabled = false
    menu.addItem(statusLine)
    let names = apps.map { $0.components(separatedBy: ".").last ?? $0 }.sorted().joined(separator: ", ")
    let watch = NSMenuItem(title: "Watching: \(names)", action: nil, keyEquivalent: "")
    watch.isEnabled = false
    menu.addItem(watch)
    menu.addItem(.separator())
    enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
    enabledItem.target = self
    enabledItem.state = .on
    menu.addItem(enabledItem)
    loginItem = NSMenuItem(title: "Start at Login", action: #selector(toggleLogin), keyEquivalent: "")
    loginItem.target = self
    menu.addItem(loginItem)
    let showLog = NSMenuItem(title: "Show Log", action: #selector(openLog), keyEquivalent: "")
    showLog.target = self
    menu.addItem(showLog)
    menu.addItem(.separator())
    let quit = NSMenuItem(title: "Quit AirPodsKeepAlive", action: #selector(quitApp), keyEquivalent: "q")
    quit.target = self
    menu.addItem(quit)
    statusItem.menu = menu
    updateStatusUI()
    updateLoginUI()
  }

  // ---- start at login (SMAppService, macOS 13+) ----
  func loginEnabled() -> Bool {
    if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
    return false
  }

  func updateLoginUI() {
    if #available(macOS 13.0, *) {
      loginItem.state = loginEnabled() ? .on : .off
    } else {
      loginItem.isEnabled = false
      loginItem.title = "Start at Login (needs macOS 13+)"
    }
  }

  func setLogin(_ on: Bool) {
    guard #available(macOS 13.0, *) else { return }
    do {
      if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
      log("start at login = \(on)")
    } catch {
      log("start at login error: \(error)")
      if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }
    updateLoginUI()
  }

  // First launch from the DMG/Applications: turn on Start at Login once.
  // install.sh sets SkipLoginSetup because it uses a LaunchAgent instead.
  func firstRunLoginSetup() {
    let d = UserDefaults.standard
    if d.bool(forKey: "DidLoginSetup") || d.bool(forKey: "SkipLoginSetup") { return }
    d.set(true, forKey: "DidLoginSetup")
    setLogin(true)
    if loginEnabled() { toast("AirPodsKeepAlive will start at login") }
  }

  @objc func toggleLogin() { setLogin(!loginEnabled()) }

  @objc func openLog() { NSWorkspace.shared.open(logURL) }

  func updateStatusUI() {
    statusLine.title = !enabled ? "Disabled" : (playing ? "Active: keeping AirPods stream open" : "Idle")
    statusItem.button?.image = KeepAlive.makeIcon(awake: playing)
    statusItem.button?.appearsDisabled = !enabled
  }

  // Menu bar icon: a pair of AirPods with eyes. Eyes open = keeping the stream alive,
  // eyes closed = idle. Drawn as a template image so it follows light/dark menu bar.
  static func makeIcon(awake: Bool) -> NSImage {
    let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
      guard let ctx = NSGraphicsContext.current else { return false }
      func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
        NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: r * 2, height: r * 2)).fill()
      }
      let buds: [CGFloat] = [-1, 1]            // left, right
      let headY: CGFloat = 12.6
      NSColor.black.setFill()
      NSColor.black.setStroke()
      // heads + stems
      for d in buds {
        let cx = 9 + d * 4.3
        circle(cx, headY, 4.0)
        let sx = d < 0 ? cx + 0.9 : cx - 2.9
        NSBezierPath(roundedRect: NSRect(x: sx, y: 1.2, width: 2.0, height: 10), xRadius: 1.0, yRadius: 1.0).fill()
      }
      for d in buds {
        let cx = 9 + d * 4.3
        if awake {
          // big round eye: white (cut out), big pupil, two sparkle highlights (cut out)
          ctx.compositingOperation = .clear
          circle(cx, headY, 2.8)
          ctx.compositingOperation = .sourceOver
          let py = headY - 0.35
          circle(cx, py, 2.0)
          ctx.compositingOperation = .clear
          circle(cx - 0.7, py + 0.7, 0.7)
          circle(cx + 0.75, py - 0.65, 0.32)
          ctx.compositingOperation = .sourceOver
        } else {
          // closed, happy eye
          ctx.compositingOperation = .clear
          let lid = NSBezierPath()
          lid.appendArc(withCenter: NSPoint(x: cx, y: headY + 0.9), radius: 2.0,
                        startAngle: 210, endAngle: 330, clockwise: false)
          lid.lineWidth = 1.0
          lid.lineCapStyle = .round
          lid.stroke()
          ctx.compositingOperation = .sourceOver
        }
      }
      return true
    }
    img.isTemplate = true
    return img
  }

  @objc func toggleEnabled() {
    enabled.toggle()
    enabledItem.state = enabled ? .on : .off
    log("enabled = \(enabled)")
    let wasPlaying = playing
    tick()
    if playing == wasPlaying {   // tick() changed nothing, so give feedback here
      updateStatusUI()
      toast(enabled ? "AirPods keep-alive enabled" : "AirPods keep-alive disabled")
    }
  }

  @objc func quitApp() {
    if playing { web.evaluateJavaScript("document.getElementById('a').pause()") }
    log("quit by user")
    NSApp.terminate(nil)   // exit code 0: launchd will not restart it until next login
  }

  // ---- logic ----
  func bluetoothOutput() -> Bool {
    var id = AudioDeviceID(0)
    var sz = UInt32(MemoryLayout<AudioDeviceID>.size)
    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                          mScope: kAudioObjectPropertyScopeGlobal,
                                          mElement: kAudioObjectPropertyElementMain)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &sz, &id) == noErr
    else { return false }
    var t: UInt32 = 0
    sz = UInt32(MemoryLayout<UInt32>.size)
    addr.mSelector = kAudioDevicePropertyTransportType
    guard AudioObjectGetPropertyData(id, &addr, 0, nil, &sz, &t) == noErr else { return false }
    return t == kAudioDeviceTransportTypeBluetooth || t == kAudioDeviceTransportTypeBluetoothLE
  }

  func tick() {
    let appOpen = NSWorkspace.shared.runningApplications.contains { apps.contains($0.bundleIdentifier ?? "") }
    let want = enabled && appOpen && bluetoothOutput()
    if want == playing { return }
    playing = want
    let js = want
      ? "document.getElementById('a').play().then(()=>'ok').catch(e=>String(e))"
      : "document.getElementById('a').pause(); 'paused'"
    web.evaluateJavaScript(js) { r, e in
      log("keepalive \(want ? "ON" : "OFF") -> \(r ?? e ?? "")")
    }
    updateStatusUI()
    toast(want ? "AirPods keep-alive: active" : "AirPods keep-alive: stopped")
  }

  // ---- toast (small HUD under the menu bar, no notification permission needed) ----
  func toast(_ text: String) {
    guard let screen = NSScreen.main?.visibleFrame else { return }
    let label = NSTextField(labelWithString: text)
    label.font = .systemFont(ofSize: 13, weight: .medium)
    label.textColor = .white
    label.sizeToFit()
    let padX: CGFloat = 16, padY: CGFloat = 10
    let size = NSSize(width: label.frame.width + padX * 2, height: label.frame.height + padY * 2)
    let rect = NSRect(x: screen.maxX - size.width - 12, y: screen.maxY - size.height - 8,
                      width: size.width, height: size.height)
    let panel = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.level = .statusBar
    panel.ignoresMouseEvents = true
    panel.hasShadow = true
    panel.collectionBehavior = [.canJoinAllSpaces, .transient]
    let bg = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
    bg.material = .hudWindow
    bg.blendingMode = .behindWindow
    bg.state = .active
    bg.wantsLayer = true
    bg.layer?.cornerRadius = 10
    bg.layer?.masksToBounds = true
    label.frame.origin = NSPoint(x: padX, y: padY)
    bg.addSubview(label)
    panel.contentView = bg
    panel.alphaValue = 0
    panel.orderFrontRegardless()
    NSAnimationContext.runAnimationGroup { $0.duration = 0.2; panel.animator().alphaValue = 1 }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
      NSAnimationContext.runAnimationGroup({ $0.duration = 0.4; panel.animator().alphaValue = 0 },
                                           completionHandler: { panel.orderOut(nil) })
    }
  }
}

let app = NSApplication.shared
let delegate = KeepAlive(apps: watchedApps())
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
