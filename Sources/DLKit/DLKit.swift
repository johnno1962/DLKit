//
//  DLKit.swift
//  DLKit
//
//  Created by John Holdsworth on 19/04/2021.
//  Copyright © 2020 John Holdsworth. All rights reserved.
//
//  Repo: https://github.com/johnno1962/DLKit
//  $Id: //depot/DLKit/Sources/DLKit/DLKit.swift#11 $
//

import Foundation
import DLKitC

/// Interface to symbols of dynamically loaded images (executable or frameworks).
public struct DLKit {
    /// Pseudo image for all images loaded in the process.
    public static let allImages: ImageSymbols = AnyImage()
    /// Pseudo image for images loaded in the process from the app bundle.
    public static let appImages: ImageSymbols = AppImages()
    /// Main execuatble image.
    public static let mainImage: ImageSymbols = MainImage()
    /// Last loaded image.
    public static var lastImage: ImageSymbols {
        return ImageSymbols(imageIndex: _dyld_image_count()-1)
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
}

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

/// Alias for symbol name type
public typealias SymbolName = UnsafePointer<Int8>
/// Extension for easy demangling of Swift symbols
public extension SymbolName {
    /// return Swif tlanguage description of symbol
    var demangle: String? {
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

/// Warrper for index into loaded images
public struct ImageNumber: Equatable {
    /// Index into loaded images
    public let imageIndex: UInt32
    /// Base address  of image (pointer to mach_header at beginning of file)
    public var imageHeader: UnsafePointer<mach_header_t> {
        return _dyld_get_image_header(imageIndex)
            .withMemoryRebound(to: mach_header_t.self, capacity: 1) {$0}
    }
    /// Amount image has been slid on load (after ASLR)
    public var imageSlide: intptr_t {
        return _dyld_get_image_vmaddr_slide(imageIndex)
    }
    /// Path to image as cString
    public var imageName: UnsafePointer<Int8> {
        return _dyld_get_image_name(imageIndex)
    }
    /// Path to image
    public var imagePath: String {
        return String(cString: imageName)
    }
    /// Short name for image
    public var imageKey: String {
        return URL(fileURLWithPath: imagePath).lastPathComponent
    }
}

/// Abstraction for an image an operations on it's symbol table
open class ImageSymbols: Equatable, CustomStringConvertible {
    public static func == (lhs: ImageSymbols, rhs: ImageSymbols) -> Bool {
        return lhs.imageNumber == rhs.imageNumber
    }
    public var description: String {
        return "#\(imageNumber.imageIndex) \(imageNumber.imagePath) \(imageNumber.imageHeader)"
    }

    /// Wrapped load index of image
    public var imageNumber: ImageNumber
    /// Lazilly mapped recovery of handle return by dlopen
    public var imageHandle: UnsafeMutableRawPointer?

    public init(imageIndex: UInt32) {
        self.imageNumber = ImageNumber(imageIndex: imageIndex)
    }

    /// Array of image numbers covered - used for Pseudo images represenint more than one image
    open var imageNumbers: [ImageNumber] {
        return [imageNumber]
    }
    /// List of wrapped images
    public var imageList: [ImageSymbols] {
        return imageNumbers.map {
            ImageSymbols(imageIndex: $0.imageIndex)
        }
    }
    /// Produce a map of images keyed by lastPathComponent of the imagePath
    public var imageMap: [String: ImageSymbols] {
        return Dictionary(uniqueKeysWithValues: imageList.map {
            return ($0.imageNumber.imageKey, $0)
        })
    }
    /// Loook up an individual symbol by name
    public subscript (name: SymbolName) -> UnsafeMutableRawPointer? {
        get { return self[[name]][0] }
        set (newValue) { self[[name]] = [newValue] }
    }
    /// Loook up an array of symbols
    public subscript (names: [SymbolName]) -> [UnsafeMutableRawPointer?] {
        get {
            let handle = imageHandle ??
                dlopen(imageNumber.imageName, RTLD_LAZY)
            imageHandle = handle
            return names.map {dlsym(handle, $0)}
        }
        set (newValue) {
            /// Use fishhook to replace references to the named symbol with new values
            /// Works for symbols references across framework boundaries or inside
            /// an image if it has been linked with -Xlinker -interposable.
            var rebindings = (0..<names.count).map {
                rebinding(name: names[$0], replacement: newValue[$0], replaced: nil)
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
            if replaced == 0 {
                NSLog("DLKit: No symbols replaced, have you added -Xlinker -interposable to your project's \"Other Linker Flags\"?")
            }
        }
    }
    /// Slightly hacky Array of Strings version
    public subscript (names: [String]) -> [UnsafeMutableRawPointer?] {
        get { return self[names.map {$0.withCString {$0}}] }
        set (newValue) { self[names.map {$0.withCString {$0}}] = newValue }
    }
    /// Inverse lookup returning image symbol name and wrapped image for an address.
    public subscript (ptr: UnsafeMutableRawPointer)
        -> (name: SymbolName, image: ImageSymbols)? {
        var info = Dl_info()
        guard dladdr(ptr, &info) != 0, let imageNumber = imageNumbers.filter({
            info.dli_fname == $0.imageName ||
            strcmp(info.dli_fname, $0.imageName) == 0
        }).first else { return nil }
        return (info.dli_sname, ImageSymbols(imageIndex: imageNumber.imageIndex))
    }
    /// Determine symbol associated with mangled name.
    /// ("self" much contain definition of or reference to symbol)
    /// - Parameter swift: Swift language version of symbol
    /// - Returns: Mangled version of String + value if there is one
    public func mangle(swift: String)
        -> (name: SymbolName, value: UnsafeMutableRawPointer?)? {
        for (name, value, _) in self where name.demangle == swift {
            return (name+1, value)
        }
        return nil
    }
}

internal extension UnsafeMutablePointer {
    init<IN>(recast: UnsafeMutablePointer<IN>) {
        self = recast.withMemoryRebound(to: Pointee.self, capacity: 1) {$0}
    }
}

/// Extend Image wrapper to be iterable over the symbols defined
extension ImageSymbols: Sequence {
    public typealias Element = (name: SymbolName,
        value: UnsafeMutableRawPointer?, entry: UnsafePointer<nlist_t>)
    public func makeIterator() -> AnyIterator<Element> {
        return AnyIterator(SymbolIterator(imageNumber: imageNumber))
    }
    struct SymbolIterator: IteratorProtocol {
        var state = symbol_iterator()
        init(imageNumber: ImageNumber) {
            init_symbol_iterator(imageNumber.imageHeader, &state)
        }
        mutating func next() -> ImageSymbols.Element? {
            guard state.next_symbol < state.symbol_count else { return nil }
            let symbol = state.symbols.advanced(by: Int(state.next_symbol))
            state.next_symbol += 1
            return (state.strings_base + Int(symbol.pointee.n_un.n_strx),
                    symbol.pointee.n_sect == NO_SECT ? nil :
                        UnsafeMutableRawPointer(bitPattern:
                        state.address_base + Int(symbol.pointee.n_value)),
                    UnsafePointer(symbol))
        }
    }
}

/// Psudo image representing all images
class AnyImage: ImageSymbols {
    init() {
        super.init(imageIndex: ~0)
        imageHandle = DLKit.RTLD_DEFAULT
    }
    open override var imageNumbers: [ImageNumber] {
        return (0..<_dyld_image_count()).map {ImageNumber(imageIndex: $0)}
    }
}

/// Psudo image representing images in the app bundle
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

/// Psudo image representing main executable image
class MainImage: AnyImage {
    override init() {
        super.init()
        imageNumber = imageNumbers[0]
        imageHandle = DLKit.RTLD_MAIN_ONLY
    }
    open override var imageNumbers: [ImageNumber] {
        let mainExecutable = Bundle.main.executablePath
        return super.imageNumbers.filter {
            strcmp(mainExecutable, $0.imageName) == 0
        }
    }
}
