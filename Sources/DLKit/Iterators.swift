//
//  Iterators.swift
//  DLKit
//
//  Created by John Holdsworth on 03/03/2023.
//  Copyright © 2020 John Holdsworth. All rights reserved.
//
//  Repo: https://github.com/johnno1962/DLKit
//  $Id: //depot/DLKit/Sources/DLKit/Iterators.swift#26 $
//

#if DEBUG || !DEBUG_ONLY
#if canImport(Darwin)

/// Extend Image wrapper to be iterable over the symbols defined
extension ImageSymbols: Sequence {
    public typealias Element = Entry
    public struct Entry: ImageInfo, CustomStringConvertible {
        public let imageNumber: ImageNumber,
                   name: DLKit.SymbolName,
                   value: SymbolValue?,
                   entry: UnsafeMutablePointer<nlist_t>

        public var isDebugging: Bool {
            return entry.pointee.n_type & UInt8(N_STAB) != 0
        }
        public var description: String {
            return String(format: "#%-3d %p: 0x%02x %s ", imageNumber,
                          unsafeBitCast(value, to: uintptr_t.self),
                          entry.pointee.n_type, name)+imageKey
        }
        public var symbol: String { return String(cString: name) }
        public var offset: UInt64 { return entry.pointee.n_value }
    }

    public struct SymbolIterator: IteratorProtocol {
        let owner: ImageSymbols
        var state = symbol_iterator()
        var next_symbol = 0;
        public init(image: ImageSymbols) {
            self.owner = image
            init_symbol_iterator(image.imageHeader, &state, image is FileSymbols)
        }
        mutating public func next() -> Element? {
            owner.skipFiltered(iterator: &self)
            guard next_symbol < state.symbol_count else { return nil }
            let symbol = state.symbols.advanced(by: next_symbol)
            next_symbol += 1
            return Entry(imageNumber: owner.imageNumber,
                name: state.strings_base + 1 +
                    Int(symbol.pointee.n_un.n_strx),
                value: symbol.pointee.n_sect == NO_SECT ? nil : SymbolValue(
                    bitPattern: state.address_base + Int(symbol[0].n_value)),
                entry: symbol)
        }
    }

    /// Overrides for iterating multiple images
    open class MultiImage: ImageSymbols {
        open override var entries: AnySequence<Element> {
            return AnySequence<Element>(imageList.flatMap { $0 })
        }
        open override func makeIterator() -> AnyIterator<Element> {
            return AnyIterator<Element>(entries.makeIterator())
        }
    }

    /// Represent filtered iteration on multiple images
    open class RefilteredSymbols: MultiImage {
        let owner: ImageSymbols
        public init(owner: ImageSymbols, typeMask: Int32) {
            self.owner = owner
            super.init(imageNumber: owner.imageNumber, typeMask: typeMask)
        }
        override open var imageHeader: UnsafePointer<mach_header_t> {
            return owner.imageHeader
        }
        open override var imageNumbers: [ImageNumber] {
            return owner.imageNumbers
        }
    }

    /// Iterate kitchen sink of all entries in the symbol table
    public var unfiltered: ImageSymbols {
        return RefilteredSymbols(owner: self, typeMask: 0) }

    /// Iterates over non-debug, non-private symbol definitions only.
    public var globals: ImageSymbols {
        return RefilteredSymbols(owner: self, typeMask: N_STAB | N_PEXT) }
}
#endif
#endif
