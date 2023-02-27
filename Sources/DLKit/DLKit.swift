//
//  DLKit.swift
//  DLKit
//
//  Created by John Holdsworth on 19/04/2021.
//  Copyright © 2020 John Holdsworth. All rights reserved.
//
//  Repo: https://github.com/johnno1962/DLKit
//  $Id: //depot/DLKit/Sources/DLKit/DLKit.swift#36 $
//

import Foundation
#if SWIFT_PACKAGE
import DLKitC
#endif

/// Interface to symbols of dynamically loaded images (executable or frameworks).
public struct DLKit {
    /// Alias for symbol name type
    public typealias SymbolName = UnsafePointer<CChar>
    /// Pseudo image for all images loaded in the process.
    public static let allImages: ImageSymbols = AnyImage()
    /// Pseudo image for images loaded from the app bundle.
    public static let appImages: ImageSymbols = AppImages()
    /// Main execuatble image.
    public static let mainImage: ImageSymbols = MainImage()
    /// Total number of images.
    public static var imageCount: ImageSymbols.ImageNumber {
        return _dyld_image_count()
    }
    /// Last dynamically loaded image.
    public static var lastImage: ImageSymbols {
        return ImageSymbols(imageNumber: imageCount-1)
    }
    /// Image of code referencing this property
    public static var selfImage: ImageSymbols {
        return allImages[self_caller_address()!]!.image
    }
    /// List of all loaded images in order
    public static var imageList: [ImageSymbols] {
        return allImages.imageList
    }
    /// Map of all loaded images
    public static var imageMap: [String: ImageSymbols] {
        return allImages.imageMap
    }
    public static let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)
    public static let RTLD_MAIN_ONLY = UnsafeMutableRawPointer(bitPattern: -5)
    public static var logger = { (msg: String) in
        NSLog("DLKit: %@", msg)
    }
    public static func load(dylib: String) -> ImageSymbols? {
        let index = imageCount
        guard let handle = dlopen(dylib, RTLD_NOW) else {
            logger("⚠️ dlopen failed \(String(cString: dlerror()))")
            return nil
        }
        let image = ImageSymbols(imageNumber: index)
        image.imageHandle = handle
        return image
    }
}

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
            outputBuffer: nil, outputBufferSize: nil, flags: 0) /*??
            __cxa_demangle(self+1, output_buffer: nil,
                              length: nil, status: nil)*/ {
            let demangledName = String(cString: demangledNamePtr)
            free(demangledNamePtr)
            return demangledName
        }
        return nil
    }
}

public protocol ImageInfo {
    var imageNumber: ImageSymbols.ImageNumber { get }
}

public extension ImageInfo {
    /// Base address of image (pointer to mach_header at beginning of file)
    var imageHeader: UnsafePointer<mach_header_t> {
        return _dyld_get_image_header(imageNumber)
            .withMemoryRebound(to: mach_header_t.self, capacity: 1) {$0}
    }
    /// Amount image has been slid on load (after ASLR)
    var imageSlide: intptr_t {
        return _dyld_get_image_vmaddr_slide(imageNumber)
    }
    /// Path to image as cString
    var imageName: UnsafePointer<Int8> {
        return _dyld_get_image_name(imageNumber)
    }
    /// Path to image
    var imagePath: String {
        return String(cString: imageName)
    }
    /// Short name for image
    var imageKey: String {
        return URL(fileURLWithPath: imagePath).lastPathComponent
    }
}

extension ImageSymbols.ImageNumber: ImageInfo {
    public var imageNumber: Self { return self }
}

/// Abstraction for an image an operations on it's symbol table
open class ImageSymbols: ImageInfo, Equatable, CustomStringConvertible {
    /// Index into loaded images
    public typealias ImageNumber = UInt32
    public static func == (lhs: ImageSymbols, rhs: ImageSymbols) -> Bool {
        return lhs.imageNumber == rhs.imageNumber
    }
    public var description: String {
        return "#\(imageNumber) \(imagePath) \(imageHeader)"
    }

    /// Index into loaded images
    public let imageNumber: ImageNumber

    /// Lazilly recovered handle returned by dlopen
    public var imageHandle: UnsafeMutableRawPointer?

    public init(imageNumber: ImageNumber) {
        self.imageNumber = imageNumber
    }

    /// Array of image numbers covered - used for Pseudo images represening more than one image
    open var imageNumbers: [ImageNumber] {
        return [imageNumber]
    }
    /// List of wrapped images
    public var imageList: [ImageSymbols] {
        return imageNumbers.map { ImageSymbols(imageNumber: $0) }
    }
    /// Produce a map of images keyed by lastPathComponent of the imagePath
    public var imageMap: [String: ImageSymbols] {
        return Dictionary(uniqueKeysWithValues: imageList.map {
            ($0.imageKey, $0)
        })
    }
    /// Loook up an individual symbol by name
    public subscript (name: DLKit.SymbolName) -> UnsafeMutableRawPointer? {
        get { return self[[name]][0] }
        set (newValue) { self[[name]] = [newValue] }
    }
    /// Loook up an array of symbols
    public subscript (names: [DLKit.SymbolName]) -> [UnsafeMutableRawPointer?] {
        get {
            let handle = imageHandle ??
                dlopen(imageName, RTLD_LAZY)
            imageHandle = handle
            return names.map {dlsym(handle, $0)}
        }
        set (newValue) {
            /// Use fishhook to replace references to the named symbol with new values
            /// Works for symbols references across framework boundaries or inside
            /// an image if it has been linked with -Xlinker -interposable.
            var rebindings: [rebinding] = (0..<names.count).compactMap {
                guard $0 < newValue.count,
                    let replacement = newValue[$0] else {
                        DLKit.logger("missing replacement at index $0 for symbol \(String(cString: names[$0]))")
                    return nil
                }
                return rebinding(name: names[$0], replacement: replacement, replaced: nil)
            }
            var replaced = 0
            rebindings.withUnsafeMutableBufferPointer {
                let buffer = $0.baseAddress!, count = $0.count
                for image in imageNumbers {
                    // Have the rebind operation store the previous value
                    // to determine when rebindings have been successful.
                    for i in 0..<count {
                        buffer[i].replaced =
                            UnsafeMutablePointer(recast: &buffer[i].replaced)
                    }
                    rebind_symbols_image(
                        UnsafeMutableRawPointer(mutating: image.imageHeader),
                        image.imageSlide, buffer, count)
                    for i in 0..<count {
                        if buffer[i].replaced !=
                            UnsafeMutablePointer(recast: &buffer[i].replaced) {
                            replaced += 1
                        }
                    }
                }
            }
            // If nothing was replaced remind the user to use -interposable.
            if rebindings.count != 0 && replaced == 0 {
                DLKit.logger("No symbols replaced, have you added -Xlinker -interposable to your project's \"Other Linker Flags\"?")
            }
        }
    }
    /// Slightly dubious Array of Strings version of subscript
    public subscript (names: [String]) -> [UnsafeMutableRawPointer?] {
        get { return self[names.map {$0.withCString {$0}}] }
        set (newValue) { self[names.map {$0.withCString {$0}}] = newValue }
    }
    /// Inverse lookup returning image symbol name and wrapped image for an address.
    public subscript (ptr: UnsafeMutableRawPointer)
        -> (name: DLKit.SymbolName, image: ImageSymbols)? {
        var info = Dl_info()
        guard dladdr(ptr, &info) != 0,
              let index = imageNumbers.first(where: {
                  info.dli_fname == $0.imageName }) ??
                imageNumbers.first(where: {
                    strcmp(info.dli_fname, $0.imageName) == 0
                }) else { return nil }
        return (info.dli_sname, ImageSymbols(imageNumber: index))
    }
    /// Determine symbol associated with mangled name.
    /// ("self" must contain definition of or reference to symbol)
    /// - Parameter swift: Swift language version of symbol
    /// - Returns: Mangled version of String + value if there is one
    public func mangle(swift: String)
        -> (name: DLKit.SymbolName, value: UnsafeMutableRawPointer?)? {
        for entry in self where entry.name.demangled == swift {
            return (entry.name, entry.value)
        }
        return nil
    }
    /// Swift symbols encode their type in as a suffix
    /// - Parameter withSuffixes: Suffixes to search for or none for all symbols
    /// - Returns: Swift symbols with any of the suffixes
    public func swiftSymbols(withSuffixes: [String]? = nil) -> [Element] {
        return filter {
            let (name, value) = ($0.name, $0.value)
            guard value != nil && strncmp(name, "$s", 2) == 0 else { return false }
            guard let suffixes = withSuffixes else { return true }
            let symbol = String(cString: name)
            return suffixes.first(where: { symbol.hasSuffix($0) }) != nil
        }
    }
}

internal extension UnsafeMutablePointer {
    init<IN>(recast: UnsafeMutablePointer<IN>) {
        self = recast.withMemoryRebound(to: Pointee.self, capacity: 1) {$0}
    }
}

/// Extend Image wrapper to be iterable over the symbols defined
extension ImageSymbols: Sequence {
    public struct Entry {
        public let name: DLKit.SymbolName,
                   value: UnsafeMutableRawPointer?,
                   entry: UnsafePointer<nlist_t>
        public var isDebugging: Bool {
            return entry.pointee.n_type & UInt8(N_STAB) != 0
        }
    }
    public typealias Element = Entry
    public func makeIterator() -> AnyIterator<Element> {
        return AnyIterator(SymbolIterator(image: self))
    }
    struct SymbolIterator: IteratorProtocol {
        var state = symbol_iterator()
        init(image: ImageSymbols) {
            init_symbol_iterator(image.imageHeader, &state)
        }
        mutating func next() -> ImageSymbols.Element? {
            guard state.next_symbol < state.symbol_count else { return nil }
            let symbol = state.symbols.advanced(by: Int(state.next_symbol))
            state.next_symbol += 1
            return Entry(
                name: state.strings_base + 1 +
                    Int(symbol.pointee.n_un.n_strx),
                value: symbol.pointee.n_sect == NO_SECT ? nil :
                        UnsafeMutableRawPointer(bitPattern:
                        state.address_base + Int(symbol.pointee.n_value)),
                entry: UnsafePointer(symbol))
        }
    }
    public var definitions: [Entry] {
        return filter { $0.value != nil && !$0.isDebugging }
    }
}

/// Pseudo image representing all images
class AnyImage: ImageSymbols {
    init() {
        super.init(imageNumber: ~0)
        imageHandle = DLKit.RTLD_DEFAULT
    }
    open override var imageNumbers: [ImageNumber] {
        return (0..<_dyld_image_count()).map {$0}
    }
}

/// Pseudo image representing images in the app bundle
class AppImages: AnyImage {
    open override var imageNumbers: [ImageNumber] {
        let mainExecutable = Bundle.main.executablePath
        let bundleFrameworks = Bundle.main.privateFrameworksPath ?? "~~"
        let frameworkPathLength = strlen(bundleFrameworks)
        return super.imageNumbers.filter {
            let imageName = $0.imageName
            return strcmp(imageName, mainExecutable) == 0 ||
                strncmp(imageName, bundleFrameworks, frameworkPathLength) == 0 ||
                (strstr(imageName, "/DerivedData/") != nil &&
                 strstr(imageName, ".framework/") != nil) ||
                strstr(imageName, "/eval") != nil
        }
    }
}

/// Pseudo image representing main executable image
class MainImage: ImageSymbols {
    init() {
        let mainExecutable = Bundle.main.executablePath
        guard let mainImageNumber = mainExecutable?.withCString({ mainPath in
            DLKit.allImages.imageNumbers.first(where: {
                strcmp(mainPath, $0.imageName) == 0
            })}) else {
            DLKit.logger("Could not find image for main executable \(mainExecutable ?? "nil")")
            fatalError()
        }
        super.init(imageNumber: mainImageNumber)
        imageHandle = DLKit.RTLD_MAIN_ONLY
    }
}
