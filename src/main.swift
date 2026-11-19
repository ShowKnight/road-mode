import Cocoa

// 路上模式 v2.3  —  真正的菜单栏状态项（可被 Thaw / Ice 收纳管理）
// 点一下 = 60 分钟「合盖不睡 + 不休眠」倒计时；再点 = 取消；到期自动还原
// 心跳守护：caffeinate 被杀自动重生；状态只由倒计时决定
// 无 Dock、无快捷键、无菜单；开机自启；纯图标无文字

final class Controller: NSObject, NSApplicationDelegate {
    var item: NSStatusItem!
    var caff: Process?
    var beat: Timer?
    var active = false
    var endDate: Date?
    var lastClick: Date = .distantPast
    var lastLidCheck: Date = .distantPast
    var reassertCount = 0

    let agentLabel = "com.lonqi.roadmode"
    let pmsetPath = "/usr/bin/pmset"
    let windowSeconds: TimeInterval = 60 * 60
    var agentPath: String { NSHomeDirectory() + "/Library/LaunchAgents/\(agentLabel).plist" }

    func log(_ m: String) {
        let f = "/tmp/roadmode_debug.log"
        let line = ISO8601DateFormatter().string(from: Date()) + " " + m + "\n"
        if let d = line.data(using: .utf8) {
            if let h = FileHandle(forWritingAtPath: f) { h.seekToEndOfFile(); h.write(d); h.closeFile() }
            else { try? d.write(to: URL(fileURLWithPath: f)) }
        }
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildStatusItem()
        installLoginItem()
        startHeartbeat()
        log("launch v2.3 statusItem+countdown+selfheal")
    }

    func buildStatusItem() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = item.button {
            b.target = self
            b.action = #selector(handleClick)
            b.sendAction(on: [.leftMouseUp])
            b.toolTip = "路上模式：点一下 60 分钟不合盖休眠"
        }
        refresh()
    }

    // 2.5 秒防抖：同一物理点击被系统重复投递时忽略
    @objc func handleClick() {
        let now = Date()
        if now.timeIntervalSince(lastClick) < 2.5 { log("click ignored (debounce)"); return }
        lastClick = now
        if active { deactivate(reason: "user") } else { activate() }
    }

    func activate() {
        active = true
        endDate = Date().addingTimeInterval(windowSeconds)
        spawnCaff(seconds: Int(windowSeconds))
        setLid(on: true)
        log("activate 60m")
        refresh()
    }

    func deactivate(reason: String) {
        active = false
        endDate = nil
        killCaff()
        setLid(on: false)
        log("deactivate (\(reason))")
        refresh()
    }

    func spawnCaff(seconds: Int) {
        killCaff()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        p.arguments = ["-dimsu", "-t", "\(max(1, seconds))"]
        try? p.run()
        caff = p
    }

    func killCaff() {
        if let c = caff { caff = nil; if c.isRunning { c.terminate() } }
    }

    func startHeartbeat() {
        beat = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.current.add(beat!, forMode: .common)
    }

    func tick() {
        if !active {
            if item != nil { refresh() }
            return
        }
        if let end = endDate, end.timeIntervalSinceNow <= 0 {
            deactivate(reason: "timeout")
            return
        }
        if caff == nil || !(caff!.isRunning) {
            let remain = endDate.map { Int($0.timeIntervalSinceNow) } ?? Int(windowSeconds)
            spawnCaff(seconds: remain)
            log("caff respawn remaining=\(remain)s")
        }
        // 自愈：系统侧可能把 SleepDisabled 悄悄清回 0（换电源、powerd 重载配置等），
        // 每 5 秒核对一次，掉线就立刻补回去 —— 否则后半段合盖又会被睡
        if Date().timeIntervalSince(lastLidCheck) >= 5 {
            lastLidCheck = Date()
            if !sleepDisabled() {
                setLid(on: true)
                reassertCount += 1
                log("lid drifted to 0 -> reasserted (#\(reassertCount))")
            }
        }
        refresh()
    }

    func refresh() {
        guard let b = item?.button else { return }
        let on = active
        let img = NSImage(systemSymbolName: on ? "cup.and.saucer.fill" : "cup.and.saucer",
                          accessibilityDescription: "路上模式")
        img?.isTemplate = true
        b.image = img
        b.imagePosition = .imageLeading
        b.contentTintColor = on ? NSColor.systemGreen : nil
        if on, let e = endDate {
            let secs = max(0, Int(e.timeIntervalSinceNow))
            let txt = secs >= 60 ? "\(secs / 60)m" : "\(secs)s"
            b.attributedTitle = NSAttributedString(string: " " + txt, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.systemGreen
            ])
        } else {
            b.attributedTitle = NSAttributedString(string: "")
        }
    }

    func setLid(on: Bool) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        p.arguments = ["-n", pmsetPath, "-a", "disablesleep", on ? "1" : "0"]
        try? p.run(); p.waitUntilExit()
        log("setLid(\(on)) -> \(sleepDisabled())")
    }

    func sleepDisabled() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: pmsetPath)
        p.arguments = ["-g"]
        let pipe = Pipe(); p.standardOutput = pipe
        try? p.run(); p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return out.range(of: "SleepDisabled\\s+1", options: .regularExpression) != nil
    }

    func installLoginItem() {
        let fm = FileManager.default
        let exec = Bundle.main.executablePath ?? "/Applications/RoadMode.app/Contents/MacOS/RoadMode"
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>Label</key><string>\(agentLabel)</string>
        <key>ProgramArguments</key><array><string>\(exec)</string></array>
        <key>RunAtLoad</key><true/>
        <key>KeepAlive</key><false/>
        </dict></plist>
        """
        if ((try? String(contentsOfFile: agentPath, encoding: .utf8)) ?? "") != plist {
            try? fm.createDirectory(atPath: NSHomeDirectory() + "/Library/LaunchAgents", withIntermediateDirectories: true)
            try? plist.write(toFile: agentPath, atomically: true, encoding: .utf8)
        }
    }
}

let app = NSApplication.shared
let ctl = Controller()
app.delegate = ctl
app.run()
