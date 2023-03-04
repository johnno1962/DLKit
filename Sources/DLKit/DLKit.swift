//
//  DLKit.swift
//  DLKit
//
//  Created by John Holdsworth on 19/04/2021.
//  Copyright © 2020 John Holdsworth. All rights reserved.
//
//  Repo: https://github.com/johnno1962/DLKit
//  $Id: //depot/DLKit/Sources/DLKit/DLKit.swift#68 $
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
    public static let allImages: ImageSymbols = AllImages()
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

    /// Pseudo image representing all images
    open class AllImages: ImageSymbols.MultiImage {
        public init() {
            super.init(imageNumber: ~0)
            imageHandle = DLKit.RTLD_DEFAULT
        }
        open override var imageNumbers: [ImageNumber] {
            return (0..<_dyld_image_count()).map {$0}
        }
    }

    /// Pseudo image representing images in the app bundle
    open class AppImages: AllImages {
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
                    strstr(imageName, ".xctest/") != nil ||
                    strstr(imageName, "/eval") != nil
            }
        }
    }

    /// Pseudo image representing main executable image
    open class MainImage: ImageSymbols {
        public init() {
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
        guard imageNumber < DLKit.imageCount else {
            fatalError("Invalid image: \(imageNumber) !< \(DLKit.imageCount)")
        }
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

/// Abstraction for an image as operations on it's symbol table
open class ImageSymbols: ImageInfo, Equatable, CustomStringConvertible {
    /// Index into loaded images
    public typealias ImageNumber = UInt32
    public typealias SymbolValue = UnsafeMutableRawPointer
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

    public init(imageNumber: ImageNumber, typeMask: Int32 = N_STAB) {
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
            ImageSymbols(imageNumber: $0, typeMask: Int32(typeMask)) }
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
