//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2016 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

// @_exported import Dispatch

import CDispatch

/// qos_class_t

public struct DispatchQoS : Equatable {
	public let qosClass: QoSClass
	public let relativePriority: Int

	@available(OSX 10.10, iOS 8.0, *)
	public static let background = DispatchQoS(qosClass: .background, relativePriority: 0)

	@available(OSX 10.10, iOS 8.0, *)
	public static let utility = DispatchQoS(qosClass: .utility, relativePriority: 0)

	@available(OSX 10.10, iOS 8.0, *)
	public static let `default` = DispatchQoS(qosClass: .default, relativePriority: 0)

	@available(OSX 10.10, iOS 8.0, *)
	public static let userInitiated = DispatchQoS(qosClass: .userInitiated, relativePriority: 0)

	@available(OSX 10.10, iOS 8.0, *)
	public static let userInteractive = DispatchQoS(qosClass: .userInteractive, relativePriority: 0)

	public static let unspecified = DispatchQoS(qosClass: .unspecified, relativePriority: 0)

	public enum QoSClass {
		@available(OSX 10.10, iOS 8.0, *)
		case background

		@available(OSX 10.10, iOS 8.0, *)
		case utility

		@available(OSX 10.10, iOS 8.0, *)
		case `default`

		@available(OSX 10.10, iOS 8.0, *)
		case userInitiated

		@available(OSX 10.10, iOS 8.0, *)
		case userInteractive

		case unspecified

		// _OSQoSClass is internal on Linux, so this initialiser has to 
		// remain as an internal init.
		@available(OSX 10.10, iOS 8.0, *)
		internal init?(rawValue: _OSQoSClass) {
			switch rawValue {
			case .QOS_CLASS_BACKGROUND: self = .background
			case .QOS_CLASS_UTILITY: self = .utility
			case .QOS_CLASS_DEFAULT: self = .default
			case .QOS_CLASS_USER_INITIATED: self = .userInitiated
			case .QOS_CLASS_USER_INTERACTIVE: self = .userInteractive
			case .QOS_CLASS_UNSPECIFIED: self = .unspecified
			}
		}

		@available(OSX 10.10, iOS 8.0, *)
		internal var rawValue: _OSQoSClass {
			switch self {
			case .background: return .QOS_CLASS_BACKGROUND
			case .utility: return .QOS_CLASS_UTILITY
			case .default: return .QOS_CLASS_DEFAULT
			case .userInitiated: return .QOS_CLASS_USER_INITIATED
			case .userInteractive: return .QOS_CLASS_USER_INTERACTIVE
			case .unspecified: return .QOS_CLASS_UNSPECIFIED
			}
		}
	}

	public init(qosClass: QoSClass, relativePriority: Int) {
		self.qosClass = qosClass
		self.relativePriority = relativePriority
	}
}

public func ==(a: DispatchQoS, b: DispatchQoS) -> Bool {
	return a.qosClass == b.qosClass && a.relativePriority == b.relativePriority
}

/// 

public enum DispatchTimeoutResult {
    static let KERN_OPERATION_TIMED_OUT:Int = 49
	case success
	case timedOut
}

/// dispatch_group

public extension DispatchGroup {
	public func notify(qos: DispatchQoS = .unspecified, flags: DispatchWorkItemFlags = [], queue: DispatchQueue, execute work: @escaping @convention(block) () -> ()) {
		dispatch_group_notify(self.__wrapped, queue.__wrapped, work)
	}

	public func wait() {
		_ = dispatch_group_wait(self.__wrapped, DispatchTime.distantFuture.rawValue)
	}

	public func wait(timeout: DispatchTime) -> DispatchTimeoutResult {
		return dispatch_group_wait(self.__wrapped, timeout.rawValue) == 0 ? .success : .timedOut
	}

	public func wait(wallTimeout timeout: DispatchWallTime) -> DispatchTimeoutResult {
		return dispatch_group_wait(self.__wrapped, timeout.rawValue) == 0 ? .success : .timedOut
	}
}

/// dispatch_semaphore

public extension DispatchSemaphore {
	@discardableResult
	public func signal() -> Int {
		return Int(dispatch_semaphore_signal(self.__wrapped))
	}

	public func wait() {
		_ = dispatch_semaphore_wait(self.__wrapped, DispatchTime.distantFuture.rawValue)
	}

	public func wait(timeout: DispatchTime) -> DispatchTimeoutResult {
		return dispatch_semaphore_wait(self.__wrapped, timeout.rawValue) == 0 ? .success : .timedOut
	}

	public func wait(wallTimeout: DispatchWallTime) -> DispatchTimeoutResult {
		return dispatch_semaphore_wait(self.__wrapped, wallTimeout.rawValue) == 0 ? .success : .timedOut
	}
}
