import Cocoa
import FlutterMacOS

@NSApplicationMain
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
}
