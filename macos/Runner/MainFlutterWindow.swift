import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
    open var currentFile: String?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController.init()
    self.contentViewController = flutterViewController
    self.setFrame(NSScreen.main?.frame ?? self.frame, display: true) // full-screen

    // interop with Flutter
    let channel = FlutterMethodChannel(name: "mitrakov", binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler({
        (call: FlutterMethodCall, result: FlutterResult) -> Void in
        if (call.method == "getCurrentFile") {
            result(self.currentFile)
        } else {
            result(FlutterMethodNotImplemented)
        }
    })

    RegisterGeneratedPlugins(registry: flutterViewController)

    NSApp.activate(ignoringOtherApps: true) // move window to front
    super.awakeFromNib()
  }
}
