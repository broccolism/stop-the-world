import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
  
  override func applicationDidFinishLaunching(_ notification: Notification) {
    let controller = mainFlutterWindow?.contentViewController as! FlutterViewController
    let registrar = controller.registrar(forPlugin: "PoseDetectionPlugin")
    
    if #available(macOS 11.0, *) {
      PoseDetectionPlugin.register(with: registrar)
    } else {
      print("PoseDetectionPlugin requires macOS 11.0 or later")
    }
  }
}
