import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var iconChannel: FlutterMethodChannel?
  
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
    
    // App Icon Manager Method Channel 설정
    setupAppIconChannel(controller: controller)
  }
  
  private func setupAppIconChannel(controller: FlutterViewController) {
    iconChannel = FlutterMethodChannel(
      name: "app_icon_manager",
      binaryMessenger: controller.engine.binaryMessenger
    )
    
    iconChannel?.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else { return }
      
      if call.method == "updateIcon" {
        guard let args = call.arguments as? [String: Any],
              let iconType = args["iconType"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "iconType is required", details: nil))
          return
        }
        
        self.updateAppIcon(iconType: iconType)
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }
  
  private func updateAppIcon(iconType: String) {
    // 아이콘 이미지 로드
    guard let iconImage = loadIconImage(for: iconType) else {
      print("[AppIcon] Failed to load icon for type: \(iconType)")
      return
    }
    
    // Dock 아이콘 업데이트
    NSApp.applicationIconImage = iconImage
    print("[AppIcon] Updated app icon to: \(iconType)")
  }
  
  private func loadIconImage(for iconType: String) -> NSImage? {
    // 앱 번들에서 아이콘 이미지 로드
    let iconFileName = "icon_\(iconType)"
    
    // 1. 번들의 Resources에서 찾기
    if let bundlePath = Bundle.main.path(forResource: iconFileName, ofType: "png"),
       let image = NSImage(contentsOfFile: bundlePath) {
      return image
    }
    
    // 2. 앱 번들의 Flutter assets에서 찾기
    if let assetPath = Bundle.main.path(forResource: "App", ofType: "framework"),
       let assetBundle = Bundle(path: assetPath),
       let flutterAssetPath = assetBundle.path(forResource: "flutter_assets/assets/\(iconFileName)", ofType: "png"),
       let image = NSImage(contentsOfFile: flutterAssetPath) {
      return image
    }
    
    // 3. 개발 모드: 프로젝트 assets 폴더에서 찾기
    if let projectPath = Bundle.main.resourcePath?.replacingOccurrences(of: "/Resources", with: ""),
       let parentPath = URL(fileURLWithPath: projectPath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().path as String? {
      let devAssetPath = "\(parentPath)/assets/\(iconFileName).png"
      if let image = NSImage(contentsOfFile: devAssetPath) {
        return image
      }
    }
    
    print("[AppIcon] Could not find icon file: \(iconFileName).png")
    return nil
  }
}
