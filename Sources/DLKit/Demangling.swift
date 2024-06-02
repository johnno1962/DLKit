//
//  Demangling.swift
//  DLKit
//
//  Created by John Holdsworth on 14/10/2023.
//  Copyright © 2020 John Holdsworth. All rights reserved.
//
//  Repo: https://github.com/johnno1962/DLKit
//  $Id: //depot/DLKit/Sources/DLKit/Demangling.swift#5 $
//

#if DEBUG || !DEBUG_ONLY
#if canImport(Darwin)
import Foundation

/// Extension for easy demangling of Swift symbols
public extension DLKit.SymbolName {
    @_silgen_name("swift_demangle")
    private
    func _stdlib_demangleImpl(
        _ mangledName: UnsafePointer<CChar>?,
        mangledNameLength: UInt,
        outputBuffer: UnsafeMutablePointer<UInt8>?,
        outputBufferSize: UnsafeMutablePointer<UInt>?,
        flags: UInt32
        ) -> UnsafeMutablePointer<CChar>?

    @_silgen_name("__cxa_demangle")
    func __cxa_demangle(_ mangled_name: UnsafePointer<Int8>?,
                        output_buffer: UnsafePointer<Int8>?,
                        length: UnsafeMutablePointer<size_t>?,
                        status: UnsafeMutablePointer<Int32>?)
        -> UnsafeMutablePointer<Int8>?

    /// return Swif tlanguage description of symbol
    var demangled: String? {
        if let demangledNamePtr = _stdlib_demangleImpl(
            self, mangledNameLength: UInt(strlen(self)),
            outputBuffer: nil, outputBufferSize: nil, flags: 0) ??
            __cxa_demangle(self+1, output_buffer: nil,
                              length: nil, status: nil) {
            let demangledName = String(cString: demangledNamePtr)
            free(demangledNamePtr)
            return demangledName
        }
        return nil
    }
}

extension String {
    public var swiftDemangle: String? {
        return withCString { $0.demangled }
    }
}
#endif
#endif
