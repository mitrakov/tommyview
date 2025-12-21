import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  // called when a user double-clicks on a file in Finder
  override func application(_ application: NSApplication, open urls: [URL]) {
    if (!urls.isEmpty) {
      (mainFlutterWindow as! MainFlutterWindow).currentFile = urls.first!.path
    }
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
