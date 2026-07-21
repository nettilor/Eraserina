import SwiftUI
import UniformTypeIdentifiers
import Carbon.HIToolbox

@main
struct EraserinaApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 540, minHeight: 560)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New from Screen Capture") { model.captureScreen() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(replacing: .pasteboard) {
                Button("Copy Result") { model.copyToClipboard() }
                    .keyboardShortcut("c", modifiers: .command)
                    .disabled(!model.hasImage)
                Button("Paste Image") { model.pasteFromClipboard() }
                    .keyboardShortcut("v", modifiers: .command)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { model.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!model.canUndo)
                Button("Redo") { model.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!model.canRedo)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save…") { model.saveResult() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!model.hasImage)
            }
            CommandGroup(after: .toolbar) {
                Button("Zoom In") { model.zoomBy(1.5) }
                    .keyboardShortcut("=", modifiers: .command)
                    .disabled(!model.hasImage)
                Button("Zoom Out") { model.zoomBy(1 / 1.5) }
                    .keyboardShortcut("-", modifiers: .command)
                    .disabled(!model.hasImage)
                Button("Zoom to Fit") { model.resetZoom() }
                    .keyboardShortcut("0", modifiers: .command)
                    .disabled(!model.hasImage)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}

// MARK: - Settings

enum CaptureHotkey: String, CaseIterable, Identifiable {
    case none, shiftCmd4, ctrlCmd4, shiftCmd6
    var id: String { rawValue }

    var label: String {
        switch self {
        case .none:      return "Off"
        case .shiftCmd4: return "⇧⌘4"
        case .ctrlCmd4:  return "⌃⌘4"
        case .shiftCmd6: return "⇧⌘6"
        }
    }
    var carbonCombo: (keyCode: UInt32, modifiers: UInt32)? {
        switch self {
        case .none:      return nil
        case .shiftCmd4: return (UInt32(kVK_ANSI_4), UInt32(cmdKey | shiftKey))
        case .ctrlCmd4:  return (UInt32(kVK_ANSI_4), UInt32(cmdKey | controlKey))
        case .shiftCmd6: return (UInt32(kVK_ANSI_6), UInt32(cmdKey | shiftKey))
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("playCaptureSound") private var playCaptureSound = true
    @AppStorage("captureHotkey") private var captureHotkey = CaptureHotkey.none.rawValue

    var body: some View {
        Form {
            Toggle("Play sound when capturing the screen", isOn: $playCaptureSound)

            Picker("Capture from anywhere", selection: $captureHotkey) {
                ForEach(CaptureHotkey.allCases) { k in
                    Text(k.label).tag(k.rawValue)
                }
            }
            .onChange(of: captureHotkey) { _ in model.applyHotkeyPreference() }

            Text("The global shortcut starts a capture even while Eraserina is in the background. To use ⇧⌘4, first turn off the system's version in System Settings → Keyboard → Keyboard Shortcuts → Screenshots (\"Save picture of selected area as a file\").")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 400)
    }
}

/// Registers a system-wide hotkey via Carbon (works without extra permissions).
final class HotKeyManager {
    var onTrigger: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    func apply(_ combo: (keyCode: UInt32, modifiers: UInt32)?) {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref); hotKeyRef = nil }
        guard let combo else { return }
        if handlerRef == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                     eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { manager.onTrigger?() }
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        }
        let id = EventHotKeyID(signature: 0x45726173, id: 1)   // 'Eras'
        RegisterEventHotKey(combo.keyCode, combo.modifiers, id,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}

// MARK: - Tools

enum Tool: String, CaseIterable, Identifiable {
    case wand = "Wand"          // remove connected region at click
    case color = "Color"        // remove clicked color everywhere
    case box = "Box"            // remove everything inside a dragged rectangle
    case restore = "Restore"    // bring back connected region at click
    var id: String { rawValue }

    var help: String {
        switch self {
        case .wand:    return "Click a region to erase everything connected to it"
        case .color:   return "Click a color to erase it everywhere in the image"
        case .box:     return "Drag a box to erase everything inside it"
        case .restore: return "Click to bring back an area that was removed"
        }
    }
    var icon: String {
        switch self {
        case .wand:    return "wand.and.stars"
        case .color:   return "eyedropper"
        case .box:     return "rectangle.dashed"
        case .restore: return "arrow.uturn.backward.circle"
        }
    }
}

// MARK: - Pixel engine (original pixels + editable alpha mask)

final class PixelEngine {
    let width: Int
    let height: Int
    let original: [UInt8]        // RGBA, row 0 = top
    var mask: [UInt8]            // 255 = keep, 0 = removed, in-between = soft edge

    init?(cgImage: CGImage) {
        width = cgImage.width
        height = cgImage.height
        let bytesPerRow = width * 4
        var buf = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let ctx = CGContext(
            data: &buf, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        original = buf
        mask = [UInt8](repeating: 255, count: width * height)
    }

    @inline(__always) private func colorDist(_ p: Int, to r: Double, _ g: Double, _ b: Double) -> Double {
        let i = p * 4
        let dr = Double(original[i]) - r
        let dg = Double(original[i+1]) - g
        let db = Double(original[i+2]) - b
        return (dr*dr + dg*dg + db*db).squareRoot()
    }

    private func colorAt(_ p: Int) -> (Double, Double, Double) {
        let i = p * 4
        return (Double(original[i]), Double(original[i+1]), Double(original[i+2]))
    }

    private var borderPixels: [Int] {
        var idx: [Int] = []
        for x in 0..<width { idx.append(x); idx.append((height - 1) * width + x) }
        for y in 0..<height { idx.append(y * width); idx.append(y * width + width - 1) }
        return idx
    }

    /// Flood fill over the ORIGINAL colors from seed pixels; returns removed flags.
    private func floodFill(seeds: [Int], ref: (Double, Double, Double), tol: Double) -> [Bool] {
        var region = [Bool](repeating: false, count: width * height)
        var visited = [Bool](repeating: false, count: width * height)
        var queue: [Int] = []
        for s in seeds where !visited[s] && colorDist(s, to: ref.0, ref.1, ref.2) <= tol {
            visited[s] = true; queue.append(s)
        }
        var head = 0
        while head < queue.count {
            let p = queue[head]; head += 1
            region[p] = true
            let x = p % width, y = p / width
            for (nx, ny) in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)] {
                if nx < 0 || ny < 0 || nx >= width || ny >= height { continue }
                let np = ny * width + nx
                if visited[np] { continue }
                visited[np] = true
                if colorDist(np, to: ref.0, ref.1, ref.2) <= tol { queue.append(np) }
            }
        }
        return region
    }

    /// Zero the mask for a region and feather neighboring near-match pixels.
    private func apply(removed: [Bool], ref: (Double, Double, Double), tol: Double) {
        for p in 0..<(width * height) where removed[p] { mask[p] = 0 }
        let softTol = tol * 2
        for p in 0..<(width * height) {
            if mask[p] == 0 { continue }
            let x = p % width, y = p / width
            var touches = false
            for (nx, ny) in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)] {
                if nx < 0 || ny < 0 || nx >= width || ny >= height { continue }
                if removed[ny * width + nx] { touches = true; break }
            }
            guard touches else { continue }
            let d = colorDist(p, to: ref.0, ref.1, ref.2)
            if d < softTol {
                let alpha = max(0.0, min(1.0, (d - tol) / max(tol, 1)))
                mask[p] = min(mask[p], UInt8(alpha * 255))
            }
        }
    }

    // MARK: Operations (each mutates mask; caller snapshots for undo)

    func autoRemove(tolerance tol: Double, edgesOnly: Bool) {
        // Detect background = most common border color
        var counts: [UInt32: Int] = [:]
        for p in borderPixels {
            let i = p * 4
            let k = UInt32(original[i]) << 16 | UInt32(original[i+1]) << 8 | UInt32(original[i+2])
            counts[k, default: 0] += 1
        }
        guard let bg = counts.max(by: { $0.value < $1.value })?.key else { return }
        let ref = (Double((bg >> 16) & 0xFF), Double((bg >> 8) & 0xFF), Double(bg & 0xFF))

        mask = [UInt8](repeating: 255, count: width * height)
        let removed: [Bool]
        if edgesOnly {
            removed = floodFill(seeds: borderPixels, ref: ref, tol: tol)
        } else {
            var r = [Bool](repeating: false, count: width * height)
            for p in 0..<(width * height) where colorDist(p, to: ref.0, ref.1, ref.2) <= tol { r[p] = true }
            removed = r
        }
        apply(removed: removed, ref: ref, tol: tol)
    }

    func wandRemove(at p: Int, tolerance tol: Double) {
        let ref = colorAt(p)
        let removed = floodFill(seeds: [p], ref: ref, tol: tol)
        apply(removed: removed, ref: ref, tol: tol)
    }

    func removeColorEverywhere(at p: Int, tolerance tol: Double) {
        let ref = colorAt(p)
        var removed = [Bool](repeating: false, count: width * height)
        for q in 0..<(width * height) where colorDist(q, to: ref.0, ref.1, ref.2) <= tol { removed[q] = true }
        apply(removed: removed, ref: ref, tol: tol)
    }

    /// Erase every pixel inside the rectangle (inclusive bounds, clamped).
    /// Hard-edged on purpose: box erasing is for straight screenshot edges.
    func removeRect(x0: Int, y0: Int, x1: Int, y1: Int) {
        let cx0 = max(0, min(x0, x1)), cx1 = min(width - 1, max(x0, x1))
        let cy0 = max(0, min(y0, y1)), cy1 = min(height - 1, max(y0, y1))
        guard cx0 <= cx1, cy0 <= cy1 else { return }
        for y in cy0...cy1 {
            let row = y * width
            for x in cx0...cx1 { mask[row + x] = 0 }
        }
    }

    func restore(at p: Int, tolerance tol: Double) {
        let ref = colorAt(p)
        // Flood over original colors so we can grow back through removed pixels
        let region = floodFill(seeds: [p], ref: ref, tol: tol)
        for q in 0..<(width * height) where region[q] { mask[q] = 255 }
    }

    // MARK: Output

    func render() -> CGImage? {
        let bytesPerRow = width * 4
        var out = [UInt8](repeating: 0, count: height * bytesPerRow)
        for p in 0..<(width * height) {
            let i = p * 4
            let m = Double(mask[p]) / 255.0
            let origA = Double(original[i+3]) / 255.0
            let a = m * origA
            out[i]   = UInt8(Double(original[i])   * m)
            out[i+1] = UInt8(Double(original[i+1]) * m)
            out[i+2] = UInt8(Double(original[i+2]) * m)
            out[i+3] = UInt8(a * 255)
        }
        guard let ctx = CGContext(
            data: &out, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        return ctx.makeImage()
    }

    /// Tight bounding box of every pixel that will be visible (final alpha > 0),
    /// in the same pixel grid render() produces. Nil if nothing remains.
    func contentBounds() -> (x: Int, y: Int, width: Int, height: Int)? {
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = y * width
            for x in 0..<width {
                let p = row + x
                // A pixel shows only if the mask kept it AND the source wasn't already transparent.
                if mask[p] != 0 && original[p * 4 + 3] != 0 {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return (minX, minY, maxX - minX + 1, maxY - minY + 1)
    }

    /// Same as render(), but cropped to contentBounds(). Falls back to the full
    /// image when nothing is left to crop.
    func renderCropped() -> CGImage? {
        guard let full = render() else { return nil }
        guard let b = contentBounds() else { return full }
        if b.x == 0, b.y == 0, b.width == width, b.height == height { return full }
        return full.cropping(to: CGRect(x: b.x, y: b.y, width: b.width, height: b.height)) ?? full
    }
}

// MARK: - App model

final class AppModel: ObservableObject {
    @Published var preview: NSImage? = nil
    @Published var statusText = "Drop a PNG, press ⌘V to paste, or ⌘N to capture your screen"
    @Published var tolerance: Double = 30
    @Published var edgesOnly = true
    @Published var clipToBounds = true   // Copy/Save crop to the subject's bounding box
    @Published var tool: Tool = .wand
    @Published var flashMessage: String? = nil
    @Published var canUndo = false
    @Published var canRedo = false
    @Published var zoom: CGFloat = 1     // 1 = fit to window
    @Published var pan: CGSize = .zero   // offset of image center from view center, in view points

    private var engine: PixelEngine? = nil
    private var sourceURL: URL? = nil
    private var undoStack: [[UInt8]] = []
    private var redoStack: [[UInt8]] = []
    private let maxHistory = 30
    private var busy = false
    private let hotKeys = HotKeyManager()
    weak var mainWindow: NSWindow?

    init() {
        hotKeys.onTrigger = { [weak self] in self?.captureScreen() }
        applyHotkeyPreference()
        // Escape minimizes the editor window (content stays loaded). Scoped to
        // the main window so Escape still cancels save panels, captures, etc.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  event.keyCode == 53,   // Escape
                  event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
                  let window = self.mainWindow,
                  event.window === window
            else { return event }
            self.minimizeWindow()
            return nil
        }
    }

    func minimizeWindow() {
        NSApp.hide(nil)   // instant, no genie animation; Dock click / ⌘Tab / capture brings it back
    }

    func applyHotkeyPreference() {
        let raw = UserDefaults.standard.string(forKey: "captureHotkey") ?? CaptureHotkey.none.rawValue
        hotKeys.apply((CaptureHotkey(rawValue: raw) ?? .none).carbonCombo)
    }

    var hasImage: Bool { engine != nil }
    var pixelSize: (Int, Int)? { engine.map { ($0.width, $0.height) } }

    // MARK: Input

    func load(url: URL) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            statusText = "Couldn't read that file"
            return
        }
        sourceURL = url
        setSource(cg)
    }

    func pasteFromClipboard() {
        let pb = NSPasteboard.general
        var cg: CGImage? = nil
        if let data = pb.data(forType: .png),
           let src = CGImageSourceCreateWithData(data as CFData, nil) {
            cg = CGImageSourceCreateImageAtIndex(src, 0, nil)
        } else if let data = pb.data(forType: .tiff),
                  let rep = NSBitmapImageRep(data: data) {
            cg = rep.cgImage
        } else if let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL],
                  let url = urls.first {
            load(url: url)
            return
        }
        guard let cg else { flash("No image in clipboard"); return }
        sourceURL = nil
        setSource(cg)
    }

    /// Hide the app, let the user drag a region with the system capture UI
    /// (same crosshair as ⌘⇧4), then load the result for background removal.
    func captureScreen() {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("eraserina-capture-\(UUID().uuidString).png")
        NSApp.hide(nil)
        // Give the window a beat to disappear before the crosshair comes up
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            var args = ["-i", tmp.path]   // interactive: drag a box, space for window mode, esc to cancel
            let playSound = UserDefaults.standard.object(forKey: "playCaptureSound") as? Bool ?? true
            if !playSound { args.insert("-x", at: 0) }
            task.arguments = args
            task.terminationHandler = { _ in
                DispatchQueue.main.async {
                    NSApp.unhide(nil)
                    NSApp.activate(ignoringOtherApps: true)
                    guard let self else { return }
                    self.mainWindow?.deminiaturize(nil)   // capture works from the minimized state too
                    if FileManager.default.fileExists(atPath: tmp.path) {
                        self.load(url: tmp)
                        self.sourceURL = nil    // temp file is not a real save location
                        try? FileManager.default.removeItem(at: tmp)
                    } else {
                        self.flash("Capture cancelled")
                    }
                }
            }
            do { try task.run() } catch {
                DispatchQueue.main.async {
                    NSApp.unhide(nil)
                    self?.flash("Couldn't launch screen capture")
                }
            }
        }
    }

    private func setSource(_ cg: CGImage) {
        guard let eng = PixelEngine(cgImage: cg) else {
            statusText = "Couldn't process that image"
            return
        }
        engine = eng
        undoStack = []
        redoStack = []
        resetZoom()
        runAuto(isInitial: true)
    }

    // MARK: Zoom

    static let maxZoom: CGFloat = 32

    /// Zoom around the view center (used by menu shortcuts; scroll zooms around the cursor).
    func zoomBy(_ factor: CGFloat) {
        let newZoom = min(Self.maxZoom, max(1, zoom * factor))
        guard newZoom != zoom else { return }
        let ratio = newZoom / zoom
        pan = CGSize(width: pan.width * ratio, height: pan.height * ratio)
        zoom = newZoom
    }

    func resetZoom() {
        zoom = 1
        pan = .zero
    }

    // MARK: Operations

    func runAuto(isInitial: Bool = false) {
        performOperation(label: isInitial ? "Auto removal done — click to fine-tune" : "Auto re-applied") { eng, tol, edges in
            eng.autoRemove(tolerance: tol, edgesOnly: edges)
        }
    }

    /// point in image pixel coordinates
    func clickAt(x: Int, y: Int) {
        guard let eng = engine, tool != .box,
              x >= 0, y >= 0, x < eng.width, y < eng.height else { return }
        let p = y * eng.width + x
        let currentTool = tool
        performOperation(label: nil) { eng, tol, _ in
            switch currentTool {
            case .wand:    eng.wandRemove(at: p, tolerance: tol)
            case .color:   eng.removeColorEverywhere(at: p, tolerance: tol)
            case .restore: eng.restore(at: p, tolerance: tol)
            case .box:     break   // box erasing is drag-driven, see eraseBox
            }
        }
    }

    /// rectangle in image pixel coordinates (inclusive), already intersecting the image
    func eraseBox(x0: Int, y0: Int, x1: Int, y1: Int) {
        guard engine != nil else { return }
        performOperation(label: "Box erased — ⌘Z to undo") { eng, _, _ in
            eng.removeRect(x0: x0, y0: y0, x1: x1, y1: y1)
        }
    }

    private func performOperation(label: String?, _ op: @escaping (PixelEngine, Double, Bool) -> Void) {
        guard let eng = engine, !busy else { return }
        busy = true
        statusText = "Processing…"
        // Snapshot for undo
        undoStack.append(eng.mask)
        if undoStack.count > maxHistory { undoStack.removeFirst() }
        redoStack = []
        updateHistoryFlags()

        let tol = tolerance, edges = edgesOnly
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            op(eng, tol, edges)
            let img = eng.render()
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                if let img {
                    self.preview = NSImage(cgImage: img, size: NSSize(width: img.width, height: img.height))
                    self.statusText = label ?? "\(self.tool.rawValue) applied — ⌘Z to undo"
                } else {
                    self.statusText = "Render failed"
                }
            }
        }
    }

    // MARK: Undo / redo

    func undo() {
        guard let eng = engine, let prev = undoStack.popLast() else { return }
        redoStack.append(eng.mask)
        eng.mask = prev
        refreshAfterHistoryChange(label: "Undone")
    }

    func redo() {
        guard let eng = engine, let next = redoStack.popLast() else { return }
        undoStack.append(eng.mask)
        eng.mask = next
        refreshAfterHistoryChange(label: "Redone")
    }

    private func refreshAfterHistoryChange(label: String) {
        guard let eng = engine else { return }
        updateHistoryFlags()
        if let img = eng.render() {
            preview = NSImage(cgImage: img, size: NSSize(width: img.width, height: img.height))
        }
        statusText = label
    }

    private func updateHistoryFlags() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    // MARK: Output

    private func currentCG() -> CGImage? {
        guard let eng = engine else { return nil }
        return clipToBounds ? eng.renderCropped() : eng.render()
    }

    func copyToClipboard() {
        guard let cg = currentCG(), let png = pngData(from: cg) else {
            flash("Nothing to copy yet"); return
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(png, forType: .png)
        let rep = NSBitmapImageRep(cgImage: cg)
        if let tiff = rep.tiffRepresentation { pb.setData(tiff, forType: .tiff) }
        flash(clipToBounds ? "Copied ✓ (\(cg.width)×\(cg.height))" : "Copied ✓")
        minimizeWindow()   // get out of the way for the paste
    }

    func saveResult() {
        guard let cg = currentCG() else { flash("Nothing to save yet"); return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = sourceURL.map {
            $0.deletingPathExtension().lastPathComponent + ".transparent.png"
        } ?? "clipboard.transparent.png"
        if let dir = sourceURL?.deletingLastPathComponent() { panel.directoryURL = dir }
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                self.flash("Couldn't save"); return
            }
            CGImageDestinationAddImage(dest, cg, nil)
            CGImageDestinationFinalize(dest)
            self.flash("Saved ✓")
        }
    }

    private func pngData(from cg: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    private func flash(_ message: String) {
        flashMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            if self?.flashMessage == message { self?.flashMessage = nil }
        }
    }
}

// MARK: - Views

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 14) {
            // Preview / drop zone
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .foregroundColor(isTargeted ? .accentColor : .secondary.opacity(0.5))
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
                    )

                if model.preview != nil {
                    CheckerboardView()
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(4)
                    EditablePreview()
                        .padding(6)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(4)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.badge.arrow.down")
                            .font(.system(size: 44))
                            .foregroundColor(.secondary)
                        Text(model.statusText)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }

                if let msg = model.flashMessage {
                    VStack {
                        Spacer()
                        Text(msg)
                            .font(.callout.weight(.medium))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(.thinMaterial, in: Capsule())
                            .padding(.bottom, 12)
                    }
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 300)
            .animation(.easeInOut(duration: 0.15), value: model.flashMessage)
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers)
            }

            // Tools
            if model.hasImage {
                Picker("Tool", selection: $model.tool) {
                    ForEach(Tool.allCases) { t in
                        Label(t.rawValue, systemImage: t.icon).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(model.tool.help)
                    .font(.callout)
                    .foregroundColor(.secondary)

                Text(model.tool == .box
                     ? "Scroll or pinch to zoom · drag to draw the box"
                     : "Scroll or pinch to zoom · drag to pan while zoomed")
                    .font(.caption)
                    .foregroundColor(Color.secondary.opacity(0.8))
            }

            HStack {
                Text("Tolerance")
                Slider(value: $model.tolerance, in: 5...100)
                Text("\(Int(model.tolerance))")
                    .monospacedDigit()
                    .frame(width: 32, alignment: .trailing)
            }

            HStack {
                Toggle("Auto removal from edges only", isOn: $model.edgesOnly)
                    .toggleStyle(.checkbox)
                Spacer()
                Button("Re-run Auto") { model.runAuto() }
                    .disabled(!model.hasImage)
            }

            HStack {
                Toggle("Clip export to bounding box", isOn: $model.clipToBounds)
                    .toggleStyle(.checkbox)
                    .help("When on, Copy and Save crop tightly around the remaining pixels, dropping empty space.")
                Spacer()
            }

            HStack(spacing: 12) {
                Button { model.captureScreen() } label: {
                    Label("Capture", systemImage: "camera.viewfinder")
                }
                .help("Capture a screen region (⌘N)")

                Button { model.pasteFromClipboard() } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }

                Button { model.undo() } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!model.canUndo)
                .help("Undo (⌘Z)")

                Button { model.redo() } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .disabled(!model.canRedo)
                .help("Redo (⇧⌘Z)")

                Spacer()

                Button { model.copyToClipboard() } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .disabled(!model.hasImage)

                Button { model.saveResult() } label: {
                    Label("Save…", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.hasImage)
            }

            if model.hasImage {
                Text(model.statusText)
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .background(WindowAccessor { model.mainWindow = $0 })
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            DispatchQueue.main.async { model.load(url: url) }
        }
        return true
    }
}

/// Renders the preview and translates clicks into image pixel coordinates.
/// Scroll or pinch to zoom (anchored at the cursor); drag to pan while zoomed.
struct EditablePreview: View {
    @EnvironmentObject var model: AppModel
    @State private var dragStartPan: CGSize? = nil
    @State private var marquee: (start: CGPoint, current: CGPoint)? = nil

    var body: some View {
        GeometryReader { geo in
            if let img = model.preview, let (pw, ph) = model.pixelSize {
                let fit = min(geo.size.width / CGFloat(pw), geo.size.height / CGFloat(ph))
                let scale = fit * model.zoom
                let dispW = CGFloat(pw) * scale
                let dispH = CGFloat(ph) * scale
                let ox = (geo.size.width - dispW) / 2 + model.pan.width
                let oy = (geo.size.height - dispH) / 2 + model.pan.height

                ZStack {
                    Image(nsImage: img)
                        .resizable()
                        .interpolation(model.zoom >= 4 ? .none : .high)  // show crisp pixels up close
                        .frame(width: dispW, height: dispH)
                        .position(x: geo.size.width / 2 + model.pan.width,
                                  y: geo.size.height / 2 + model.pan.height)

                    if let m = marquee {
                        let r = CGRect(x: min(m.start.x, m.current.x),
                                       y: min(m.start.y, m.current.y),
                                       width: abs(m.current.x - m.start.x),
                                       height: abs(m.current.y - m.start.y))
                        Rectangle()
                            .fill(Color.red.opacity(0.12))
                            .overlay(
                                Rectangle()
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                                    .foregroundColor(.red)
                            )
                            .frame(width: r.width, height: r.height)
                            .position(x: r.midX, y: r.midY)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .background(
                    ScrollZoomCatcher(
                        onScroll: { deltaY, location, precise in
                            let factor = exp(deltaY * (precise ? 0.01 : 0.05))
                            applyZoom(factor: factor, at: location, view: geo.size,
                                      pw: CGFloat(pw), ph: CGFloat(ph), fit: fit)
                        },
                        onMagnify: { magnification, location in
                            applyZoom(factor: 1 + magnification, at: location, view: geo.size,
                                      pw: CGFloat(pw), ph: CGFloat(ph), fit: fit)
                        }
                    )
                )
                .onTapGesture(coordinateSpace: .local) { location in
                    // Map click in view space -> image pixel space
                    let px = Int((location.x - ox) / scale)
                    let py = Int((location.y - oy) / scale)
                    guard px >= 0, py >= 0, px < pw, py < ph else { return }
                    model.clickAt(x: px, y: py)
                }
                .gesture(
                    DragGesture(minimumDistance: 3, coordinateSpace: .local)
                        .onChanged { value in
                            if model.tool == .box {
                                marquee = (value.startLocation, value.location)
                            } else {
                                guard model.zoom > 1 else { return }
                                let base = dragStartPan ?? model.pan
                                dragStartPan = base
                                let moved = CGSize(width: base.width + value.translation.width,
                                                   height: base.height + value.translation.height)
                                model.pan = Self.clampPan(moved, view: geo.size, dispW: dispW, dispH: dispH)
                            }
                        }
                        .onEnded { _ in
                            if let m = marquee {
                                // Map marquee corners from view space to image pixels
                                let x0 = max(0, Int((min(m.start.x, m.current.x) - ox) / scale))
                                let x1 = min(pw - 1, Int((max(m.start.x, m.current.x) - ox) / scale))
                                let y0 = max(0, Int((min(m.start.y, m.current.y) - oy) / scale))
                                let y1 = min(ph - 1, Int((max(m.start.y, m.current.y) - oy) / scale))
                                if x0 <= x1, y0 <= y1 {
                                    model.eraseBox(x0: x0, y0: y0, x1: x1, y1: y1)
                                }
                                marquee = nil
                            }
                            dragStartPan = nil
                        }
                )
                .overlay(alignment: .topTrailing) {
                    if model.zoom > 1.001 {
                        HStack(spacing: 6) {
                            Text("\(Int((model.zoom * 100).rounded()))%")
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                            Button { model.resetZoom() } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Zoom to fit (⌘0)")
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.thinMaterial, in: Capsule())
                        .padding(8)
                    }
                }
            }
        }
    }

    /// Change zoom by `factor`, keeping the image point under `location` fixed on screen.
    private func applyZoom(factor: CGFloat, at location: CGPoint, view: CGSize,
                           pw: CGFloat, ph: CGFloat, fit: CGFloat) {
        let oldZoom = model.zoom
        let newZoom = min(AppModel.maxZoom, max(1, oldZoom * factor))
        guard abs(newZoom - oldZoom) > 0.0001 else { return }
        let oldScale = fit * oldZoom
        let newScale = fit * newZoom
        let ox = (view.width - pw * oldScale) / 2 + model.pan.width
        let oy = (view.height - ph * oldScale) / 2 + model.pan.height
        let imageX = (location.x - ox) / oldScale
        let imageY = (location.y - oy) / oldScale
        let pan = CGSize(
            width: location.x - imageX * newScale - (view.width - pw * newScale) / 2,
            height: location.y - imageY * newScale - (view.height - ph * newScale) / 2
        )
        model.zoom = newZoom
        model.pan = Self.clampPan(pan, view: view, dispW: pw * newScale, dispH: ph * newScale)
    }

    /// Keep the image from being dragged fully out of view; center it along any
    /// axis where it is smaller than the viewport.
    private static func clampPan(_ pan: CGSize, view: CGSize, dispW: CGFloat, dispH: CGFloat) -> CGSize {
        let maxX = max(0, (dispW - view.width) / 2)
        let maxY = max(0, (dispH - view.height) / 2)
        return CGSize(width: min(maxX, max(-maxX, pan.width)),
                      height: min(maxY, max(-maxY, pan.height)))
    }
}

/// Invisible AppKit layer that turns scroll-wheel / trackpad-scroll and pinch
/// events over the preview into zoom callbacks. It never participates in hit
/// testing, so clicks, drags, and file drops pass straight through to SwiftUI.
struct ScrollZoomCatcher: NSViewRepresentable {
    var onScroll: (_ deltaY: CGFloat, _ location: CGPoint, _ precise: Bool) -> Void
    var onMagnify: (_ magnification: CGFloat, _ location: CGPoint) -> Void

    func makeNSView(context: Context) -> CatcherView { CatcherView() }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onScroll = onScroll
        view.onMagnify = onMagnify
    }

    final class CatcherView: NSView {
        var onScroll: ((CGFloat, CGPoint, Bool) -> Void)?
        var onMagnify: ((CGFloat, CGPoint) -> Void)?
        private var monitors: [Any] = []

        override var isFlipped: Bool { true }               // match SwiftUI's top-left origin
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitors()
            guard window != nil else { return }
            monitors.append(NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                let loc = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(loc), event.scrollingDeltaY != 0 else { return event }
                self.onScroll?(event.scrollingDeltaY, loc, event.hasPreciseScrollingDeltas)
                return nil
            } as Any)
            monitors.append(NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                let loc = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(loc) else { return event }
                self.onMagnify?(event.magnification, loc)
                return nil
            } as Any)
        }

        private func removeMonitors() {
            monitors.forEach { NSEvent.removeMonitor($0) }
            monitors = []
        }

        deinit { removeMonitors() }
    }
}

/// Hands the hosting NSWindow to whoever needs it (used for minimize/restore).
struct WindowAccessor: NSViewRepresentable {
    var onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onResolve(view.window) }
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { onResolve(view.window) }
    }
}

/// Checkerboard background so transparency is visible in the preview.
struct CheckerboardView: View {
    var body: some View {
        Canvas { context, size in
            let s: CGFloat = 10
            for row in 0..<Int(size.height / s) + 1 {
                for col in 0..<Int(size.width / s) + 1 {
                    if (row + col) % 2 == 0 {
                        context.fill(
                            Path(CGRect(x: CGFloat(col) * s, y: CGFloat(row) * s, width: s, height: s)),
                            with: .color(.gray.opacity(0.25))
                        )
                    }
                }
            }
        }
    }
}
