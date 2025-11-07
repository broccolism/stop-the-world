import Cocoa
import FlutterMacOS
import AVFoundation

class VideoTexture: NSObject, FlutterTexture {
    private var latestPixelBuffer: CVPixelBuffer?
    private let registry: FlutterTextureRegistry
    private(set) var textureId: Int64 = 0
    
    init(registry: FlutterTextureRegistry) {
        self.registry = registry
        super.init()
        self.textureId = registry.register(self)
    }
    
    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        guard let pixelBuffer = latestPixelBuffer else {
            return nil
        }
        return Unmanaged.passRetained(pixelBuffer)
    }
    
    func onFrameAvailable(_ pixelBuffer: CVPixelBuffer) {
        latestPixelBuffer = pixelBuffer
        registry.textureFrameAvailable(textureId)
    }
    
    func dispose() {
        registry.unregisterTexture(textureId)
    }
}

