//
//  Dependency.swift
//  
//
//  Created by Thomas Roughton on 27/03/20.
//

import Foundation

struct FenceDependency {
    var encoderIndex: Int
    var index: Int // The index of the dependency within the command stream
    var stages: RenderStages
}

// For fence tracking - support at most one dependency between each set of two render passes. Make the fence update as early as possible, and make the fence wait as late as possible.
struct Dependency {
    var signal : FenceDependency
    var wait : FenceDependency
    
    init(dependentUsage: ResourceUsage, dependentEncoder: Int, passUsage: ResourceUsage, passEncoder: Int) {
        self.signal = FenceDependency(encoderIndex: passEncoder, index: passUsage.commandRange.last!, stages: passUsage.stages)
        self.wait = FenceDependency(encoderIndex: dependentEncoder, index: dependentUsage.commandRange.lowerBound, stages: dependentUsage.stages)
    }
    
    init(signal: FenceDependency, wait: FenceDependency) {
        self.signal = signal
        self.wait = wait
    }
    
    public func merged(with otherDependency: Dependency) -> Dependency {
        var result = self
        result.wait.index = min(result.wait.index, otherDependency.wait.index)
        result.wait.stages.formUnion(otherDependency.wait.stages)
        
        result.signal.index = max(result.signal.index, otherDependency.signal.index)
        result.signal.stages.formUnion(otherDependency.signal.stages)
        
        return result
    }
}