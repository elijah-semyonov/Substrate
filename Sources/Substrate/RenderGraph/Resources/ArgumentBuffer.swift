//
//  ArgumentEncoder.swift
//  RenderAPI
//
//  Created by Thomas Roughton on 22/02/18.
//

import Foundation
import SubstrateUtilities
import Atomics

public protocol FunctionArgumentKey {
    var stringValue : String { get }
    func bindingPath(arrayIndex: Int, argumentBufferPath: ResourceBindingPath?) -> ResourceBindingPath?
}

extension RawRepresentable where Self.RawValue == String {
    public var stringValue : String {
        return self.rawValue
    }
}

#if canImport(Metal)
@preconcurrency import Metal

public struct MetalIndexedFunctionArgument : FunctionArgumentKey {
    public var type: MTLArgumentType
    public var index : Int
    public var stages : RenderStages
    
    public init(type: MTLArgumentType, index: Int, stages: RenderStages) {
        self.type = type
        self.index = index
        self.stages = stages
    }
    
    public var stringValue : String {
        return "\(type)_arg\(index)"
    }
    
    public func bindingPath(arrayIndex: Int, argumentBufferPath: ResourceBindingPath?) -> ResourceBindingPath? {
        return ResourceBindingPath(stages: MTLRenderStages(self.stages), type: self.type, argumentBufferIndex: nil, index: self.index + arrayIndex)
    }
}
#endif

extension FunctionArgumentKey {
    
    public func bindingPath(arrayIndex: Int, argumentBufferPath: ResourceBindingPath?) -> ResourceBindingPath? {
        return nil
    }
    
    func bindingPath(argumentBufferPath: ResourceBindingPath?, arrayIndex: Int, pipelineReflection: PipelineReflection) -> ResourceBindingPath? {
        return self.bindingPath(arrayIndex: arrayIndex, argumentBufferPath: argumentBufferPath) ?? pipelineReflection.bindingPath(argumentName: self.stringValue, arrayIndex: arrayIndex, argumentBufferPath: argumentBufferPath)
    }
    
    func computedBindingPath(pipelineReflection: PipelineReflection) -> ResourceBindingPath? {
        return self.bindingPath(arrayIndex: 0, argumentBufferPath: nil) ?? pipelineReflection.bindingPath(argumentName: self.stringValue, arrayIndex: 0, argumentBufferPath: nil)
    }
}

extension String : FunctionArgumentKey {
    public var stringValue : String {
        return self
    }
}

public protocol ArgumentBufferEncodable {
    static var activeStages : RenderStages { get }
    
    static var argumentBufferDescriptor: ArgumentBufferDescriptor { get }
    
    mutating func encode(into argBuffer: ArgumentBuffer, setIndex: Int, bindingEncoder: ResourceBindingEncoder?)
}

@available(*, deprecated, renamed: "ArgumentBuffer")
public typealias _ArgumentBuffer = ArgumentBuffer

@available(*, deprecated, renamed: "ArgumentBuffer")
public typealias _ArgumentBufferArray = ArgumentBufferArray

public struct ArgumentDescriptor: Hashable, Sendable {
    public enum ArgumentResourceType: Hashable, Sendable {
        case inlineData(type: DataType)
        case constantBuffer(alignment: Int = 0)
        case storageBuffer
        case texture(type: TextureType)
        case sampler
        case accelerationStructure
    }
    
    public var resourceType: ArgumentResourceType // VkDescriptorSetLayoutBinding.descriptorType
    public var index: Int // VkDescriptorSetLayoutBinding.binding
    public var arrayLength: Int // VkDescriptorSetLayoutBinding.descriptorCount
    public var accessType: ResourceAccessType // VkDescriptorSetLayoutBinding.descriptorType
    
    public init(resourceType: ArgumentResourceType, index: Int? = nil, arrayLength: Int = 1, accessType: ResourceAccessType = .read) {
        self.resourceType = resourceType
        self.index = index ?? -1
        self.arrayLength = arrayLength
        self.accessType = accessType
    }
}

extension ArgumentDescriptor.ArgumentResourceType: CustomStringConvertible {
    public var description: String {
        switch self {
        case .inlineData(let type):
            return "inlineData(type: .\(type))"
        case .constantBuffer(let alignment):
            return "constantBuffer(alignment: \(alignment))"
        case .storageBuffer:
            return "storageBuffer"
        case .texture(let type):
            let typeString = String(describing: type)
            return "texture(type: .\(typeString))"
        case .sampler:
            return "sampler"
        case .accelerationStructure:
            return "accelerationStructure"
        }
    }
}

public struct ArgumentBufferDescriptor: Hashable, Sendable {
    public var arguments: [ArgumentDescriptor]
    
    @inlinable
    public init(arguments: [ArgumentDescriptor]) {
        self.arguments = arguments
        
        var nextIndex = 0
        for i in self.arguments.indices {
            precondition(self.arguments[i].index < 0 || self.arguments[i].index >= nextIndex, "Arguments must be in order of ascending index.")
            self.arguments[i].index = max(self.arguments[i].index, nextIndex)
            nextIndex = self.arguments[i].index + 1
        }
    }
}

public struct ArgumentBuffer : ResourceProtocol {
    @usableFromInline let _handle : UnsafeRawPointer
    @inlinable public var handle : Handle { return UInt64(UInt(bitPattern: _handle)) }
    
    public enum ArgumentResource {
        case buffer(Buffer, offset: Int)
        case texture(Texture)
        case accelerationStructure(AccelerationStructure)
        case visibleFunctionTable(VisibleFunctionTable)
        case intersectionFunctionTable(IntersectionFunctionTable)
        case sampler(SamplerDescriptor)
        // Where offset is the source offset in the source Data.
        case bytes(offset: Int, length: Int)
        
        public var resource: Resource? {
            switch self {
            case .buffer(let buffer, _):
                return Resource(buffer)
            case .texture(let texture):
                return Resource(texture)
            case .accelerationStructure(let structure):
                return Resource(structure)
            case .visibleFunctionTable(let table):
                return Resource(table)
            case .intersectionFunctionTable(let table):
                return Resource(table)
            case .sampler, .bytes:
                return nil
            }
        }
        
        public var activeRangeOffsetIntoResource: Int {
            switch self {
            case .buffer(_, let offset):
                return offset
            default:
                return 0
            }
        }
    }
    
    public init(handle: Handle) {
        assert(Resource(handle: handle).type == .argumentBuffer)
        self._handle = UnsafeRawPointer(bitPattern: UInt(handle))!
    }
   
    public init(bindingPath: ResourceBindingPath, pipelineReflection: PipelineReflection, renderGraph: RenderGraph? = nil) {
        guard let renderGraph = renderGraph ?? RenderGraph.activeRenderGraph else {
            fatalError("The RenderGraph must be specified for transient resources created outside of a render pass' execute() method.")
        }
        guard let encoder = pipelineReflection.argumentBufferEncoder(at: bindingPath, currentEncoder: nil) else {
            preconditionFailure("Binding path \(bindingPath) does not represent an argument buffer binding in the provided pipeline reflection.")
        }
        precondition(renderGraph.transientRegistryIndex >= 0, "Transient resources are not supported on the RenderGraph \(renderGraph)")
        
        self = TransientArgumentBufferRegistry.instances[renderGraph.transientRegistryIndex].allocate(descriptor: .init(arguments: []), flags: [])
        
        assert(self.encoder == nil)
        _ = self.replaceEncoder(with: encoder, expectingCurrentValue: nil)
    }
    
    public init(descriptor: ArgumentBufferDescriptor, renderGraph: RenderGraph? = nil, flags: ResourceFlags = []) {
        precondition(!flags.contains(.historyBuffer), "Argument Buffers cannot be used as history buffers.")
        
        guard let encoder = RenderBackend._backend.argumentBufferEncoder(for: descriptor) else {
            preconditionFailure("Argument buffer encoder couldn't be created.")
        }
        
        if flags.contains(.persistent) {
            self = PersistentArgumentBufferRegistry.instance.allocate(descriptor: descriptor, heap: nil, flags: flags)
        } else {
            guard let renderGraph = renderGraph ?? RenderGraph.activeRenderGraph else {
                fatalError("The RenderGraph must be specified for transient resources created outside of a render pass' execute() method.")
            }
            precondition(renderGraph.transientRegistryIndex >= 0, "Transient resources are not supported on the RenderGraph \(renderGraph)")
            
            self = TransientArgumentBufferRegistry.instances[renderGraph.transientRegistryIndex].allocate(descriptor: descriptor, flags: flags)
        }
        
        assert(self.encoder == nil)
        _ = self.replaceEncoder(with: encoder, expectingCurrentValue: nil)
    }
    
    public init<A : ArgumentBufferEncodable>(encoding arguments: A, setIndex: Int, renderGraph: RenderGraph? = nil, flags: ResourceFlags = []) {
        self.init(descriptor: A.argumentBufferDescriptor, renderGraph: renderGraph, flags: flags)

#if !SUBSTRATE_DISABLE_AUTOMATIC_LABELS
    self.label = "Descriptor Set for \(String(reflecting: A.self))"
#endif
        
        var arguments = arguments
        arguments.encode(into: self, setIndex: setIndex, bindingEncoder: nil)
    }
    
    init(flags: ResourceFlags = [], sourceArray: ArgumentBufferArray) {
        if flags.contains(.persistent) {
            self = PersistentArgumentBufferRegistry.instance.allocate(flags: flags, sourceArray: sourceArray)
        } else {
            self = TransientArgumentBufferRegistry.instances[sourceArray.transientRegistryIndex].allocate(flags: flags, sourceArray: sourceArray)
        }
        
        assert(self.encoder == nil)
    }
    
    public var descriptor: ArgumentBufferDescriptor {
        _read {
            yield self.pointer(for: \.descriptors).pointee
        }
    }
    
    public var sourceArray : ArgumentBufferArray? {
        if self.flags.contains(.resourceView) {
            return self[\.sourceArrays]
        }
        return nil
    }
    
    public var stateFlags: ResourceStateFlags {
        get {
            return []
        }
        nonmutating set {
        }
    }
    
    public var encoder : UnsafeRawPointer? {
        get {
            return UnsafeRawPointer.AtomicOptionalRepresentation.atomicLoad(at: self.pointer(for: \.encoders), ordering: .relaxed)
        }
    }
    
    /// Updates the encoder to also support encoding to bindingPath.
    func updateEncoder(pipelineReflection: PipelineReflection, bindingPath: ResourceBindingPath) {
        var hasSetEncoder = false
        repeat {
            let currentEncoder = self.encoder
            let newEncoder = pipelineReflection.argumentBufferEncoder(at: bindingPath, currentEncoder: currentEncoder)!
            hasSetEncoder = (newEncoder == currentEncoder) || self.replaceEncoder(with: newEncoder, expectingCurrentValue: currentEncoder)
        } while !hasSetEncoder
    }
    
    /// Allows us to perform a compare-and-swap on the argument buffer encoder.
    func replaceEncoder(with newEncoder: UnsafeRawPointer, expectingCurrentValue: UnsafeRawPointer?) -> Bool {
        return UnsafeRawPointer.AtomicOptionalRepresentation.atomicWeakCompareExchange(expected: expectingCurrentValue, desired: newEncoder, at: self.pointer(for: \.encoders), successOrdering: .relaxed, failureOrdering: .relaxed).exchanged
    }
    
    /// A limit for the maximum buffer size that may be allocated by the backend for this argument buffer.
    /// Useful for capping the length of bindless arrays to the actually used capacity. The encoder length is used if this is equal to .max, which is the default.
    public var allocationLength : Int {
        get {
            return self.pointer(for: \.allocationLengths).pointee
        }
        nonmutating set {
            self.pointer(for: \.allocationLengths).pointee = newValue
        }
    }
    
    public var enqueuedBindings : ExpandingBuffer<(FunctionArgumentKey, Int, ArgumentBuffer.ArgumentResource)> {
        _read {
            yield self.pointer(for: \.enqueuedBindings).pointee
        }
    }
    
    public var bindings : ExpandingBuffer<(ResourceBindingPath, ArgumentBuffer.ArgumentResource)> {
        _read {
            yield self.pointer(for: \.bindings).pointee
        }
    }
    
    public var storageMode: StorageMode {
        return .shared
    }
    
    // Thread-safe
    func translateEnqueuedBindings(_ closure: (FunctionArgumentKey, Int, ArgumentBuffer.ArgumentResource) -> ResourceBindingPath?) {
        
        func translateBindings() {
            var i = 0
            while i < self.enqueuedBindings.count {
                let (key, arrayIndex, binding) = self.enqueuedBindings[i]
                if let bindingPath = closure(key, arrayIndex, binding) {
                    self.enqueuedBindings.remove(at: i)
                    self.bindings.append((bindingPath, binding))
                } else {
                    i += 1
                }
            }
        }

        if self._usesPersistentRegistry {
            PersistentArgumentBufferRegistry.instance.lock.withLock {
                translateBindings()
            }
        } else {
            TransientArgumentBufferRegistry.instances[self.transientRegistryIndex].lock.withLock {
                translateBindings()
            }
        }
    }
    
    public func _bytes(offset: Int) -> UnsafeRawPointer {
        if self._usesPersistentRegistry {
            return self.pointer(for: \.inlineDataStorage)!.pointee.withUnsafeBytes { return $0.baseAddress! + offset }
        } else {
            return UnsafeRawPointer(TransientArgumentBufferRegistry.instances[self.transientRegistryIndex].inlineDataAllocator.buffer!) + offset
        }
    }
    
    /// returns the offset in bytes into the buffer's storage
    public func _copyBytes(_ bytes: UnsafeRawPointer, length: Int) -> Int {
        if self._usesPersistentRegistry {
            return PersistentArgumentBufferRegistry.instance.lock.withLock {
                let inlineDataStorage = self.pointer(for: \.inlineDataStorage)!
                let offset = inlineDataStorage.pointee.count
                inlineDataStorage.pointee.append(bytes.assumingMemoryBound(to: UInt8.self), count: length)
                return offset
            }
        } else {
            return TransientArgumentBufferRegistry.instances[self.transientRegistryIndex].lock.withLock {
                let offset = TransientArgumentBufferRegistry.instances[self.transientRegistryIndex].inlineDataAllocator.count
                TransientArgumentBufferRegistry.instances[self.transientRegistryIndex].inlineDataAllocator.append(from: bytes.assumingMemoryBound(to: UInt8.self), count: length)
                return offset
            }
        }
    }
    
    public func setBuffer(_ buffer: Buffer?, offset: Int, key: FunctionArgumentKey, arrayIndex: Int = 0) {
        guard let buffer = buffer else { return }
        
        assert(!self.flags.contains(.persistent) || buffer.flags.contains(.persistent), "A persistent argument buffer can only contain persistent resources.")
        self.enqueuedBindings.append(
            (key, arrayIndex, .buffer(buffer, offset: offset))
        )
    }
    
    public func setTexture(_ texture: Texture, key: FunctionArgumentKey, arrayIndex: Int = 0) {
        assert(!self.flags.contains(.persistent) || texture.flags.contains(.persistent), "A persistent argument buffer can only contain persistent resources.")
        self.enqueuedBindings.append(
            (key, arrayIndex, .texture(texture))
        )
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    public func setAccelerationStructure(_ structure: AccelerationStructure, key: FunctionArgumentKey, arrayIndex: Int = 0) {
        assert(!self.flags.contains(.persistent) || structure.flags.contains(.persistent), "A persistent argument buffer can only contain persistent resources.")
        self.enqueuedBindings.append(
            (key, arrayIndex, .accelerationStructure(structure))
        )
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    public func setVisibleFunctionTable(_ table: VisibleFunctionTable, key: FunctionArgumentKey, arrayIndex: Int = 0) {
        assert(!self.flags.contains(.persistent) || table.flags.contains(.persistent), "A persistent argument buffer can only contain persistent resources.")
        self.enqueuedBindings.append(
            (key, arrayIndex, .visibleFunctionTable(table))
        )
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    public func setIntersectionFunctionTable(_ table: IntersectionFunctionTable, key: FunctionArgumentKey, arrayIndex: Int = 0) {
        assert(!self.flags.contains(.persistent) || table.flags.contains(.persistent), "A persistent argument buffer can only contain persistent resources.")
        self.enqueuedBindings.append(
            (key, arrayIndex, .intersectionFunctionTable(table))
        )
    }
    
    @inlinable
    public func setSampler(_ sampler: SamplerDescriptor, key: FunctionArgumentKey, arrayIndex: Int = 0) {
        self.enqueuedBindings.append(
            (key, arrayIndex, .sampler(sampler))
        )
    }
    
    public func setValue<T>(_ value: T, key: FunctionArgumentKey, arrayIndex: Int = 0) {
        assert(_isPOD(T.self), "Only POD types should be used with setValue.")
        
        var value = value
        withUnsafeBytes(of: &value) { bufferPointer in
            self.setBytes(bufferPointer.baseAddress!, length: bufferPointer.count, for: key, arrayIndex: arrayIndex)
        }
    }
    
    public func setValue<T : ResourceProtocol>(_ value: T, key: FunctionArgumentKey, arrayIndex: Int = 0) {
        preconditionFailure("setValue should not be used with resources; use setBuffer or setTexture instead.")
    }
    
    public func setBytes(_ bytes: UnsafeRawPointer, length: Int, for key: FunctionArgumentKey, arrayIndex: Int = 0) {
        let currentOffset = self._copyBytes(bytes, length: length)
        self.enqueuedBindings.append(
            (key, arrayIndex, .bytes(offset: currentOffset, length: length))
        )
    }
    
    public static var resourceType: ResourceType {
        return .argumentBuffer
    }
}

extension ArgumentBuffer {
    
    public func setBuffers(_ buffers: [Buffer], offsets: [Int], keys: [FunctionArgumentKey]) {
        for (buffer, (offset, key)) in zip(buffers, zip(offsets, keys)) {
            self.setBuffer(buffer, offset: offset, key: key)
        }
    }
    
    public func setTextures(_ textures: [Texture], keys: [FunctionArgumentKey]) {
        for (texture, key) in zip(textures, keys) {
            self.setTexture(texture, key: key)
        }
    }
    
    public func setSamplers(_ samplers: [SamplerDescriptor], keys: [FunctionArgumentKey]) {
        for (sampler, key) in zip(samplers, keys) {
            self.setSampler(sampler, key: key)
        }
    }
}

extension ArgumentBuffer: ResourceProtocolImpl {
    typealias SharedProperties = ArgumentBufferProperties
    typealias TransientProperties = EmptyProperties<ArgumentBufferDescriptor>
    typealias PersistentProperties = ArgumentBufferProperties.PersistentArgumentBufferProperties
    
    static func transientRegistry(index: Int) -> TransientArgumentBufferRegistry? {
        return TransientArgumentBufferRegistry.instances[index]
    }
    
    static var persistentRegistry: PersistentRegistry<Self> { PersistentArgumentBufferRegistry.instance }
    
    typealias Descriptor = ArgumentBufferDescriptor
}


extension ArgumentBuffer: CustomStringConvertible {
    public var description: String {
        return "ArgumentBuffer(handle: \(self.handle)) { \(self.label.map { "label: \($0), "} ?? "")bindings: \(self.bindings), enqueuedBindings: \(self.enqueuedBindings), flags: \(self.flags) }"
    }
}

public struct TypedArgumentBuffer<K : FunctionArgumentKey> : ResourceProtocol {
    public let argumentBuffer : ArgumentBuffer
    
    public init?(_ resource: Resource) {
        guard let argumentBuffer = ArgumentBuffer(resource) else { return nil }
        self.argumentBuffer = argumentBuffer
    }
    
    public init(_ argumentBuffer: ArgumentBuffer) {
        self.argumentBuffer = argumentBuffer
    }
    
    public init(handle: Handle) {
        self.argumentBuffer = ArgumentBuffer(handle: handle)
    }
    
    public init(descriptor: ArgumentBufferDescriptor, renderGraph: RenderGraph? = nil, flags: ResourceFlags = []) {
        self.argumentBuffer = ArgumentBuffer(descriptor: descriptor, renderGraph: renderGraph, flags: flags)
#if !SUBSTRATE_DISABLE_AUTOMATIC_LABELS
        self.argumentBuffer.label = "Argument Buffer \(K.self)"
#endif
    }
    
    public func dispose() {
        self.argumentBuffer.dispose()
    }
    
    @inlinable
    public var handle: Resource.Handle {
        return self.argumentBuffer.handle
    }
    
    public var stateFlags: ResourceStateFlags {
        get {
            return self.argumentBuffer.stateFlags
        }
        nonmutating set {
            self.argumentBuffer.stateFlags = newValue
        }
    }
    
    public var flags : ResourceFlags {
        return self.argumentBuffer.flags
    }
    
    public var sourceArray : TypedArgumentBufferArray<K>? {
        return self.argumentBuffer.sourceArray.map { TypedArgumentBufferArray(handle: $0.handle) }
    }
    
    public var isKnownInUse: Bool {
        return self.argumentBuffer.isKnownInUse
    }
    
    public var hasPendingRenderGraph: Bool {
        return self.argumentBuffer.hasPendingRenderGraph
    }
    
    public func markAsUsed(activeRenderGraphMask: ActiveRenderGraphMask) {
        self.argumentBuffer.markAsUsed(activeRenderGraphMask: activeRenderGraphMask)
    }
    
    public var isValid: Bool {
        return self.argumentBuffer.isValid
    }
    
    public var label : String? {
        get {
            return self.argumentBuffer.label
        }
        nonmutating set {
            self.argumentBuffer.label = newValue
        }
    }
    
    public var usages: ChunkArray<ResourceUsage> {
        get {
            return self.argumentBuffer.usages
        }
        nonmutating set {
            self.argumentBuffer.usages = newValue
        }
    }
    
    public var resourceForUsageTracking: Resource {
        return self.argumentBuffer.resourceForUsageTracking
    }
    
    public var storageMode: StorageMode {
        return self.argumentBuffer.storageMode
    }
    
    public func setBuffer(_ buffer: Buffer?, offset: Int, key: K, arrayIndex: Int = 0) {
        guard let buffer = buffer else { return }
        
        assert(!self.flags.contains(.persistent) || buffer.flags.contains(.persistent), "A persistent argument buffer can only contain persistent resources.")
        self.argumentBuffer.enqueuedBindings.append(
            (key, arrayIndex, .buffer(buffer, offset: offset))
        )
    }
    
    public func setTexture(_ texture: Texture, key: K, arrayIndex: Int = 0) {
        assert(!self.flags.contains(.persistent) || texture.flags.contains(.persistent), "A persistent argument buffer can only contain persistent resources.")
        self.argumentBuffer.enqueuedBindings.append(
            (key, arrayIndex, .texture(texture))
        )
    }
    
    public func setSampler(_ sampler: SamplerDescriptor, key: K, arrayIndex: Int = 0) {
        self.argumentBuffer.enqueuedBindings.append(
            (key, arrayIndex, .sampler(sampler))
        )
    }

    public func setValue<T : ResourceProtocol>(_ value: T, key: K, arrayIndex: Int = 0) {
        assertionFailure("Cannot set a resource with setValue; did you mean to use setTexture or setBuffer?")
    }
    
    public func setValue<T>(_ value: T, key: K, arrayIndex: Int = 0) {
        assert(_isPOD(T.self), "Only POD types should be used with setValue.")
        
        var value = value
        withUnsafeBytes(of: &value) { bufferPointer in
            self.setBytes(bufferPointer.baseAddress!, length: bufferPointer.count, for: key, arrayIndex: arrayIndex)
        }
    }
    
    public func setValue<T : ResourceProtocol>(_ value: T, key: FunctionArgumentKey, arrayIndex: Int = 0) {
        preconditionFailure("setValue should not be used with resources; use setBuffer or setTexture instead.")
    }
    
    public func setBytes(_ bytes: UnsafeRawPointer, length: Int, for key: K, arrayIndex: Int = 0) {
        let currentOffset = self.argumentBuffer._copyBytes(bytes, length: length)
        self.argumentBuffer.enqueuedBindings.append(
            (key, arrayIndex, .bytes(offset: currentOffset, length: length))
        )
    }
    
    public static var resourceType: ResourceType {
        return .argumentBuffer
    }
}

extension TypedArgumentBuffer {
    
    public func setBuffers(_ buffers: [Buffer], offsets: [Int], keys: [K]) {
        for (buffer, (offset, key)) in zip(buffers, zip(offsets, keys)) {
            self.setBuffer(buffer, offset: offset, key: key)
        }
    }
    
    public func setTextures(_ textures: [Texture], keys: [K]) {
        for (texture, key) in zip(textures, keys) {
            self.setTexture(texture, key: key)
        }
    }
    
    public func setSamplers(_ samplers: [SamplerDescriptor], keys: [K]) {
        for (sampler, key) in zip(samplers, keys) {
            self.setSampler(sampler, key: key)
        }
    }
}

extension TypedArgumentBuffer: CustomStringConvertible {
    public var description: String {
        return self.argumentBuffer.description
    }
}

// Unlike the other transient registries, the transient argument buffer registry is chunk-based.
// This is because the number of argument buffers used within a frame can vary dramatically, and so a pre-assigned maximum is more likely to be hit.
final class TransientArgumentBufferRegistry: TransientChunkRegistry<ArgumentBuffer> {
    static let instances = TransientRegistryArray<TransientArgumentBufferRegistry>()
    
    override class var maxChunks: Int { 2048 }
    
    let inlineDataAllocator : ExpandingBuffer<UInt8> = .init()
    
    func allocate(flags: ResourceFlags, sourceArray: ArgumentBufferArray) -> ArgumentBuffer {
        let resource = self.allocateHandle(flags: flags)
        let (chunkIndex, indexInChunk) = resource.index.quotientAndRemainder(dividingBy: ArgumentBuffer.itemsPerChunk)
        self.sharedPropertyChunks?[chunkIndex].initialize(index: indexInChunk, sourceArray: sourceArray)
        self.labelChunks[chunkIndex].advanced(by: indexInChunk).initialize(to: nil)
        return resource
    }
}

final class PersistentArgumentBufferRegistry: PersistentRegistry<ArgumentBuffer> {
    static let instance = PersistentArgumentBufferRegistry()
    
    override class var maxChunks: Int { 256 }
    
    func allocate(flags: ResourceFlags, sourceArray: ArgumentBufferArray) -> ArgumentBuffer {
        let handle = self.allocateHandle(flags: flags)
        let (chunkIndex, indexInChunk) = handle.index.quotientAndRemainder(dividingBy: ArgumentBuffer.itemsPerChunk)
        self.sharedChunks?[chunkIndex].initialize(index: indexInChunk, sourceArray: sourceArray)
        self.persistentChunks?[chunkIndex].initialize(index: indexInChunk, sourceArray: sourceArray)
        self.labelChunks[chunkIndex].advanced(by: indexInChunk).initialize(to: nil)
        return handle
    }
}

struct ArgumentBufferProperties: SharedResourceProperties {
    struct PersistentArgumentBufferProperties: PersistentResourceProperties {
        let inlineDataStorage : UnsafeMutablePointer<Data>
        let heaps : UnsafeMutablePointer<Heap?>
        /// The index that must be completed on the GPU for each queue before the CPU can read from this resource's memory.
        let readWaitIndices : UnsafeMutablePointer<QueueCommandIndices>
        /// The index that must be completed on the GPU for each queue before the CPU can write to this resource's memory.
        let writeWaitIndices : UnsafeMutablePointer<QueueCommandIndices>
        /// The RenderGraphs that are currently using this resource.
        let activeRenderGraphs : UnsafeMutablePointer<UInt8.AtomicRepresentation>
        
        init(capacity: Int) {
            self.inlineDataStorage = .allocate(capacity: capacity)
            self.heaps = .allocate(capacity: capacity)
            self.readWaitIndices = .allocate(capacity: capacity)
            self.writeWaitIndices = .allocate(capacity: capacity)
            self.activeRenderGraphs = .allocate(capacity: capacity)
        }
        
        func deallocate() {
            self.inlineDataStorage.deallocate()
            self.heaps.deallocate()
            self.readWaitIndices.deallocate()
            self.writeWaitIndices.deallocate()
            self.activeRenderGraphs.deallocate()
        }
        
        func initialize(index indexInChunk: Int, descriptor: ArgumentBufferDescriptor, heap: Heap?, flags: ResourceFlags) {
            self.inlineDataStorage.advanced(by: indexInChunk).initialize(to: Data())
            self.heaps.advanced(by: indexInChunk).initialize(to: nil)
            self.readWaitIndices.advanced(by: indexInChunk).initialize(to: SIMD8(repeating: 0))
            self.writeWaitIndices.advanced(by: indexInChunk).initialize(to: SIMD8(repeating: 0))
            self.activeRenderGraphs.advanced(by: indexInChunk).initialize(to: UInt8.AtomicRepresentation(0))
        }
        
        func initialize(index indexInChunk: Int, sourceArray: ArgumentBufferArray) {
            self.inlineDataStorage.advanced(by: indexInChunk).initialize(to: Data())
            self.heaps.advanced(by: indexInChunk).initialize(to: nil)
            self.readWaitIndices.advanced(by: indexInChunk).initialize(to: SIMD8(repeating: 0))
            self.writeWaitIndices.advanced(by: indexInChunk).initialize(to: SIMD8(repeating: 0))
            self.activeRenderGraphs.advanced(by: indexInChunk).initialize(to: UInt8.AtomicRepresentation(0))
        }
        
        func deinitialize(from indexInChunk: Int, count: Int) {
            self.inlineDataStorage.advanced(by: indexInChunk).deinitialize(count: count)
            self.heaps.advanced(by: indexInChunk).deinitialize(count: count)
        }
        
        var readWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndices>? { self.readWaitIndices }
        var writeWaitIndicesOptional: UnsafeMutablePointer<QueueCommandIndices>? { self.writeWaitIndices }
        var activeRenderGraphsOptional: UnsafeMutablePointer<UInt8.AtomicRepresentation>? { self.activeRenderGraphs }
    }
    
    let usages : UnsafeMutablePointer<ChunkArray<ResourceUsage>>
    let descriptors: UnsafeMutablePointer<ArgumentBufferDescriptor>
    let encoders : UnsafeMutablePointer<UnsafeRawPointer.AtomicOptionalRepresentation> // Some opaque backend type that can construct the argument buffer
    let allocationLengths: UnsafeMutablePointer<Int>
    let enqueuedBindings : UnsafeMutablePointer<ExpandingBuffer<(FunctionArgumentKey, Int, ArgumentBuffer.ArgumentResource)>>
    let bindings : UnsafeMutablePointer<ExpandingBuffer<(ResourceBindingPath, ArgumentBuffer.ArgumentResource)>>
    let sourceArrays : UnsafeMutablePointer<ArgumentBufferArray?>
    
    typealias Descriptor = ArgumentBufferDescriptor
    
    init(capacity: Int) {
        self.usages = .allocate(capacity: capacity)
        self.descriptors = .allocate(capacity: capacity)
        self.encoders = .allocate(capacity: capacity)
        self.allocationLengths = .allocate(capacity: capacity)
        self.enqueuedBindings = .allocate(capacity: capacity)
        self.bindings = .allocate(capacity: capacity)
        self.sourceArrays = .allocate(capacity: capacity)
    }
    
    func deallocate() {
        self.usages.deallocate()
        self.descriptors.deallocate()
        self.encoders.deallocate()
        self.allocationLengths.deallocate()
        self.enqueuedBindings.deallocate()
        self.bindings.deallocate()
        self.sourceArrays.deallocate()
    }
    
    func initialize(index indexInChunk: Int, descriptor: ArgumentBufferDescriptor, heap: Heap?, flags: ResourceFlags) {
        self.usages.advanced(by: indexInChunk).initialize(to: ChunkArray())
        self.descriptors.advanced(by: indexInChunk).initialize(to: descriptor)
        self.encoders.advanced(by: indexInChunk).initialize(to: UnsafeRawPointer.AtomicOptionalRepresentation(nil))
        self.allocationLengths.advanced(by: indexInChunk).initialize(to: .max)
        self.enqueuedBindings.advanced(by: indexInChunk).initialize(to: ExpandingBuffer())
        self.bindings.advanced(by: indexInChunk).initialize(to: ExpandingBuffer())
        self.sourceArrays.advanced(by: indexInChunk).initialize(to: nil)
    }
    
    func initialize(index indexInChunk: Int, sourceArray: ArgumentBufferArray) {
        self.usages.advanced(by: indexInChunk).initialize(to: ChunkArray())
        self.descriptors.advanced(by: indexInChunk).initialize(to: sourceArray.descriptor)
        self.encoders.advanced(by: indexInChunk).initialize(to: UnsafeRawPointer.AtomicOptionalRepresentation(nil))
        self.allocationLengths.advanced(by: indexInChunk).initialize(to: .max)
        self.enqueuedBindings.advanced(by: indexInChunk).initialize(to: ExpandingBuffer())
        self.bindings.advanced(by: indexInChunk).initialize(to: ExpandingBuffer())
        self.sourceArrays.advanced(by: indexInChunk).initialize(to: sourceArray)
    }
    
    func deinitialize(from index: Int, count: Int) {
        self.usages.advanced(by: index).deinitialize(count: count)
        self.descriptors.advanced(by: index).deinitialize(count: count)
        self.encoders.advanced(by: index).deinitialize(count: count)
        self.allocationLengths.advanced(by: index).deinitialize(count: count)
        self.enqueuedBindings.advanced(by: index).deinitialize(count: count)
        self.bindings.advanced(by: index).deinitialize(count: count)
        self.sourceArrays.advanced(by: index).deinitialize(count: count)
    }
    
    var usagesOptional: UnsafeMutablePointer<ChunkArray<ResourceUsage>>? { self.usages }
}

