//
//  File.swift
//  
//
//  Created by Thomas Roughton on 7/04/20.
//

import SubstrateUtilities

protocol SpecificRenderBackend: _RenderBackendProtocol {
    associatedtype RenderTargetDescriptor: BackendRenderTargetDescriptor
    associatedtype CommandBuffer: BackendCommandBuffer where CommandBuffer.Backend == Self
    
    associatedtype QueueImpl: Substrate.BackendQueue where QueueImpl.Backend == Self
    associatedtype Event
    associatedtype CompactedResourceCommandType
    
    associatedtype TransientResourceRegistry: BackendTransientResourceRegistry where TransientResourceRegistry.Backend == Self
    associatedtype PersistentResourceRegistry: BackendPersistentResourceRegistry where PersistentResourceRegistry.Backend == Self
    
    associatedtype BufferReference
    associatedtype TextureReference
    associatedtype ArgumentBufferReference
    associatedtype ArgumentBufferArrayReference
    associatedtype VisibleFunctionTableReference
    associatedtype IntersectionFunctionTableReference
    associatedtype SamplerReference
    
    associatedtype InterEncoderDependencyType: Dependency
    
    static var requiresResourceResidencyTracking: Bool { get }
    
    var supportsMemorylessAttachments: Bool { get }
    
    func makeQueue(renderGraphQueue: Queue) -> QueueImpl
    func makeSyncEvent(for queue: Queue) -> Event
    func freeSyncEvent(for queue: Queue)
    func syncEvent(for queue: Queue) -> Event?
    
    var activeContextLock: AsyncSpinLock { get }
    func setActiveContext(_ context: RenderGraphContextImpl<Self>?) async
    
    var resourceRegistry: PersistentResourceRegistry { get }
    func makeTransientRegistry(index: Int, inflightFrameCount: Int, queue: Queue) -> TransientResourceRegistry
    
    func compactResourceCommands(queue: Queue, resourceMap: FrameResourceMap<Self>, commandInfo: FrameCommandInfo<Self>, commandGenerator: ResourceCommandGenerator<Self>, into: inout [CompactedResourceCommand<CompactedResourceCommandType>])
    func didCompleteCommand(_ index: UInt64, queue: Queue, context: RenderGraphContextImpl<Self>) // Called on the context's DispatchQueue.
    
    static func fillArgumentBuffer(_ argumentBuffer: ArgumentBuffer, storage: ArgumentBufferReference, firstUseCommandIndex: Int, resourceMap: FrameResourceMap<Self>)
    static func fillArgumentBufferArray(_ argumentBufferArray: ArgumentBufferArray, storage: ArgumentBufferArrayReference, firstUseCommandIndex: Int, resourceMap: FrameResourceMap<Self>)
    
    func fillVisibleFunctionTable(_ table: VisibleFunctionTable, storage: VisibleFunctionTableReference, firstUseCommandIndex: Int, resourceMap: FrameResourceMap<Self>) async
    func fillIntersectionFunctionTable(_ table: IntersectionFunctionTable, storage: IntersectionFunctionTableReference, firstUseCommandIndex: Int, resourceMap: FrameResourceMap<Self>) async
}

extension SpecificRenderBackend {
    func didCompleteCommand(_ index: UInt64, queue: Queue, context: RenderGraphContextImpl<Self>) {
        
    }
}

protocol BackendRenderTargetDescriptor: AnyObject {
    init(renderPass: RenderPassRecord)
    var descriptor: RenderTargetDescriptor { get }
    func descriptorMergedWithPass(_ pass: RenderPassRecord, storedTextures: inout [Texture]) -> Self
    func finalise(storedTextures: inout [Texture])
}

protocol BackendQueue: AnyObject {
    associatedtype Backend: SpecificRenderBackend
    
    func makeCommandBuffer(
            commandInfo: FrameCommandInfo<Backend>,
             resourceMap: FrameResourceMap<Backend>,
        compactedResourceCommands: [CompactedResourceCommand<Backend.CompactedResourceCommandType>]) -> Backend.CommandBuffer
}

protocol BackendCommandBuffer: AnyObject {
    associatedtype Backend: SpecificRenderBackend
    
    func encodeCommands(encoderIndex: Int) async
    
    func waitForEvent(_ event: Backend.Event, value: UInt64)
    func signalEvent(_ event: Backend.Event, value: UInt64)
    func presentSwapchains(resourceRegistry: Backend.TransientResourceRegistry)
    func commit(onCompletion: @escaping (Self) -> Void) async
    
    var gpuStartTime: Double { get }
    var gpuEndTime: Double { get }
    
    var error: Error? { get }
}

protocol ResourceRegistry: AnyObject {
    associatedtype Backend: SpecificRenderBackend
    
    subscript(buffer: Buffer) -> Backend.BufferReference? { get }
    subscript(texture: Texture) -> Backend.TextureReference? { get }
    subscript(argumentBuffer: ArgumentBuffer) -> Backend.ArgumentBufferReference? { get }
    subscript(argumentBufferArray: ArgumentBufferArray) -> Backend.ArgumentBufferArrayReference? { get }
    
    func prepareFrame()
    func cycleFrames()
    func allocateArgumentBufferIfNeeded(_ buffer: ArgumentBuffer) -> Backend.ArgumentBufferReference
    func allocateArgumentBufferArrayIfNeeded(_ buffer: ArgumentBufferArray) -> Backend.ArgumentBufferArrayReference
}

protocol BackendTransientResourceRegistry: ResourceRegistry {
    static func isAliasedHeapResource(resource: Resource) -> Bool
    
    var accessLock: SpinLock { get set }
    
    func allocateBufferIfNeeded(_ buffer: Buffer, forceGPUPrivate: Bool) -> Backend.BufferReference
    func allocateTextureIfNeeded(_ texture: Texture, forceGPUPrivate: Bool, frameStoredTextures: [Texture]) -> Backend.TextureReference
    func allocateWindowHandleTexture(_ texture: Texture) throws -> Backend.TextureReference
    func allocateTextureView(_ texture: Texture, resourceMap: FrameResourceMap<Backend>) -> Backend.TextureReference
    
    func setDisposalFences(on resource: Resource, to fences: [FenceDependency])
    func disposeTexture(_ texture: Texture, waitEvent: ContextWaitEvent)
    func disposeBuffer(_ buffer: Buffer, waitEvent: ContextWaitEvent)
    func disposeArgumentBuffer(_ buffer: ArgumentBuffer, waitEvent: ContextWaitEvent)
    func disposeArgumentBufferArray(_ buffer: ArgumentBufferArray, waitEvent: ContextWaitEvent)
    
    func withHeapAliasingFencesIfPresent(for resourceHandle: Resource.Handle, perform: (inout [FenceDependency]) -> Void)
    
    var textureWaitEvents: TransientResourceMap<Texture, ContextWaitEvent> { get }
    var bufferWaitEvents: TransientResourceMap<Buffer, ContextWaitEvent> { get }
    var argumentBufferWaitEvents: TransientResourceMap<ArgumentBuffer, ContextWaitEvent>? { get }
    var argumentBufferArrayWaitEvents: TransientResourceMap<ArgumentBufferArray, ContextWaitEvent>? { get }
    var historyBufferResourceWaitEvents: [Resource : ContextWaitEvent] { get }
}

extension BackendTransientResourceRegistry {
    var argumentBufferWaitEvents: TransientResourceMap<ArgumentBuffer, ContextWaitEvent>? { nil }
    var argumentBufferArrayWaitEvents: TransientResourceMap<ArgumentBufferArray, ContextWaitEvent>? { nil }
}

protocol BackendPersistentResourceRegistry: ResourceRegistry {
    subscript(sampler: SamplerDescriptor) -> Backend.SamplerReference { get }
    
    @available(macOS 11.0, iOS 14.0, *)
    subscript(accelerationStructure: AccelerationStructure) -> AnyObject? { get }
    @available(macOS 11.0, iOS 14.0, *)
    subscript(visibleFunctionTable: VisibleFunctionTable) -> Backend.VisibleFunctionTableReference? { get }
    @available(macOS 11.0, iOS 14.0, *)
    subscript(intersectionFunctionTable: IntersectionFunctionTable) -> Backend.IntersectionFunctionTableReference? { get }
    
    func allocateBuffer(_ buffer: Buffer) -> Backend.BufferReference?
    func allocateTexture(_ texture: Texture) -> Backend.TextureReference?
    
    func allocateVisibleFunctionTableIfNeeded(_ table: VisibleFunctionTable) -> Backend.VisibleFunctionTableReference?
    func allocateIntersectionFunctionTableIfNeeded(_ table: IntersectionFunctionTable) -> Backend.IntersectionFunctionTableReference?
    
    func prepareMultiframeBuffer(_ buffer: Buffer, frameIndex: UInt64)
    func prepareMultiframeTexture(_ texture: Texture, frameIndex: UInt64)
    
    func disposeTexture(_ texture: Texture)
    func disposeBuffer(_ buffer: Buffer)
    func disposeArgumentBuffer(_ buffer: ArgumentBuffer)
    func disposeArgumentBufferArray(_ buffer: ArgumentBufferArray)
}
