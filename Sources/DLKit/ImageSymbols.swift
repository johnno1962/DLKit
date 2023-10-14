//
//  ImageSymbols.swift
//  DLKit
//
//  Copyright © 2020 John Holdsworth. All rights reserved.
//  Created by John Holdsworth on 14/10/2023.
//  
//  Repo: https://github.com/johnno1962/DLKit
//  $Id: //depot/DLKit/Sources/DLKit/ImageSymbols.swift#2 $
//

import Foundation
#if SWIFT_PACKAGE
import DLKitC
#endif

/// Abstraction for an image as operations on it's symbol table
open class ImageSymbols: ImageInfo, Equatable, CustomStringConvertible {
    /// For compatability
    public typealias ImageNumber = DLKit.ImageNumber
    /// Index into loaded images
    public typealias SymbolValue = UnsafeMutableRawPointer
    /// Symbols included if these bits not set
    public static var mask: Int32 = N_STAB
    public static func == (lhs: ImageSymbols, rhs: ImageSymbols) -> Bool {
        return lhs.imageNumber == rhs.imageNumber
    }
    public var description: String {
        return "#\(imageNumber) \(imagePath) \(imageHeader)"
    }

    /// Index into loaded images
    public let imageNumber: ImageNumber
    /// Skip if any of these bits set in "n_type"
    let typeMask: UInt8

    /// Lazilly recovered handle returned by dlopen
    var imageHandle: UnsafeMutableRawPointer?
    /// Base address of image (pointer to mach_header at beginning of file)
    public var imageHeader: UnsafePointer<mach_header_t> {
        return imageNumber.imageHeader
    }

    public init(imageNumber: ImageNumber, typeMask: Int32 = ImageSymbols.mask) {
        self.imageNumber = imageNumber
        self.typeMask = UInt8(typeMask)
    }

    /// Array of image numbers covered - used to represent MultiImage
    open var imageNumbers: [ImageNumber] {
        return [imageNumber]
    }
    /// List of wrapped images
    open var imageList: [ImageSymbols] {
        return imageNumbers.map {
            if typeMask != ImageSymbols.mask, let path = FileSymbols.filePaths[$0],
                let masked = FileSymbols(path: path, typeMask: Int32(typeMask)) {
                return masked
            } else {
                return ImageSymbols(imageNumber: $0, typeMask: Int32(typeMask))
            }
        }
    }
    /// Produce a map of images keyed by lastPathComponent of the imagePath
    open var imageMap: [String: ImageSymbols] {
        return Dictionary(uniqueKeysWithValues: imageList.map {
            ($0.imageKey, $0)
        })
    }
    /// Entries in the symbol table
    open var entries: AnySequence<Entry> {
        return AnySequence<Entry>(self)
    }
    /// Default iterator now removes debug and undefined symbols
    open func makeIterator() -> AnyIterator<Entry> {
        return AnyIterator(SymbolIterator(image: self))
    }
    /// Implement custom symbol filtering here...
    open func skipFiltered(state: inout symbol_iterator) {
        while state.next_symbol < state.symbol_count && typeMask != 0 && (
            state.symbols[Int(state.next_symbol)].n_type & typeMask != 0 ||
            state.symbols[Int(state.next_symbol)].n_sect == NO_SECT) {
                state.next_symbol += 1
        }
    }

    /// Determine symbol associated with mangled name.
    /// ("self" must contain definition of or reference to symbol)
    /// - Parameter swift: Swift language version of symbol
    /// - Returns: Mangled version of String + value if there is one
    open func mangle(swift: String) -> Entry? {
        return entries.first(where: { $0.name.demangled == swift })
    }
    /// Swift symbols encode their type as a suffix
    /// - Parameter withSuffixes: Suffixes to search for or none for all symbols
    /// - Returns: Swift symbols with any of the suffixes
    open func swiftSymbols(withSuffixes: [String]? = nil) ->[Entry] {
        return entries.filter {
            let (name, value) = ($0.name, $0.value)
            guard value != nil && strncmp(name, "$s", 2) == 0 else { return false }
            guard let suffixes = withSuffixes else { return true }
            let symbol = String(cString: name)
            return suffixes.first(where: { symbol.hasSuffix($0) }) != nil
        }
    }
    /// Linear scan for symbols with prefix
    open func entries(withPrefix: DLKit.SymbolName) -> [Entry] {
        let prefixLen = strlen(withPrefix)
        return entries.filter({ strncmp($0.name, withPrefix, prefixLen) == 0 })
    }
    /// Linear scan for symbol by name
    open func entry(named: DLKit.SymbolName) -> Entry? {
        return entries.first(where: { strcmp($0.name, named) == 0 })
    }
}
