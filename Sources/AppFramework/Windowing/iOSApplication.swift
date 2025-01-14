//
//  iOSApplication.swift
//  Renderer
//
//  Created by Thomas Roughton on 20/01/18.
//

#if os(iOS)

import SubstrateMath
import Substrate
import UIKit
@preconcurrency import MetalKit
import ImGui

final class CocoaInputManager : InputManagerInternal {
    public var inputState = InputState<RawInputState>()
    
    var shouldQuit: Bool = false
    var frame: UInt32 = 0
    
    public init() {
        
    }
    
    func updateMousePosition(_ touch: UITouch) {
        let location = touch.preciseLocation(in: touch.window)
        
        inputState[.mouse][.mouseX] = RawInputState(value: Float(location.x), frame: self.frame)
        inputState[.mouse][.mouseY] = RawInputState(value: Float(location.y), frame: self.frame)
        inputState[.mouse][.mouseXInWindow] = RawInputState(value: Float(location.x), frame: self.frame)
        inputState[.mouse][.mouseYInWindow] = RawInputState(value: Float(location.y), frame: self.frame)
    }
    
    func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let touch = touches.first!
        self.updateMousePosition(touch)
        
    
        inputState[.mouse][.mouseButtonLeft] = RawInputState(active: true, frame: frame)
    }
    
    func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let touch = touches.first!
        self.updateMousePosition(touch)
        
        let location = touch.preciseLocation(in: touch.window)
        let previousLocation = touch.precisePreviousLocation(in: touch.window)
        
        let deltaX = location.x - previousLocation.x
        let deltaY = location.y - previousLocation.y
        
        inputState[.mouse][.mouseXRelative] = RawInputState(value: Float(deltaX), frame: self.frame)
        inputState[.mouse][.mouseYRelative] = RawInputState(value: Float(deltaY), frame: self.frame)
    }
    
    func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let touch = touches.first!
        self.updateMousePosition(touch)
        
        inputState[.mouse][.mouseButtonLeft].markInactive()
    }
    
    func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        inputState[.mouse][.mouseButtonLeft].markInactive()
    }
    
    
    func insertText(_ text: String) {
        ImGui.io.pointee.addInputCharactersUTF8(str: text)
    }
    
    func deleteBackward() {
        inputState[.keyboard][.backspace] = RawInputState(active: true, frame: self.frame)
        inputState[.keyboardScanCode][.backspace] = RawInputState(active: true, frame: self.frame)
    }
    
    func update(frame: UInt64, windows: [Window]) {
        self.frame = UInt32(truncatingIfNeeded: frame)
    }
}

public class CocoaApplication : Application {
    
    let contentScaleFactor : Float
    let viewController: UIViewController
    
    public init(delegate: ApplicationDelegate?, viewController: UIViewController, windowDelegate: @autoclosure () async -> WindowDelegate, updateScheduler: MetalUpdateScheduler, windowRenderGraph: RenderGraph) async {
        delegate?.applicationWillInitialise()
        
        self.viewController = viewController
        self.contentScaleFactor = Float(viewController.view.contentScaleFactor)
        let inputManager = CocoaInputManager()
        
        let windowDelegate = await windowDelegate()
        await super.init(delegate: delegate, updateables: [windowDelegate], inputManager: inputManager, updateScheduler: updateScheduler, windowRenderGraph: windowRenderGraph)
        
    }
    
    public override func createWindow(title: String, dimensions: WindowSize, flags: WindowCreationFlags, renderGraph: RenderGraph) -> Window {
        let window = CocoaWindow(viewController: self.viewController, inputManager: self.inputManager as! CocoaInputManager, renderGraph: renderGraph)
        self.windows.append(window)
        return window
    }
    
    public override func setCursorPosition(to position: SIMD2<Float>) {
        
    }
    
    public override var screens : [Screen] {
        return [Screen(position: WindowPosition(0, 0),
                       dimensions: self.windows[0].dimensions,
                       workspacePosition: WindowPosition(0, 0),
                       workspaceDimensions: self.windows[0].dimensions,
                       backingScaleFactor: self.contentScaleFactor)]
    }
}

#endif // os(iOS)

