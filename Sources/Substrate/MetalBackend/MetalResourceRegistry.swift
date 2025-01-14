//
//  MetalResourceRegistry.swift
//  MetalRenderer
//
//  Created by Thomas Roughton on 23/12/17.
//

#if canImport(Metal)

@preconcurrency import Metal
@preconcurrency import MetalKit
import SubstrateUtilities
import OSLog

protocol MTLResourceReference {
    associatedtype Resource : MTLResource
    var resource : Resource { get }
}

// Must be a POD type and trivially copyable/movable
struct MTLBufferReference : MTLResourceReference {
    let _buffer : Unmanaged<MTLBuffer>
    let offset : Int
    
    var buffer : MTLBuffer {
        return self._buffer.takeUnretainedValue()
    }
    
    var resource : MTLBuffer {
        return self._buffer.takeUnretainedValue()
    }
    
    init(buffer: Unmanaged<MTLBuffer>, offset: Int) {
        self._buffer = buffer
        self.offset = offset
    }
}

// Must be a POD type and trivially copyable/movable
struct MTLTextureReference : MTLResourceReference {
    var _texture : Unmanaged<MTLTexture>!
    
    // For window handle textures only.
    var disposeWaitValue: UInt64 = 0
    var disposeWaitQueue: Queue? = nil
    
    var texture : MTLTexture! {
        return _texture?.takeUnretainedValue()
    }
    
    var resource : MTLTexture {
        return self.texture
    }
    
    init(windowTexture: ()) {
        self._texture = nil
    }
    
    init(texture: Unmanaged<MTLTexture>) {
        self._texture = texture
    }
}

struct MTLVisibleFunctionTableReference : MTLResourceReference {
    unowned(unsafe) let _table : AnyObject & MTLResource
    let functionCapacity: Int
    let pipelineState: UnsafeRawPointer
    let stage: RenderStages
    
    @available(macOS 11.0, iOS 14.0, *)
    var table : MTLVisibleFunctionTable {
        return self._table as! MTLVisibleFunctionTable
    }
    
    var resource : MTLResource {
        return self._table
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    init(table: MTLVisibleFunctionTable, functionCapacity: Int, pipelineState: UnsafeRawPointer, stage: RenderStages) {
        self._table = table
        self.functionCapacity = functionCapacity
        self.pipelineState = pipelineState
        self.stage = stage
    }
}

struct MTLIntersectionFunctionTableReference : MTLResourceReference {
    unowned(unsafe) let _table : AnyObject & MTLResource
    let functionCapacity: Int
    let pipelineState: UnsafeRawPointer
    let stage: RenderStages
    
    @available(macOS 11.0, iOS 14.0, *)
    var table : MTLIntersectionFunctionTable {
        return self._table as! MTLIntersectionFunctionTable
    }
    
    var resource : MTLResource {
        return self._table
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    init(table: MTLIntersectionFunctionTable, functionCapacity: Int, pipelineState: UnsafeRawPointer, stage: RenderStages) {
        self._table = table
        self.functionCapacity = functionCapacity
        self.pipelineState = pipelineState
        self.stage = stage
    }
}

struct MTLTextureUsageProperties {
    var usage : MTLTextureUsage
    var canBeMemoryless : Bool
    
    init(usage: MTLTextureUsage, canBeMemoryless: Bool = false) {
        self.usage = usage
        self.canBeMemoryless = canBeMemoryless
    }
}

final actor MetalPersistentResourceRegistry: BackendPersistentResourceRegistry {
    typealias Backend = MetalBackend
    
    @available(macOS 11.0, iOS 14.0, *)
    typealias AccelerationStructureReference = MTLAccelerationStructure
    
    let heapReferences = PersistentResourceMap<Heap, MTLHeap>()
    let textureReferences = PersistentResourceMap<Texture, MTLTextureReference>()
    let bufferReferences = PersistentResourceMap<Buffer, MTLBufferReference>()
    let argumentBufferReferences = PersistentResourceMap<ArgumentBuffer, MTLBufferReference>()
    let argumentBufferArrayReferences = PersistentResourceMap<ArgumentBufferArray, MTLBufferReference>()
    let accelerationStructureReferences = PersistentResourceMap<AccelerationStructure, MTLResource>()
    let visibleFunctionTableReferences = PersistentResourceMap<VisibleFunctionTable, MTLVisibleFunctionTableReference>()
    let intersectionFunctionTableReferences = PersistentResourceMap<IntersectionFunctionTable, MTLIntersectionFunctionTableReference>()
    
    var samplerReferences = [SamplerDescriptor : MTLSamplerState]()
    
    private let device : MTLDevice
    
    public init(device: MTLDevice) {
        self.device = device
        
        MetalFenceRegistry.instance = .init(device: self.device)
    }
    
    deinit {
        self.heapReferences.deinit()
        self.textureReferences.deinit()
        self.bufferReferences.deinit()
        self.argumentBufferReferences.deinit()
        self.argumentBufferArrayReferences.deinit()
    }
    
    @discardableResult
    public nonisolated func allocateHeap(_ heap: Heap) -> MTLHeap? {
        precondition(heap._usesPersistentRegistry)
        
        let descriptor = MTLHeapDescriptor(heap.descriptor, isAppleSiliconGPU: device.isAppleSiliconGPU)
        
        let mtlHeap = self.device.makeHeap(descriptor: descriptor)
        
        assert(self.heapReferences[heap] == nil)
        self.heapReferences[heap] = mtlHeap
        
        return mtlHeap
    }
    
    @discardableResult
    public nonisolated func allocateTexture(_ texture: Texture) -> MTLTextureReference? {
        precondition(texture._usesPersistentRegistry)
        
        if texture.flags.contains(.windowHandle) {
            // Reserve a slot in texture references so we can later insert the texture reference in a thread-safe way, but don't actually allocate anything yet
            self.textureReferences[texture] = MTLTextureReference(windowTexture: ())
            return nil
        }
        
        // NOTE: all synchronisation is managed through the per-queue waitIndices associated with the resource.
        
        let descriptor = MTLTextureDescriptor(texture.descriptor, usage: MTLTextureUsage(texture.descriptor.usageHint), isAppleSiliconGPU: device.isAppleSiliconGPU)
        
        let mtlTexture : MTLTextureReference
        if let heap = texture.heap {
            guard let mtlHeap = self.heapReferences[heap] else {
                print("Warning: requested heap \(heap) for texture \(texture) is invalid.")
                return nil
            }
            guard let mtlTextureObj = mtlHeap.makeTexture(descriptor: descriptor) else {
                return nil
            }
            mtlTexture = MTLTextureReference(texture: Unmanaged<MTLTexture>.passRetained(mtlTextureObj))
        } else {
            guard let mtlTextureObj = self.device.makeTexture(descriptor: descriptor) else {
                return nil
            }
            mtlTexture = MTLTextureReference(texture: Unmanaged<MTLTexture>.passRetained(mtlTextureObj))
        }
        
        if let label = texture.label {
            mtlTexture.texture.label = label
        }
        
        assert(self.textureReferences[texture] == nil)
        self.textureReferences[texture] = mtlTexture
        
        return mtlTexture
    }
    
    @discardableResult
    public nonisolated func allocateBuffer(_ buffer: Buffer) -> MTLBufferReference? {
        precondition(buffer._usesPersistentRegistry)
        
        // NOTE: all synchronisation is managed through the per-queue waitIndices associated with the resource.
        
        let options = MTLResourceOptions(storageMode: buffer.descriptor.storageMode, cacheMode: buffer.descriptor.cacheMode, isAppleSiliconGPU: device.isAppleSiliconGPU)
        
        let mtlBuffer : MTLBufferReference
        
        if let heap = buffer.heap {
            guard let mtlHeap = self.heapReferences[heap] else {
                print("Warning: requested heap \(heap) for buffer \(buffer) is invalid.")
                return nil
            }
            guard let mtlBufferObj = mtlHeap.makeBuffer(length: buffer.descriptor.length, options: options) else {
                return nil
            }
            mtlBuffer = MTLBufferReference(buffer: Unmanaged<MTLBuffer>.passRetained(mtlBufferObj), offset: 0)
        } else {
            guard let mtlBufferObj = self.device.makeBuffer(length: buffer.descriptor.length, options: options) else {
                return nil
            }
            mtlBuffer = MTLBufferReference(buffer: Unmanaged<MTLBuffer>.passRetained(mtlBufferObj), offset: 0)
        }
        
        if let label = buffer.label {
            mtlBuffer.buffer.label = label
        }
        
        assert(self.bufferReferences[buffer] == nil)
        self.bufferReferences[buffer] = mtlBuffer
        
        return mtlBuffer
    }
    
    @discardableResult
    public nonisolated func allocateArgumentBuffer(_ argumentBuffer: ArgumentBuffer, stateCaches: MetalStateCaches) -> MTLBufferReference? {
        precondition(argumentBuffer._usesPersistentRegistry)
        
        // NOTE: all synchronisation is managed through the per-queue waitIndices associated with the resource.
        
        let options: MTLResourceOptions = [.storageModeShared, .substrateTrackedHazards]
        
        let mtlBuffer : MTLBufferReference
        
        let descriptor = argumentBuffer.descriptor
        
        let encoder = stateCaches.argumentEncoderCache[descriptor]
        _ = argumentBuffer.replaceEncoder(with: Unmanaged.passUnretained(encoder).toOpaque(), expectingCurrentValue: nil)
        
        if let heap = argumentBuffer.heap {
            guard let mtlHeap = self.heapReferences[heap] else {
                print("Warning: requested heap \(heap) for buffer \(argumentBuffer) is invalid.")
                return nil
            }
            guard let mtlBufferObj = mtlHeap.makeBuffer(length: encoder.encoder.encodedLength, options: options) else {
                return nil
            }
            mtlBuffer = MTLBufferReference(buffer: Unmanaged<MTLBuffer>.passRetained(mtlBufferObj), offset: 0)
        } else {
            guard let mtlBufferObj = self.device.makeBuffer(length: encoder.encoder.encodedLength, options: options) else {
                return nil
            }
            mtlBuffer = MTLBufferReference(buffer: Unmanaged<MTLBuffer>.passRetained(mtlBufferObj), offset: 0)
        }
        
        if let label = argumentBuffer.label {
            mtlBuffer.buffer.label = label
        }
        
        assert(self.argumentBufferReferences[argumentBuffer] == nil)
        self.argumentBufferReferences[argumentBuffer] = mtlBuffer
        
        return mtlBuffer
    }
    
    func allocateArgumentBufferStorage<A : ResourceProtocol>(for argumentBuffer: A, encodedLength: Int) -> MTLBufferReference {
//        #if os(macOS)
//        let options : MTLResourceOptions = [.storageModeManaged, .substrateTrackedHazards]
//        #else
        let options : MTLResourceOptions = [.storageModeShared, .substrateTrackedHazards]
//        #endif
        
        return MTLBufferReference(buffer: Unmanaged.passRetained(self.device.makeBuffer(length: encodedLength, options: options)!), offset: 0)
    }
    
    @discardableResult
    func allocateArgumentBufferIfNeeded(_ argumentBuffer: ArgumentBuffer) async -> MTLBufferReference {
        if let baseArray = argumentBuffer.sourceArray {
            _ = await self.allocateArgumentBufferArrayIfNeeded(baseArray)
            return self.argumentBufferReferences[argumentBuffer]!
        }
        if let mtlArgumentBuffer = self.argumentBufferReferences[argumentBuffer] {
            return mtlArgumentBuffer
        }
        
        let argEncoder = Unmanaged<MetalArgumentEncoder>.fromOpaque(argumentBuffer.encoder!).takeUnretainedValue()
        
        var allocationLength = argumentBuffer.allocationLength
        if allocationLength == .max {
            allocationLength = argEncoder.encoder.encodedLength
        }
        
        let storage = self.allocateArgumentBufferStorage(for: argumentBuffer, encodedLength: allocationLength)
        
        self.argumentBufferReferences[argumentBuffer] = storage
        
        return storage
    }
    
    @discardableResult
    func allocateArgumentBufferArrayIfNeeded(_ argumentBufferArray: ArgumentBufferArray) async -> MTLBufferReference {
        if let mtlArgumentBuffer = self.argumentBufferArrayReferences[argumentBufferArray] {
            return mtlArgumentBuffer
        }
        
        let argEncoder = Unmanaged<MetalArgumentEncoder>.fromOpaque(argumentBufferArray._bindings.first(where: { $0?.encoder != nil })!!.encoder!).takeUnretainedValue()
        let storage = self.allocateArgumentBufferStorage(for: argumentBufferArray, encodedLength: argEncoder.encoder.encodedLength * argumentBufferArray._bindings.count)
        
        for (i, argumentBuffer) in argumentBufferArray._bindings.enumerated() {
            guard let argumentBuffer = argumentBuffer else { continue }
            
            let localStorage = MTLBufferReference(buffer: storage._buffer, offset: storage.offset + i * argEncoder.encoder.encodedLength)
            self.argumentBufferReferences[argumentBuffer] = localStorage
        }
        
        self.argumentBufferArrayReferences[argumentBufferArray] = storage
        
        return storage
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    @discardableResult
    public nonisolated func allocateAccelerationStructure(_ structure: AccelerationStructure) -> MTLAccelerationStructure? {
        let mtlStructure = self.device.makeAccelerationStructure(size: structure.size)
        
        assert(self.accelerationStructureReferences[structure] == nil)
        self.accelerationStructureReferences[structure] = mtlStructure
        
        return mtlStructure
    }
    
    func allocateVisibleFunctionTableIfNeeded(_ table: VisibleFunctionTable) async -> MTLVisibleFunctionTableReference? {
        guard #available(macOS 11.0, iOS 14.0, *) else { return nil }
        
        guard let pipelineState = table.pipelineState, let renderStage = table.usages.first?.stages else {
            print("Table \(table) has not been used with any pipeline.")
            return nil
        }
        
        if let tableRef = self.visibleFunctionTableReferences[table],
           pipelineState == tableRef.pipelineState,
           renderStage == tableRef.stage,
            tableRef.functionCapacity >= (table.functions.lastIndex(where: { $0 != nil }) ?? 0) + 1 {
            return tableRef
        }
        
        if let oldTable = self.visibleFunctionTableReferences[table]?.table {
            CommandEndActionManager.enqueue(action: .release(Unmanaged.passUnretained(oldTable)))
        }
        
        table.stateFlags.remove(.initialised)
        table[\.readWaitIndices] = .zero
        table[\.writeWaitIndices] = .zero
        
        let mtlDescriptor = MTLVisibleFunctionTableDescriptor()
        mtlDescriptor.functionCount = table.functions.count
        
        let mtlTable: MTLVisibleFunctionTable?
        let pipeline = Unmanaged<AnyObject>.fromOpaque(pipelineState).takeUnretainedValue()
        if let renderPipeline = pipeline as? MTLRenderPipelineState {
            guard #available(macOS 12.0, iOS 15.0, *) else { return nil }
            mtlTable = renderPipeline.makeVisibleFunctionTable(descriptor: mtlDescriptor, stage: MTLRenderStages(renderStage))
        } else {
            let computePipeline = pipeline as! MTLComputePipelineState
            mtlTable = computePipeline.makeVisibleFunctionTable(descriptor: mtlDescriptor)
        }
        guard let mtlTable = mtlTable else {
            print("MetalPeristentResourceRegistry: Failed to allocate visible function table \(table)")
            return nil
        }
        
        _ = Unmanaged.passRetained(mtlTable)
        
        let tableRef = MTLVisibleFunctionTableReference(table: mtlTable, functionCapacity: table.functions.count, pipelineState: pipelineState, stage: renderStage)
        self.visibleFunctionTableReferences[table] = tableRef
        
        return tableRef
    }
    
    func allocateIntersectionFunctionTableIfNeeded(_ table: IntersectionFunctionTable) async -> MTLIntersectionFunctionTableReference? {
        guard #available(macOS 11.0, iOS 14.0, *) else { return nil }
        
        guard let pipelineState = table.pipelineState, let renderStage = table.usages.first?.stages else {
            print("Table \(table) has not been used with any pipeline.")
            return nil
        }
        
        if let tableRef = self.intersectionFunctionTableReferences[table],
           pipelineState == tableRef.pipelineState,
           renderStage == tableRef.stage,
           tableRef.functionCapacity >= (table.descriptor.functions.lastIndex(where: { $0 != nil }) ?? 0) + 1 {
            return tableRef
        }
        
        if let oldTable = self.intersectionFunctionTableReferences[table]?.table {
            CommandEndActionManager.enqueue(action: .release(Unmanaged.passUnretained(oldTable)))
        }
        
        table.stateFlags.remove(.initialised)
        table[\.readWaitIndices] = .zero
        table[\.writeWaitIndices] = .zero
        
        let mtlDescriptor = MTLIntersectionFunctionTableDescriptor()
        mtlDescriptor.functionCount = table.descriptor.functions.count
        
        let mtlTable: MTLIntersectionFunctionTable?
        let pipeline = Unmanaged<AnyObject>.fromOpaque(pipelineState).takeUnretainedValue()
        if let renderPipeline = pipeline as? MTLRenderPipelineState {
            guard #available(macOS 12.0, iOS 15.0, *) else { return nil }
            mtlTable = renderPipeline.makeIntersectionFunctionTable(descriptor: mtlDescriptor, stage: MTLRenderStages(renderStage))
        } else {
            let computePipeline = pipeline as! MTLComputePipelineState
            mtlTable = computePipeline.makeIntersectionFunctionTable(descriptor: mtlDescriptor)
        }
        guard let mtlTable = mtlTable else {
            print("MetalPeristentResourceRegistry: Failed to allocate visible function table \(table)")
            return nil
        }
        
        _ = Unmanaged.passRetained(mtlTable)
        
        let tableRef = MTLIntersectionFunctionTableReference(table: mtlTable, functionCapacity: table.descriptor.functions.count, pipelineState: pipelineState, stage: renderStage)
        self.intersectionFunctionTableReferences[table] = tableRef
        
        return tableRef
    }
    
    public nonisolated func importExternalResource(_ resource: Resource, backingResource: Any) {
        if let texture = Texture(resource) {
            self.textureReferences[texture] = MTLTextureReference(texture: Unmanaged.passRetained(backingResource as! MTLTexture))
        } else if let buffer = Buffer(resource) {
            self.bufferReferences[buffer] = MTLBufferReference(buffer: Unmanaged.passRetained(backingResource as! MTLBuffer), offset: 0)
        }
    }
    
    public nonisolated subscript(texture: Texture) -> MTLTextureReference? {
        return self.textureReferences[texture]
    }

    public nonisolated subscript(buffer: Buffer) -> MTLBufferReference? {
        return self.bufferReferences[buffer]
    }

    public nonisolated subscript(heap: Heap) -> MTLHeap? {
        return self.heapReferences[heap]
    }

    public nonisolated subscript(argumentBuffer: ArgumentBuffer) -> MTLBufferReference? {
        return self.argumentBufferReferences[argumentBuffer]
    }

    public nonisolated subscript(argumentBufferArray: ArgumentBufferArray) -> MTLBufferReference? {
        return self.argumentBufferArrayReferences[argumentBufferArray]
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    public nonisolated subscript(structure: AccelerationStructure) -> AnyObject? {
        return self.accelerationStructureReferences[structure]
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    public nonisolated subscript(table: VisibleFunctionTable) -> MTLVisibleFunctionTableReference? {
        return self.visibleFunctionTableReferences[table]
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    public nonisolated subscript(table: IntersectionFunctionTable) -> MTLIntersectionFunctionTableReference? {
        return self.intersectionFunctionTableReferences[table]
    }
    
    public subscript(descriptor: SamplerDescriptor) -> MTLSamplerState {
        get async {
            if let state = self.samplerReferences[descriptor] {
                return state
            }
            
            let mtlDescriptor = MTLSamplerDescriptor(descriptor, isAppleSiliconGPU: device.isAppleSiliconGPU)
            let state = self.device.makeSamplerState(descriptor: mtlDescriptor)!
            self.samplerReferences[descriptor] = state
            
            return state
        }
    }
    
    nonisolated func prepareMultiframeBuffer(_ buffer: Buffer, frameIndex: UInt64) {
        // No-op for Metal
    }
    
    nonisolated func prepareMultiframeTexture(_ texture: Texture, frameIndex: UInt64) {
        // No-op for Metal
    }


    nonisolated func dispose(resource: Resource) {
        switch resource.type {
        case .buffer:
            let buffer = Buffer(resource)!
            if let mtlBuffer = self.bufferReferences.removeValue(forKey: buffer) {
                if mtlBuffer.buffer.heap != nil { mtlBuffer.buffer.makeAliasable() }
                CommandEndActionManager.enqueue(action: .release(Unmanaged.fromOpaque(mtlBuffer._buffer.toOpaque())))
            }
        case .texture:
            let texture = Texture(resource)!
            if let mtlTexture = self.textureReferences.removeValue(forKey: texture) {
                if texture.flags.contains(.windowHandle) {
                    return
                }
                if mtlTexture.texture.heap != nil { mtlTexture.texture.makeAliasable() }
                CommandEndActionManager.enqueue(action: .release(Unmanaged.fromOpaque(mtlTexture._texture.toOpaque())))
            }
            
        case .heap:
            let heap = Heap(resource)!
            if let mtlHeap = self.heapReferences.removeValue(forKey: heap) {
                CommandEndActionManager.enqueue(action: .release(Unmanaged.passRetained(mtlHeap)))
            }
            
        case .argumentBuffer:
            let buffer = ArgumentBuffer(resource)!
            if let mtlBuffer = self.argumentBufferReferences.removeValue(forKey: buffer) {
                assert(buffer.sourceArray == nil, "Persistent argument buffers from an argument buffer array should not be disposed individually; this needs to be fixed within the Metal RenderGraph backend.")
                CommandEndActionManager.enqueue(action: .release(Unmanaged.fromOpaque(mtlBuffer._buffer.toOpaque())))
            }
            
        case .argumentBufferArray:
            let buffer = ArgumentBufferArray(resource)!
            if let mtlBuffer = self.argumentBufferArrayReferences.removeValue(forKey: buffer) {
                CommandEndActionManager.enqueue(action: .release(Unmanaged.fromOpaque(mtlBuffer._buffer.toOpaque())))
            }
        case .accelerationStructure:
            let structure = AccelerationStructure(resource)!
            if let mtlStructure = self.accelerationStructureReferences.removeValue(forKey: structure) {
                CommandEndActionManager.enqueue(action: .release(Unmanaged.passRetained(mtlStructure)))
            }
            
        case .visibleFunctionTable:
            let table = VisibleFunctionTable(resource)!
            if let mtlTable = self.visibleFunctionTableReferences.removeValue(forKey: table) {
                CommandEndActionManager.enqueue(action: .release(Unmanaged.passRetained(mtlTable.resource)))
            }
            
        case .intersectionFunctionTable:
            let table = IntersectionFunctionTable(resource)!
            if let mtlTable = self.intersectionFunctionTableReferences.removeValue(forKey: table) {
                CommandEndActionManager.enqueue(action: .release(Unmanaged.passRetained(mtlTable.resource)))
            }
        default:
            preconditionFailure("dispose(resource:): Unhandled resource type \(resource.type)")
        }
    }
    
    nonisolated func cycleFrames() {
    }
    
}


final class MetalTransientResourceRegistry: BackendTransientResourceRegistry {
    
    typealias Backend = MetalBackend
    
    let device: MTLDevice
    let queue: Queue
    let persistentRegistry : MetalPersistentResourceRegistry
    var accessLock = SpinLock()
    
    private var textureReferences : TransientResourceMap<Texture, MTLTextureReference>
    private var bufferReferences : TransientResourceMap<Buffer, MTLBufferReference>
    private var argumentBufferReferences : TransientResourceMap<ArgumentBuffer, MTLBufferReference>
    private var argumentBufferArrayReferences : TransientResourceMap<ArgumentBufferArray, MTLBufferReference>
    
    var textureWaitEvents : TransientResourceMap<Texture, ContextWaitEvent>
    var bufferWaitEvents : TransientResourceMap<Buffer, ContextWaitEvent>
    var argumentBufferWaitEvents : TransientResourceMap<ArgumentBuffer, ContextWaitEvent>
    var argumentBufferArrayWaitEvents : TransientResourceMap<ArgumentBufferArray, ContextWaitEvent>
    var historyBufferResourceWaitEvents = [Resource : ContextWaitEvent]() // since history buffers use the persistent (rather than transient) resource maps.
    
    private var heapResourceUsageFences = [Resource : [FenceDependency]]()
    private var heapResourceDisposalFences = [Resource : [FenceDependency]]()
    
    private let frameSharedBufferAllocator : MetalTemporaryBufferAllocator
    private let frameSharedWriteCombinedBufferAllocator : MetalTemporaryBufferAllocator
    
    #if os(macOS) || targetEnvironment(macCatalyst)
    private let frameManagedBufferAllocator : MetalTemporaryBufferAllocator?
    private let frameManagedWriteCombinedBufferAllocator : MetalTemporaryBufferAllocator?
    #endif
    
    private let historyBufferAllocator : MetalPoolResourceAllocator
    
    private let memorylessTextureAllocator : MetalPoolResourceAllocator?
    
    private let frameArgumentBufferAllocator : MetalTemporaryBufferAllocator
    
    private let stagingTextureAllocator : MetalPoolResourceAllocator
    private let privateAllocator : MetalHeapResourceAllocator
    
    private let colorRenderTargetAllocator : MetalHeapResourceAllocator
    private let depthRenderTargetAllocator : MetalHeapResourceAllocator
    
    var windowReferences = [Texture : CAMetalLayer]()
    public private(set) var frameDrawables : [(Texture, Result<CAMetalDrawable, RenderTargetTextureError>)] = []
    
    var isExecutingFrame: Bool = false
    
    public init(device: MTLDevice, inflightFrameCount: Int, queue: Queue, transientRegistryIndex: Int, persistentRegistry: MetalPersistentResourceRegistry) {
        self.device = device
        self.queue = queue
        self.persistentRegistry = persistentRegistry
        
        self.textureReferences = .init(transientRegistryIndex: transientRegistryIndex)
        self.bufferReferences = .init(transientRegistryIndex: transientRegistryIndex)
        self.argumentBufferReferences = .init(transientRegistryIndex: transientRegistryIndex)
        self.argumentBufferArrayReferences = .init(transientRegistryIndex: transientRegistryIndex)
        
        self.textureWaitEvents = .init(transientRegistryIndex: transientRegistryIndex)
        self.bufferWaitEvents = .init(transientRegistryIndex: transientRegistryIndex)
        self.argumentBufferWaitEvents = .init(transientRegistryIndex: transientRegistryIndex)
        self.argumentBufferArrayWaitEvents = .init(transientRegistryIndex: transientRegistryIndex)
        
        self.stagingTextureAllocator = MetalPoolResourceAllocator(device: device, numFrames: inflightFrameCount)
        self.historyBufferAllocator = MetalPoolResourceAllocator(device: device, numFrames: 1)
        
        self.frameSharedBufferAllocator = MetalTemporaryBufferAllocator(device: device, numFrames: inflightFrameCount, blockSize: 256 * 1024, options: [.storageModeShared, .substrateTrackedHazards])
        self.frameSharedWriteCombinedBufferAllocator = MetalTemporaryBufferAllocator(device: device, numFrames: inflightFrameCount, blockSize: 2 * 1024 * 1024, options: [.storageModeShared, .cpuCacheModeWriteCombined, .substrateTrackedHazards])
        
        self.frameArgumentBufferAllocator = MetalTemporaryBufferAllocator(device: device, numFrames: inflightFrameCount, blockSize: 2 * 1024 * 1024, options: [.storageModeShared, .substrateTrackedHazards])
        
        #if os(macOS) || targetEnvironment(macCatalyst)
        if !device.isAppleSiliconGPU {
            self.frameManagedBufferAllocator = MetalTemporaryBufferAllocator(device: device, numFrames: inflightFrameCount, blockSize: 1024 * 1024, options: [.storageModeManaged, .substrateTrackedHazards])
            self.frameManagedWriteCombinedBufferAllocator = MetalTemporaryBufferAllocator(device: device, numFrames: inflightFrameCount, blockSize: 2 * 1024 * 1024, options: [.storageModeManaged, .cpuCacheModeWriteCombined, .substrateTrackedHazards])
        } else {
            self.frameManagedBufferAllocator = nil
            self.frameManagedWriteCombinedBufferAllocator = nil
        }
        #endif
        
        if device.isAppleSiliconGPU {
            self.memorylessTextureAllocator = MetalPoolResourceAllocator(device: device, numFrames: 1)
        } else {
            self.memorylessTextureAllocator = nil
        }
        
        self.privateAllocator = MetalHeapResourceAllocator(device: device, queue: queue, label: "Private Allocator for Queue \(queue.index)")
        self.depthRenderTargetAllocator = MetalHeapResourceAllocator(device: device, queue: queue, label: "Depth RT Allocator for Queue \(queue.index)")
        self.colorRenderTargetAllocator = MetalHeapResourceAllocator(device: device, queue: queue, label: "Color RT Allocator for Queue \(queue.index)")
    }
    
    deinit {
        self.textureReferences.deinit()
        self.bufferReferences.deinit()
        self.argumentBufferReferences.deinit()
        self.argumentBufferArrayReferences.deinit()
        
        self.textureWaitEvents.deinit()
        self.bufferWaitEvents.deinit()
        self.argumentBufferWaitEvents.deinit()
        self.argumentBufferArrayWaitEvents.deinit()
    }
    
    public func prepareFrame() {
        self.isExecutingFrame = true
        
        self.textureReferences.prepareFrame()
        self.bufferReferences.prepareFrame()
        self.argumentBufferReferences.prepareFrame()
        self.argumentBufferArrayReferences.prepareFrame()
        
        self.textureWaitEvents.prepareFrame()
        self.bufferWaitEvents.prepareFrame()
        self.argumentBufferWaitEvents.prepareFrame()
        self.argumentBufferArrayWaitEvents.prepareFrame()
    }
    
    public func flushTransientBuffers() {
        #if os(macOS) || targetEnvironment(macCatalyst)
        self.frameManagedBufferAllocator?.flush()
        self.frameManagedWriteCombinedBufferAllocator?.flush()
        #endif
    }
    
    public func registerWindowTexture(for texture: Texture, swapchain: Any) {
        self.windowReferences[texture] = (swapchain as! CAMetalLayer)
    }
    
    func allocatorForTexture(storageMode: MTLStorageMode, flags: ResourceFlags, textureParams: (PixelFormat, MTLTextureUsage)) -> MetalTextureAllocator {
        assert(!flags.contains(.persistent))
        
        if flags.contains(.historyBuffer) {
            assert(storageMode == .private)
            return self.historyBufferAllocator
        }
        
        if #available(macOS 11.0, macCatalyst 14.0, *), storageMode == .memoryless,
           let memorylessAllocator = self.memorylessTextureAllocator {
            return memorylessAllocator
        }
        
        if storageMode != .private {
            return self.stagingTextureAllocator
        } else {
            if textureParams.0.isDepth || textureParams.0.isStencil {
                return self.depthRenderTargetAllocator
            } else {
                return self.colorRenderTargetAllocator
            }
        }
    }
    
    func allocatorForBuffer(length: Int, storageMode: StorageMode, cacheMode: CPUCacheMode, flags: ResourceFlags) -> MetalBufferAllocator {
        assert(!flags.contains(.persistent))
        
        if flags.contains(.historyBuffer) {
            assert(storageMode == .private)
            return self.historyBufferAllocator
        }
        switch storageMode {
        case .private:
            return self.privateAllocator
        case .managed:
            #if os(macOS) || targetEnvironment(macCatalyst)
            if self.device.isAppleSiliconGPU {
                fallthrough
            } else {
                switch cacheMode {
                case .writeCombined:
                    return self.frameManagedWriteCombinedBufferAllocator!
                case .defaultCache:
                    return self.frameManagedBufferAllocator!
                }
            }
            #else
            fallthrough
            #endif
            
        case .shared:
            switch cacheMode {
            case .writeCombined:
                return self.frameSharedWriteCombinedBufferAllocator
            case .defaultCache:
                return self.frameSharedBufferAllocator
            }
        }
    }
    
    func allocatorForArgumentBuffer(flags: ResourceFlags) -> MetalBufferAllocator {
        assert(!flags.contains(.persistent))
        return self.frameArgumentBufferAllocator
    }
    
    static func isAliasedHeapResource(resource: Resource) -> Bool {
        let flags = resource.flags
        let storageMode : StorageMode = resource.storageMode
        
        if flags.contains(.windowHandle) {
            return false
        }
        
        if flags.intersection([.persistent, .historyBuffer]) != [] {
            return false
        }
        
        return storageMode == .private
    }
    
    func computeTextureUsage(_ texture: Texture, isStoredThisFrame: Bool) -> MTLTextureUsageProperties {
        var textureUsage : MTLTextureUsage = []
        
        for usage in texture.usages {
            switch usage.type {
            case .read:
                textureUsage.formUnion(.shaderRead)
            case .write:
                textureUsage.formUnion(.shaderWrite)
            case .readWrite:
                textureUsage.formUnion([.shaderRead, .shaderWrite])
            case  .inputAttachmentRenderTarget:
                textureUsage.formUnion(.renderTarget)
                if RenderBackend.requiresEmulatedInputAttachments {
                    textureUsage.formUnion(.shaderRead)
                }
            case .readWriteRenderTarget, .writeOnlyRenderTarget, .unusedRenderTarget:
                textureUsage.formUnion(.renderTarget)
            default:
                break
            }
        }
        
        if texture.descriptor.usageHint.contains(.pixelFormatView) {
            textureUsage.formUnion(.pixelFormatView)
        }
        
        let canBeMemoryless = self.device.isAppleSiliconGPU &&
            (texture.flags.intersection([.persistent, .historyBuffer]) == [] || (texture.flags.contains(.persistent) && texture.descriptor.usageHint == .renderTarget)) &&
            textureUsage == .renderTarget &&
            !isStoredThisFrame
        let properties = MTLTextureUsageProperties(usage: textureUsage, canBeMemoryless: canBeMemoryless)
        
        assert(properties.usage != .unknown)
        
        return properties
    }
    
    @discardableResult
    public func allocateTexture(_ texture: Texture, forceGPUPrivate: Bool, isStoredThisFrame: Bool) async -> MTLTextureReference {
        let properties = self.computeTextureUsage(texture, isStoredThisFrame: isStoredThisFrame)
        
        if texture.flags.contains(.windowHandle) {
            // Reserve a slot in texture references so we can later insert the texture reference in a thread-safe way, but don't actually allocate anything yet.
            // We can only do this if the texture is only used as a render target.
            self.textureReferences[texture] = MTLTextureReference(windowTexture: ())
            if !properties.usage.isEmpty, properties.usage != .renderTarget {
                // If we use the texture other than as a render target, we need to eagerly allocate it.
                do {
                    try await self.allocateWindowHandleTexture(texture)
                }
                catch {
                    print("Error allocating window handle texture: \(error)")
                }
            }
            return self.textureReferences[texture]!
        }
        
        let descriptor = MTLTextureDescriptor(texture.descriptor, usage: properties.usage, isAppleSiliconGPU: self.device.isAppleSiliconGPU)
        
        if properties.canBeMemoryless, #available(macOS 11.0, macCatalyst 14.0, *) {
            descriptor.storageMode = .memoryless
            descriptor.resourceOptions.formUnion(.storageModeMemoryless)
        }
        
        let allocator = self.allocatorForTexture(storageMode: descriptor.storageMode, flags: texture.flags, textureParams: (texture.descriptor.pixelFormat, properties.usage))
        let (mtlTexture, fences, waitEvent) = allocator.collectTextureWithDescriptor(descriptor)
        
        if let label = texture.label {
            mtlTexture.texture.label = label
        }
        
        if texture._usesPersistentRegistry {
            precondition(texture.flags.contains(.historyBuffer))
            self.persistentRegistry.textureReferences[texture] = mtlTexture
            self.historyBufferResourceWaitEvents[Resource(texture)] = waitEvent
        } else {
            precondition(self.textureReferences[texture] == nil)
            self.textureReferences[texture] = mtlTexture
            self.textureWaitEvents[texture] = waitEvent
        }
        
        
        if !fences.isEmpty {
            self.heapResourceUsageFences[Resource(texture)] = fences
        }
        
        return mtlTexture
    }
    
    @discardableResult
    public func allocateTextureView(_ texture: Texture, resourceMap: FrameResourceMap<Backend>) -> MTLTextureReference {
        assert(texture.flags.intersection([.persistent, .windowHandle, .externalOwnership]) == [])
        
        let mtlTexture : MTLTexture
        let properties = self.computeTextureUsage(texture, isStoredThisFrame: true) // We don't allow texture views to be memoryless.
        
        let baseResource = texture.baseResource!
        switch texture.textureViewBaseInfo! {
        case .buffer(let bufferInfo):
            let mtlBuffer = resourceMap[Buffer(baseResource)!]!
            let descriptor = MTLTextureDescriptor(bufferInfo.descriptor, usage: properties.usage, isAppleSiliconGPU: device.isAppleSiliconGPU)
            mtlTexture = mtlBuffer.resource.makeTexture(descriptor: descriptor, offset: bufferInfo.offset + mtlBuffer.offset, bytesPerRow: bufferInfo.bytesPerRow)!
        case .texture(let textureInfo):
            let baseTexture = resourceMap[Texture(baseResource)!]!
            if textureInfo.levels.lowerBound == -1 || textureInfo.slices.lowerBound == -1 {
                assert(textureInfo.levels.lowerBound == -1 && textureInfo.slices.lowerBound == -1)
                mtlTexture = baseTexture.texture.makeTextureView(pixelFormat: MTLPixelFormat(textureInfo.pixelFormat))!
            } else {
                mtlTexture = baseTexture.texture.makeTextureView(pixelFormat: MTLPixelFormat(textureInfo.pixelFormat), textureType: MTLTextureType(textureInfo.textureType), levels: textureInfo.levels, slices: textureInfo.slices)!
            }
        }
        
        assert(self.textureReferences[texture] == nil)
        let textureReference = MTLTextureReference(texture: Unmanaged.passRetained(mtlTexture))
        self.textureReferences[texture] = textureReference
        return textureReference
    }
    
    @discardableResult
    public func allocateWindowHandleTexture(_ texture: Texture) async throws -> MTLTextureReference {
        precondition(texture.flags.contains(.windowHandle))
        
        // The texture reference should always be present but the texture itself might not be.
        if self.textureReferences[texture]!._texture == nil {
            do {
                guard let windowReference = self.windowReferences.removeValue(forKey: texture),
                      let mtlDrawable = windowReference.nextDrawable() else {
                    throw RenderTargetTextureError.unableToRetrieveDrawable(texture)
                }
                
                let drawableTexture = mtlDrawable.texture
                if drawableTexture.width >= texture.descriptor.size.width && drawableTexture.height >= texture.descriptor.size.height {
                    self.frameDrawables.append((texture, .success(mtlDrawable)))
                    self.textureReferences[texture]!._texture = Unmanaged.passRetained(drawableTexture)
                    if let queue = self.textureReferences[texture]!.disposeWaitQueue {
                        CommandEndActionManager.enqueue(action: .release(.fromOpaque(self.textureReferences[texture]!._texture.toOpaque())), after: self.textureReferences[texture]!.disposeWaitValue, on: queue)
                    }
                } else {
                    // The window was resized to be smaller than the texture size. We can't render directly to that, so instead
                    // throw an error.
                    throw RenderTargetTextureError.invalidSizeDrawable(texture, requestedSize: Size(width: texture.descriptor.width, height: texture.descriptor.height), drawableSize: Size(width: drawableTexture.width, height: drawableTexture.height))
                }
            } catch let error as RenderTargetTextureError {
                self.frameDrawables.append((texture, .failure(error)))
                throw error
            }
        }
        
        return self.textureReferences[texture]!
    }
    
    @discardableResult
    public func allocateBuffer(_ buffer: Buffer, forceGPUPrivate: Bool) -> MTLBufferReference? {
        var options = MTLResourceOptions(storageMode: buffer.descriptor.storageMode, cacheMode: buffer.descriptor.cacheMode, isAppleSiliconGPU: device.isAppleSiliconGPU)
        if buffer.descriptor.usageHint.contains(.textureView) {
            options.remove(.substrateTrackedHazards) // FIXME: workaround for a bug in Metal where setting hazardTrackingModeUntracked on a MTLTextureDescriptor doesn't stick
        }
        

        let allocator = self.allocatorForBuffer(length: buffer.descriptor.length, storageMode: buffer.descriptor.storageMode, cacheMode: buffer.descriptor.cacheMode, flags: buffer.flags)
        let (mtlBuffer, fences, waitEvent) = allocator.collectBufferWithLength(buffer.descriptor.length, options: options)
        
        if let label = buffer.label {
            if allocator is MetalTemporaryBufferAllocator {
                mtlBuffer.buffer.addDebugMarker(label, range: mtlBuffer.offset..<(mtlBuffer.offset + buffer.descriptor.length))
            } else {
                mtlBuffer.buffer.label = label
            }
        }
        
        if buffer._usesPersistentRegistry {
            precondition(buffer.flags.contains(.historyBuffer))
            self.persistentRegistry.bufferReferences[buffer] = mtlBuffer
            self.historyBufferResourceWaitEvents[Resource(buffer)] = waitEvent
        } else {
            precondition(self.bufferReferences[buffer] == nil)
            self.bufferReferences[buffer] = mtlBuffer
            self.bufferWaitEvents[buffer] = waitEvent
        }
        
        if !fences.isEmpty {
            self.heapResourceUsageFences[Resource(buffer)] = fences
        }
        
        return mtlBuffer
    }
    
    @discardableResult
    public func allocateBufferIfNeeded(_ buffer: Buffer, forceGPUPrivate: Bool) -> MTLBufferReference {
        if let mtlBuffer = self.bufferReferences[buffer] {
            return mtlBuffer
        }
        return self.allocateBuffer(buffer, forceGPUPrivate: forceGPUPrivate)!
    }
    
    
    @discardableResult
    public func allocateTextureIfNeeded(_ texture: Texture, forceGPUPrivate: Bool, isStoredThisFrame: Bool) async -> MTLTextureReference {
        if let mtlTexture = self.textureReferences[texture] {
            assert(mtlTexture.texture.pixelFormat == MTLPixelFormat(texture.descriptor.pixelFormat))
            return mtlTexture
        }
        return await self.allocateTexture(texture, forceGPUPrivate: forceGPUPrivate, isStoredThisFrame: isStoredThisFrame)
    }
    
    func allocateArgumentBufferStorage<A : ResourceProtocol>(for argumentBuffer: A, encodedLength: Int) -> (MTLBufferReference, [FenceDependency], ContextWaitEvent) {
//        #if os(macOS)
//        let options : MTLResourceOptions = [.storageModeManaged, .substrateTrackedHazards]
//        #else
        let options : MTLResourceOptions = [.storageModeShared, .substrateTrackedHazards]
//        #endif
        
        let allocator = self.allocatorForArgumentBuffer(flags: argumentBuffer.flags)
        return allocator.collectBufferWithLength(encodedLength, options: options)
    }
    
    @discardableResult
    func allocateArgumentBufferIfNeeded(_ argumentBuffer: ArgumentBuffer) -> MTLBufferReference {
        if let baseArray = argumentBuffer.sourceArray {
            _ = self.allocateArgumentBufferArrayIfNeeded(baseArray)
            return self.argumentBufferReferences[argumentBuffer]!
        }
        if let mtlArgumentBuffer = self.argumentBufferReferences[argumentBuffer] {
            return mtlArgumentBuffer
        }
        
        let argEncoder = Unmanaged<MetalArgumentEncoder>.fromOpaque(argumentBuffer.encoder!).takeUnretainedValue()
        
        var allocationLength = argumentBuffer.allocationLength
        if allocationLength == .max {
            allocationLength = argEncoder.encoder.encodedLength
        }
        
        let (storage, fences, waitEvent) = self.allocateArgumentBufferStorage(for: argumentBuffer, encodedLength: allocationLength)
        assert(fences.isEmpty)
        
        self.argumentBufferReferences[argumentBuffer] = storage
        self.argumentBufferWaitEvents[argumentBuffer] = waitEvent
        
        return storage
    }
    
    @discardableResult
    func allocateArgumentBufferArrayIfNeeded(_ argumentBufferArray: ArgumentBufferArray) -> MTLBufferReference {
        if let mtlArgumentBuffer = self.argumentBufferArrayReferences[argumentBufferArray] {
            return mtlArgumentBuffer
        }
        
        let argEncoder = Unmanaged<MetalArgumentEncoder>.fromOpaque(argumentBufferArray._bindings.first(where: { $0?.encoder != nil })!!.encoder!).takeUnretainedValue()
        let (storage, fences, waitEvent) = self.allocateArgumentBufferStorage(for: argumentBufferArray, encodedLength: argEncoder.encoder.encodedLength * argumentBufferArray._bindings.count)
        assert(fences.isEmpty)
        
        for (i, argumentBuffer) in argumentBufferArray._bindings.enumerated() {
            guard let argumentBuffer = argumentBuffer else { continue }
            
            let localStorage = MTLBufferReference(buffer: storage._buffer, offset: storage.offset + i * argEncoder.encoder.encodedLength)
            self.argumentBufferReferences[argumentBuffer] = localStorage
            self.argumentBufferWaitEvents[argumentBuffer] = waitEvent
        }
        
        self.argumentBufferArrayReferences[argumentBufferArray] = storage
        self.argumentBufferArrayWaitEvents[argumentBufferArray] = waitEvent
        
        return storage
    }
    
    public func importExternalResource(_ resource: Resource, backingResource: Any) {
        self.prepareFrame()
        if let texture = Texture(resource) {
            self.textureReferences[texture] = MTLTextureReference(texture: Unmanaged.passRetained(backingResource as! MTLTexture))
        } else if let buffer = Buffer(resource) {
            self.bufferReferences[buffer] = MTLBufferReference(buffer: Unmanaged.passRetained(backingResource as! MTLBuffer), offset: 0)
        }
    }
    
    public subscript(texture: Texture) -> MTLTextureReference? {
        return self.textureReferences[texture]
    }

    public subscript(buffer: Buffer) -> MTLBufferReference? {
        return self.bufferReferences[buffer]
    }

    public subscript(argumentBuffer: ArgumentBuffer) -> MTLBufferReference? {
        return self.argumentBufferReferences[argumentBuffer]
    }

    public subscript(argumentBufferArray: ArgumentBufferArray) -> MTLBufferReference? {
        return self.argumentBufferArrayReferences[argumentBufferArray]
    }
    
    public func withHeapAliasingFencesIfPresent(for resourceHandle: Resource.Handle, perform: (inout [FenceDependency]) -> Void) {
        let resource = Resource(handle: resourceHandle)
        
        perform(&self.heapResourceUsageFences[resource, default: []])
    }
    
    func setDisposalFences(on resource: Resource, to fences: [FenceDependency]) {
        assert(Self.isAliasedHeapResource(resource: resource))
        self.heapResourceDisposalFences[resource] = fences
    }
    
    func disposeTexture(_ texture: Texture, waitEvent: ContextWaitEvent) {
        // We keep the reference around until the end of the frame since allocation/disposal is all processed ahead of time.
        
        let textureRef : MTLTextureReference?
        if texture._usesPersistentRegistry {
            precondition(texture.flags.contains(.historyBuffer))
            textureRef = self.persistentRegistry.textureReferences[texture]
            _ = textureRef?._texture.retain() // since the persistent registry releases its resources unconditionally on dispose, but we want the allocator to have ownership of it.
        } else {
            textureRef = self.textureReferences[texture]
        }
        
        if let mtlTexture = textureRef {
            if texture.flags.contains(.windowHandle) || texture.isTextureView {
                if let texture = mtlTexture._texture {
                    CommandEndActionManager.enqueue(action: .release(.fromOpaque(texture.toOpaque())), after: waitEvent.waitValue, on: self.queue)
                } else {
                    self.textureReferences[texture]?.disposeWaitValue = waitEvent.waitValue
                    self.textureReferences[texture]?.disposeWaitQueue = self.queue
                }
                return
            }
            
            var fences : [FenceDependency] = []
            if Self.isAliasedHeapResource(resource: Resource(texture)) {
                fences = self.heapResourceDisposalFences[Resource(texture)] ?? []
            }
            
            let allocator = self.allocatorForTexture(storageMode: mtlTexture.texture.storageMode, flags: texture.flags, textureParams: (texture.descriptor.pixelFormat, mtlTexture.texture.usage))
            allocator.depositTexture(mtlTexture, fences: fences, waitEvent: waitEvent)
        }
    }
    
    func disposeBuffer(_ buffer: Buffer, waitEvent: ContextWaitEvent) {
        // We keep the reference around until the end of the frame since allocation/disposal is all processed ahead of time.
        
        let bufferRef : MTLBufferReference?
        if buffer._usesPersistentRegistry {
            precondition(buffer.flags.contains(.historyBuffer))
            bufferRef = self.persistentRegistry.bufferReferences[buffer]
            _ = bufferRef?._buffer.retain() // since the persistent registry releases its resources unconditionally on dispose, but we want the allocator to have ownership of it.
        } else {
            bufferRef = self.bufferReferences[buffer]
        }
        
        if let mtlBuffer = bufferRef {
            var fences : [FenceDependency] = []
            if Self.isAliasedHeapResource(resource: Resource(buffer)) {
                fences = self.heapResourceDisposalFences[Resource(buffer)] ?? []
            }
            
            let allocator = self.allocatorForBuffer(length: buffer.descriptor.length, storageMode: buffer.descriptor.storageMode, cacheMode: buffer.descriptor.cacheMode, flags: buffer.flags)
            allocator.depositBuffer(mtlBuffer, fences: fences, waitEvent: waitEvent)
        }
    }
    
    func disposeArgumentBuffer(_ buffer: ArgumentBuffer, waitEvent: ContextWaitEvent) {
        if let mtlBuffer = self.argumentBufferReferences[buffer] {
            let allocator = self.allocatorForArgumentBuffer(flags: buffer.flags)
            allocator.depositBuffer(mtlBuffer, fences: [], waitEvent: waitEvent)
        }
    }
    
    func disposeArgumentBufferArray(_ buffer: ArgumentBufferArray, waitEvent: ContextWaitEvent) {
        if let mtlBuffer = self.argumentBufferArrayReferences[buffer] {
            let allocator = self.allocatorForArgumentBuffer(flags: buffer.flags)
            allocator.depositBuffer(mtlBuffer, fences: [], waitEvent: waitEvent)
        }
    }
    
    func clearDrawables() {
        self.frameDrawables.removeAll(keepingCapacity: true)
    }
    
    func makeTransientAllocatorsPurgeable() {
        if self.isExecutingFrame { return }
        
        self.stagingTextureAllocator.makePurgeable()
        self.privateAllocator.makePurgeable()
        self.historyBufferAllocator.makePurgeable()
        
        self.colorRenderTargetAllocator.makePurgeable()
        self.depthRenderTargetAllocator.makePurgeable()
        
        self.frameSharedBufferAllocator.makePurgeable()
        self.frameSharedWriteCombinedBufferAllocator.makePurgeable()
        
        #if os(macOS) || targetEnvironment(macCatalyst)
        self.frameManagedBufferAllocator?.makePurgeable()
        self.frameManagedWriteCombinedBufferAllocator?.makePurgeable()
        #endif
        
        self.frameArgumentBufferAllocator.makePurgeable()
    }
    
    func cycleFrames() {
        // Clear all transient resources at the end of the frame.
        
        self.textureReferences.removeAll()
        self.bufferReferences.removeAll()
        self.argumentBufferReferences.removeAll()
        self.argumentBufferArrayReferences.removeAll()
        
        self.heapResourceUsageFences.removeAll(keepingCapacity: true)
        self.heapResourceDisposalFences.removeAll(keepingCapacity: true)
        
        self.stagingTextureAllocator.cycleFrames()
        self.privateAllocator.cycleFrames()
        self.historyBufferAllocator.cycleFrames()
        
        self.colorRenderTargetAllocator.cycleFrames()
        self.depthRenderTargetAllocator.cycleFrames()
        
        self.frameSharedBufferAllocator.cycleFrames()
        self.frameSharedWriteCombinedBufferAllocator.cycleFrames()
        
        #if os(macOS) || targetEnvironment(macCatalyst)
        self.frameManagedBufferAllocator?.cycleFrames()
        self.frameManagedWriteCombinedBufferAllocator?.cycleFrames()
        #endif
        self.memorylessTextureAllocator?.cycleFrames()
        
        self.frameArgumentBufferAllocator.cycleFrames()
        
        self.isExecutingFrame = false
    }
}

#endif // canImport(Metal)
