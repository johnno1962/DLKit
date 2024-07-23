//
//  DLKit.swift
//  DLKit
//
//  Created by John Holdsworth on 19/04/2021.
//  Copyright © 2020 John Holdsworth. All rights reserved.
//
//  Repo: https://github.com/johnno1962/DLKit
//  $Id: //depot/DLKit/Sources/DLKit/DLKit.swift#77 $
//

#if DEBUG || !DEBUG_ONLY
#if canImport(Darwin)
import Foundation
#if SWIFT_PACKAGE
#if DEBUG_ONLY
#if canImport(DLKitCD)
@_exported import DLKitCD
#endif
#else
@_exported import DLKitC
#endif
#endif

/// Interface to symbols of dynamically loaded images (executable or frameworks).
public struct DLKit {
    /// Offset into table of loaded images
    public typealias ImageNumber = UInt32
    /// Alias for symbol name type
    public typealias SymbolName = UnsafePointer<CChar>
    /// Pseudo image for all images loaded in the process.
    public static let allImages = AllImages()
    /// Pseudo image for images loaded from the app bundle.
    public static let appImages = AppImages()
    /// Main execuatble image.
    public static let mainImage = MainImage()
    /// Total number of images.
    public static var imageCount: ImageNumber {
        return _dyld_image_count()
    }
    /// Last dynamically loaded image.
    public static var lastImage: ImageSymbols {
        return ImageSymbols(imageNumber: imageCount-1)
    }
    /// Image of code referencing this property
    public static var selfImage: ImageSymbols {
        return allImages[self_caller_address()!]!.image!
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
                    strstr(imageName, "/eval") != nil ||
                    strstr(imageName, ".debug.dylib") != nil // Xcode16
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

@_cdecl("DLKit_appImagesContain")
public func appImagesContain(symbol: UnsafePointer<CChar>) -> UnsafeMutableRawPointer? {
    return DLKit.appImages.imageList.compactMap {
        trie_dlsym($0.imageHeader, symbol) }.first
//    return DLKit.appImages.imageList.compactMap {
//        $0.entry(named: symbol) }.first?.value
}

public protocol ImageInfo {
    var imageNumber: DLKit.ImageNumber { get }
}

extension DLKit.ImageNumber: ImageInfo {
    public var imageNumber: Self { return self }
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
        return FileSymbols.filePaths[imageNumber] ?? String(cString: imageName)
    }
    /// Short name for image
    var imageKey: String {
        return URL(fileURLWithPath: imagePath).lastPathComponent
    }
}
#endif
#endif
