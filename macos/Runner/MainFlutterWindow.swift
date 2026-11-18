import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var pointerChannel: FlutterMethodChannel?
  private var pointerMonitor: Any?
  private var focusObserver: NSObjectProtocol?
  private var pointerCaptured = false
  private var primaryHeld = false
  private var secondaryHeld = false

  private func releasePointer() {
    guard pointerCaptured else { return }
    pointerCaptured = false
    CGAssociateMouseAndMouseCursorPosition(1)
    NSCursor.unhide()
    primaryHeld = false
    secondaryHeld = false
    pointerChannel?.invokeMethod("released", arguments: nil)
  }

  private func setupPointer(_ controller: FlutterViewController) {
    acceptsMouseMovedEvents = true
    let channel = FlutterMethodChannel(name: "crime_oren/relative_pointer",
      binaryMessenger: controller.engine.binaryMessenger)
    pointerChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(false); return }
      switch call.method {
      case "capture":
        guard self.isKeyWindow else { result(false); return }
        if !self.pointerCaptured {
          guard CGAssociateMouseAndMouseCursorPosition(0) == .success else {
            result(false); return
          }
          self.pointerCaptured = true
          NSCursor.hide()
        }
        result(true)
      case "release": self.releasePointer(); result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
    focusObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didResignKeyNotification, object: self, queue: .main) { [weak self] _ in
        self?.releasePointer()
      }
    pointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [
      .mouseMoved, .leftMouseDragged, .rightMouseDragged,
      .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp
    ]) { [weak self] event in
      guard let self = self, self.pointerCaptured else { return event }
      guard self.isKeyWindow else { self.releasePointer(); return event }
      switch event.type {
      case .mouseMoved, .leftMouseDragged, .rightMouseDragged:
        self.pointerChannel?.invokeMethod("delta", arguments: ["dx": event.deltaX, "dy": event.deltaY])
      case .leftMouseDown: self.primaryHeld = true
      case .leftMouseUp: self.primaryHeld = false
      case .rightMouseDown: self.secondaryHeld = true
      case .rightMouseUp: self.secondaryHeld = false
      default: break
      }
      self.pointerChannel?.invokeMethod("buttons", arguments: [
        "primary": self.primaryHeld, "secondary": self.secondaryHeld])
      // Keep Flutter's button state synchronized; its absolute cursor stays put.
      return event
    }
  }

  deinit {
    if pointerCaptured { CGAssociateMouseAndMouseCursorPosition(1); NSCursor.unhide() }
    if let monitor = pointerMonitor { NSEvent.removeMonitor(monitor) }
    if let observer = focusObserver { NotificationCenter.default.removeObserver(observer) }
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    title = "Crime Oren"
    minSize = NSSize(width: 960, height: 600)
    let available = screen?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
    setContentSize(NSSize(width: min(1280, available.width * 0.9),
                          height: min(800, available.height * 0.9)))
    center()

    setupPointer(flutterViewController)
    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
