//
//  iOSWindow.swift
//  LlamaCore
//
//  Created by Thomas Roughton on 11/01/19.
//

#if os(iOS)
import Foundation
import UIKit
@preconcurrency import Metal
@preconcurrency import MetalKit
import Substrate
import SubstrateUtilities

import ImGui

final class MTKEventView : MTKView, UIKeyInput {
    
    var frameworkWindow : Window?
    
    func insertText(_ text: String) {
        self.inputDelegate?.insertText(text)
    }
    
    func deleteBackward() {
        self.inputDelegate?.deleteBackward()
    }
    
    weak var inputDelegate : CocoaInputManager? = nil
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.inputDelegate?.touchesBegan(touches, with: event)
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.inputDelegate?.touchesMoved(touches, with: event)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.inputDelegate?.touchesEnded(touches, with: event)
    }
    
    override func touchesEstimatedPropertiesUpdated(_ touches: Set<UITouch>) {
        
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.inputDelegate?.touchesCancelled(touches, with: event)
    }
    
    override var canBecomeFirstResponder: Bool {
        return ImGui.io.pointee.WantCaptureKeyboard
    }
    
    var hasText : Bool {
        return ImGui.io.pointee.WantCaptureKeyboard
    }
}

@objc protocol ExtendedDynamicRangeContent {
    func setWantsExtendedDynamicRangeContent(_ wantsEDR: Bool)
}

// Our iOS specific view controller
public class CocoaWindow : Window, MTKWindow {

    let viewController : UIViewController
    public let mtkView: MTKView
    
    public var delegate: WindowDelegate?
    
    var _texture = CachedAsync<Texture>()
    
    public var texture: Texture {
        get async {
            return await _texture.getValue()
        }
    }
    
    public var title: String = "Main Window"
    
    init(viewController: UIViewController, inputManager: CocoaInputManager, renderGraph: RenderGraph) {
        self.viewController = viewController
        guard let mtkView = viewController.view as? MTKEventView else {
            fatalError("View of viewController is not an MTKEventView")
        }
        self.mtkView = mtkView
        mtkView.frameworkWindow = self
        
        mtkView.device = (RenderBackend.renderDevice as! MTLDevice)
        mtkView.backgroundColor = UIColor.black
        mtkView.colorPixelFormat = .bgr10_xr_srgb
        mtkView.depthStencilPixelFormat = .invalid
        mtkView.framebufferOnly = true
        mtkView.preferredFramesPerSecond = 120
        
        mtkView.isUserInteractionEnabled = true
        
//        let metalLayer = (mtkView.layer as! CAMetalLayer)
//        unsafeBitCast(metalLayer, to: ExtendedDynamicRangeContent.self).setWantsExtendedDynamicRangeContent(true)
//        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
//        mtkView.colorPixelFormat = .rgba16Float
        
        mtkView.inputDelegate = inputManager

        self._texture.constructor = { [unowned(unsafe) self] in
            let texture = await Texture(descriptor: self.textureDescriptor, isMinimised: false, nativeWindow: self.mtkView.layer, renderGraph: renderGraph)
            return texture
        }
    }
    
    public var textureDescriptor : TextureDescriptor {
        return TextureDescriptor(type: .type2D, format: PixelFormat(rawValue: mtkView.colorPixelFormat.rawValue)!, width: Int(exactly: self.drawableSize.width)!, height: Int(exactly: self.drawableSize.height)!, mipmapped: false)
    }
    
    public var drawableSize: WindowSize {
        let drawableSize = self.mtkView.drawableSize
        return WindowSize(Float(drawableSize.width), Float(drawableSize.height))
    }
    
    public var dimensions: WindowSize {
        get {
            let size = self.mtkView.bounds.size
            return WindowSize(Float(size.width), Float(size.height))
        }
        set {
            _ = newValue
        }
    }
    
    class DocumentPickerDelegate : NSObject, UIDocumentPickerDelegate {
        let group = DispatchGroup()
        var selectedURLs : [URL]? = nil
        
        override init() {
            super.init()
            
            self.group.enter()
        }
        
        public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            self.selectedURLs = urls
            self.group.leave()
        }
        
        public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            self.selectedURLs = nil
            self.group.leave()
        }
    }
    
    public func displayOpenDialog(allowedFileTypes: [String]?, options: FileChooserOptions) -> [URL]? {
        let pickerDelegate = DocumentPickerDelegate()
        DispatchQueue.main.async {
            let importPicker = UIDocumentPickerViewController(documentTypes: allowedFileTypes, in: .import)
            importPicker.delegate = pickerDelegate
            self.viewController.present(importPicker, animated: true, completion: nil)
        }
        
        pickerDelegate.group.wait()
        
        return nil
    }
    
    public func displaySaveDialog(allowedFileTypes: [String], options: FileChooserOptions) -> URL? {
        return nil
    }
    
    public var id: Int {
        return 0
    }
    
    public var position: WindowPosition {
        get {
            return WindowPosition(0, 0)
        }
        set {
            _ = newValue
        }
    }
    
    public var hasFocus: Bool {
        get {
            return true
        }
        set {
            _ = newValue
        }
    }
    
    public var isVisible: Bool {
        get {
            return true
        }
        set {
            _ = newValue
        }
    }
    
    public var alpha: Float {
        get {
            return 1.0
        }
        set {
            _ = newValue
        }
    }
    
    public var windowsInFrontCount: Int {
        return 0
    }
    
    public var fullscreen: Bool {
        get {
            return true
        }
        set {
            _ = newValue
        }
    }
    
    public func cycleFrames() {
        _texture.reset()
    }
}

#endif
