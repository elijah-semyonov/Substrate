import Foundation
import SubstrateUtilities

@available(*, unavailable)
final class UnavailableBackend : SpecificRenderBackend {
    
    var hasUnifiedMemory: Bool {
        preconditionFailure()
    }
    
    var renderDevice: Any {
        preconditionFailure()
    }
    
    var api: RenderAPI {
        preconditionFailure()
    }
    
    final class CommandBufferImpl: BackendCommandBuffer {
        typealias Backend = UnavailableBackend
        
        func encodeCommands(encoderIndex: Int) { preconditionFailure() }
        
        func waitForEvent(_ event: Backend.Event, value: UInt64) { preconditionFailure() }
        func signalEvent(_ event: Backend.Event, value: UInt64) { preconditionFailure() }
        func presentSwapchains(resourceRegistry: Backend.TransientResourceRegistry, onPresented: (@Sendable (Texture, Result<OpaquePointer?, Error>) -> Void)? = nil) { preconditionFailure() }
        func commit(onCompletion: @escaping (CommandBufferImpl) -> Void) { preconditionFailure() }
        
        var gpuStartTime: Double { preconditionFailure() }
        var gpuEndTime: Double { preconditionFailure() }
        
        var error: Error? { preconditionFailure() }
    }
    
    final class QueueImpl: Substrate.BackendQueue {
        func makeCommandBuffer(commandInfo: FrameCommandInfo<RenderTargetDescriptorImpl>, resourceMap: FrameResourceMap<UnavailableBackend>, compactedResourceCommands: [CompactedResourceCommand<UnavailableBackend.CompactedResourceCommandType>]) -> CommandBufferImpl {
            preconditionFailure()
        }
        
        typealias Backend = UnavailableBackend
    }
    
    final class RenderTargetDescriptorImpl: BackendRenderTargetDescriptor {
        init(renderPass: RenderPassRecord) {
            preconditionFailure()
        }
        
        var descriptor: Substrate.RenderTargetDescriptor {
            preconditionFailure()
        }
        
        func descriptorMergedWithPass(_ pass: RenderPassRecord, storedTextures: inout [Texture]) -> Self {
            preconditionFailure()
        }
        
        func finalise(storedTextures: inout [Texture]) {
            preconditionFailure()
        }
        
        typealias Backend = UnavailableBackend
    }
    
    final class PersistentResourceRegistryImpl: BackendPersistentResourceRegistry {
        subscript(sampler: SamplerDescriptor) -> Backend.SamplerReference {
            get async {
                preconditionFailure()
            }
        }
        
        @available(macOS 11.0, iOS 14.0, *)
        subscript(accelerationStructure: AccelerationStructure) -> AnyObject? {
            preconditionFailure()
        }
        @available(macOS 11.0, iOS 14.0, *)
        subscript(visibleFunctionTable: VisibleFunctionTable) -> Backend.VisibleFunctionTableReference? {
            preconditionFailure()
        }
        
        @available(macOS 11.0, iOS 14.0, *)
        subscript(intersectionFunctionTable: IntersectionFunctionTable) -> Backend.IntersectionFunctionTableReference? {
            preconditionFailure()
        }
        
        func allocateBuffer(_ buffer: Buffer) -> Backend.BufferReference? {
            preconditionFailure()
        }
        
        func allocateTexture(_ texture: Texture) -> Backend.TextureReference? {
            preconditionFailure()
        }
        
        func prepareMultiframeBuffer(_ buffer: Buffer, frameIndex: UInt64) {
            preconditionFailure()
        }
        
        func prepareMultiframeTexture(_ texture: Texture, frameIndex: UInt64) {
            preconditionFailure()
        }
        
        func dispose(resource: Resource) {
            preconditionFailure()
        }
        
        subscript(buffer: Buffer) -> Backend.BufferReference? {
            preconditionFailure()
        }
        
        subscript(texture: Texture) -> Backend.TextureReference? {
            preconditionFailure()
        }
        
        subscript(argumentBuffer: ArgumentBuffer) -> Backend.ArgumentBufferReference? {
            preconditionFailure()
        }
        
        subscript(argumentBufferArray: ArgumentBufferArray) -> Backend.ArgumentBufferArrayReference? {
            preconditionFailure()
        }
        
        func prepareFrame() {
            preconditionFailure()
        }
        
        func cycleFrames() {
            preconditionFailure()
        }
        
        func allocateArgumentBufferIfNeeded(_ buffer: ArgumentBuffer) -> Backend.ArgumentBufferReference {
            preconditionFailure()
        }
        
        func allocateArgumentBufferArrayIfNeeded(_ buffer: ArgumentBufferArray) -> Backend.ArgumentBufferArrayReference {
            preconditionFailure()
        }
        
        
        func allocateVisibleFunctionTableIfNeeded(_ table: VisibleFunctionTable) async -> Backend.VisibleFunctionTableReference? {
            preconditionFailure()
        }
        
        func allocateIntersectionFunctionTableIfNeeded(_ table: IntersectionFunctionTable) async -> Backend.IntersectionFunctionTableReference? {
            preconditionFailure()
        }
        
        typealias Backend = UnavailableBackend
    }
    
    final class TransientResourceRegistryImpl: BackendTransientResourceRegistry {
        var accessLock: SpinLock { preconditionFailure() }
        
        static func isAliasedHeapResource(resource: Resource) -> Bool {
            preconditionFailure()
        }
        
        func registerWindowTexture(for: Texture, swapchain: Any) async {
            preconditionFailure()
        }
        
        func allocateBufferIfNeeded(_ buffer: Buffer, forceGPUPrivate: Bool) -> Backend.BufferReference {
            preconditionFailure()
        }
        
        func allocateTextureIfNeeded(_ texture: Texture, forceGPUPrivate: Bool, isStoredThisFrame: Bool) -> Backend.TextureReference {
            preconditionFailure()
        }
        
        func allocateWindowHandleTexture(_ texture: Texture) async throws -> Backend.TextureReference {
            preconditionFailure()
        }
        
        func allocateTextureView(_ texture: Texture, resourceMap: FrameResourceMap<UnavailableBackend>) -> Backend.TextureReference {
            preconditionFailure()
        }
        
        func setDisposalFences(on resource: Resource, to fences: [FenceDependency]) {
            preconditionFailure()
        }
        
        func disposeTexture(_ texture: Texture, waitEvent: ContextWaitEvent) {
            preconditionFailure()
        }
        
        func disposeBuffer(_ buffer: Buffer, waitEvent: ContextWaitEvent) {
            preconditionFailure()
        }
        
        func disposeArgumentBuffer(_ buffer: ArgumentBuffer, waitEvent: ContextWaitEvent) {
            preconditionFailure()
        }
        
        func disposeArgumentBufferArray(_ buffer: ArgumentBufferArray, waitEvent: ContextWaitEvent) {
            preconditionFailure()
        }
        
        func withHeapAliasingFencesIfPresent(for resourceHandle: Resource.Handle, perform: (inout [FenceDependency]) -> Void) {
            preconditionFailure()
        }
        
        var textureWaitEvents: TransientResourceMap<Texture, ContextWaitEvent> {
            preconditionFailure()
        }
        
        var bufferWaitEvents: TransientResourceMap<Buffer, ContextWaitEvent> {
            preconditionFailure()
        }
        
        var historyBufferResourceWaitEvents: [Resource : ContextWaitEvent] {
            preconditionFailure()
        }
        
        subscript(buffer: Buffer) -> Backend.BufferReference? {
            preconditionFailure()
        }
        
        subscript(texture: Texture) -> Backend.TextureReference? {
            preconditionFailure()
        }
        
        subscript(argumentBuffer: ArgumentBuffer) -> Backend.ArgumentBufferReference? {
            preconditionFailure()
        }
        
        subscript(argumentBufferArray: ArgumentBufferArray) -> Backend.ArgumentBufferArrayReference? {
            preconditionFailure()
        }
        
        func prepareFrame() {
            preconditionFailure()
        }
        
        func flushTransientBuffers() {
            preconditionFailure()
        }
        
        func cycleFrames() {
            preconditionFailure()
        }
        
        func allocateArgumentBufferIfNeeded(_ buffer: ArgumentBuffer) -> Backend.ArgumentBufferReference {
            preconditionFailure()
        }
        
        func allocateArgumentBufferArrayIfNeeded(_ buffer: ArgumentBufferArray) -> Backend.ArgumentBufferArrayReference {
            preconditionFailure()
        }
        
        typealias Backend = UnavailableBackend
    }
    
    typealias CompactedResourceCommandType = Void
    typealias InterEncoderDependencyType = CoarseDependency
    typealias BufferReference = Void
    typealias TextureReference = Void
    typealias SamplerReference = Void
    typealias ArgumentBufferReference = Void
    typealias ArgumentBufferArrayReference = Void
    typealias VisibleFunctionTableReference = Void
    typealias IntersectionFunctionTableReference = Void
    typealias Event = Void
    
    typealias RenderTargetDescriptor = RenderTargetDescriptorImpl
    typealias CommandBuffer = CommandBufferImpl
    
    typealias TransientResourceRegistry = TransientResourceRegistryImpl
    typealias PersistentResourceRegistry = PersistentResourceRegistryImpl
    
    static var activeContextTaskLocal: TaskLocal<RenderGraphContextImpl<UnavailableBackend>?> { preconditionFailure() }
    static var requiresResourceResidencyTracking: Bool { preconditionFailure() }
    
    var supportsMemorylessAttachments: Bool { preconditionFailure() }
    
    func makeQueue(renderGraphQueue: Queue) -> QueueImpl {
        preconditionFailure()
    }
    
    func makeSyncEvent(for queue: Queue) -> Event {
        preconditionFailure()
    }
    
    func freeSyncEvent(for queue: Queue) {
        preconditionFailure()
    }
    
    func syncEvent(for queue: Queue) -> Event? {
        preconditionFailure()
    }
    
    func reloadShaderLibraryIfNeeded() async {
        preconditionFailure()
    }
    
    var resourceRegistry: PersistentResourceRegistryImpl {
        preconditionFailure()
    }
    
    func makeTransientRegistry(index: Int, inflightFrameCount: Int, queue: Queue) -> TransientResourceRegistryImpl {
        preconditionFailure()
    }
    
    func compactResourceCommands(queue: Queue, resourceMap: FrameResourceMap<UnavailableBackend>, commandInfo: FrameCommandInfo<RenderTargetDescriptor>, commandGenerator: ResourceCommandGenerator<UnavailableBackend>, into: inout [CompactedResourceCommand<CompactedResourceCommandType>]) {
        preconditionFailure()
    }
    
    func didCompleteCommand(_ index: UInt64, queue: Queue, context: RenderGraphContextImpl<UnavailableBackend>) {
        preconditionFailure()
    }
    
    static func fillArgumentBuffer(_ argumentBuffer: ArgumentBuffer, storage: ArgumentBufferReference, firstUseCommandIndex: Int, resourceMap: FrameResourceMap<UnavailableBackend>) {
        preconditionFailure()
    }
    
    static func fillArgumentBufferArray(_ argumentBufferArray: ArgumentBufferArray, storage: ArgumentBufferArrayReference, firstUseCommandIndex: Int, resourceMap: FrameResourceMap<UnavailableBackend>) {
        preconditionFailure()
    }
    
    func fillVisibleFunctionTable(_ table: VisibleFunctionTable, storage: VisibleFunctionTableReference, firstUseCommandIndex: Int, resourceMap: FrameResourceMap<UnavailableBackend>) async {
        preconditionFailure()
    }
    
    func fillIntersectionFunctionTable(_ table: IntersectionFunctionTable, storage: IntersectionFunctionTableReference, firstUseCommandIndex: Int, resourceMap: FrameResourceMap<UnavailableBackend>) async {
        preconditionFailure()
    }
    
    func materialisePersistentResource(_ resource: Resource) -> Bool {
        preconditionFailure()
    }
    
    func replaceBackingResource(for resource: Resource, with: Any?) -> Any? {
        preconditionFailure()
    }
    
    func registerExternalResource(_ resource: Resource, backingResource: Any) {
        preconditionFailure()
    }
    
    func updateLabel(on resource: Resource) {
        preconditionFailure()
    }
    
    var requiresEmulatedInputAttachments: Bool {
        preconditionFailure()
    }
    
    func bufferContents(for buffer: Buffer, range: Range<Int>) -> UnsafeMutableRawPointer? {
        preconditionFailure()
    }
    
    func buffer(_ buffer: Buffer, didModifyRange range: Range<Int>) {
        preconditionFailure()
    }
    
    func copyTextureBytes(from texture: Texture, to bytes: UnsafeMutableRawPointer, bytesPerRow: Int, region: Region, mipmapLevel: Int) {
        preconditionFailure()
    }
    
    func replaceTextureRegion(texture: Texture, region: Region, mipmapLevel: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int) {
        preconditionFailure()
    }
    
    func replaceTextureRegion(texture: Texture, region: Region, mipmapLevel: Int, slice: Int, withBytes bytes: UnsafeRawPointer, bytesPerRow: Int, bytesPerImage: Int) {
        preconditionFailure()
    }
    
    func usedSize(for heap: Heap) -> Int {
        preconditionFailure()
    }
    
    func currentAllocatedSize(for heap: Heap) -> Int {
        preconditionFailure()
    }
    
    func maxAvailableSize(forAlignment alignment: Int, in heap: Heap) -> Int {
        preconditionFailure()
    }
    
    func updatePurgeableState(for resource: Resource, to: ResourcePurgeableState?) -> ResourcePurgeableState {
        preconditionFailure()
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    func accelerationStructureSizes(for descriptor: AccelerationStructureDescriptor) -> AccelerationStructureSizes {
        preconditionFailure()
    }
    
    func renderPipelineReflection(descriptor: RenderPipelineDescriptor, renderTarget: Substrate.RenderTargetDescriptor) -> PipelineReflection? {
        preconditionFailure()
    }
    
    func computePipelineReflection(descriptor: ComputePipelineDescriptor) -> PipelineReflection? {
        preconditionFailure()
    }
    
    func dispose(resource: Resource) {
        preconditionFailure()
    }
    
    var pushConstantPath: ResourceBindingPath {
        preconditionFailure()
    }
    
    func argumentBufferPath(at index: Int, stages: RenderStages) -> ResourceBindingPath {
        preconditionFailure()
    }
    
    func argumentBufferEncoder(for descriptor: ArgumentBufferDescriptor) -> UnsafeRawPointer? {
        preconditionFailure()
    }
    
    func backingResource(_ resource: Resource) -> Any? {
        preconditionFailure()
    }
    
    func sizeAndAlignment(for texture: TextureDescriptor) -> (size: Int, alignment: Int) {
        preconditionFailure()
    }
    
    func sizeAndAlignment(for buffer: BufferDescriptor) -> (size: Int, alignment: Int) {
        preconditionFailure()
    }
    
    func supportsPixelFormat(_ format: PixelFormat, usage: TextureUsage) -> Bool {
        preconditionFailure()
    }
}
