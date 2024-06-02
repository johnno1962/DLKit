//
//  FileSymbols.swift
//  DLKit
//
//  Created by John Holdsworth on 14/10/2023.
//  Copyright © 2020 John Holdsworth. All rights reserved.
//
//  Repo: https://github.com/johnno1962/DLKit
//  $Id: //depot/DLKit/Sources/DLKit/FileSymbols.swift#7 $
//

#if DEBUG || !DEBUG_ONLY
#if canImport(Darwin)
import Foundation

open class FileSymbols: ImageSymbols {

    /// Fake imageNumber for files
    public static var fileNumber: ImageNumber = 1_000_000
    /// Record of paths to images read in rather than loaded
    public static var filePaths = [ImageNumber: String]()

    public let data: NSMutableData
    public let header: UnsafePointer<mach_header_t>

    override open var imageHeader: UnsafePointer<mach_header_t> {
        return header
    }
    override open var imageList: [ImageSymbols] {
        return [self]
    }
    
    static func parseFAT(bytes: UnsafeRawPointer, forArch: Int32?)
                        -> UnsafePointer<mach_header_t>? {
        let header = bytes.assumingMemoryBound(to: fat_header.self)
        if header.pointee.magic.bigEndian == FAT_MAGIC {
            let archs = bytes.advanced(by: MemoryLayout<fat_header>.size)
                .assumingMemoryBound(to: fat_arch.self)
            for slice in 0..<Int(header.pointee.nfat_arch.bigEndian) {
                if forArch == nil || archs[slice].cputype.bigEndian == forArch! {
                    return bytes.advanced(by: Int(archs[slice].offset.bigEndian))
                        .assumingMemoryBound(to: mach_header_t.self)
                }
            }
        }
        return nil
    }

    public init?(path: String, typeMask: Int32 = ImageSymbols.mask,
                 arch: Int32? = CPU_TYPE_ARM64) {
        guard let data = NSMutableData(contentsOfFile: path) else { return nil }
        self.data = data
        if data.bytes.load(as: UInt32.self) == MH_MAGIC_64 {
            header = data.bytes.assumingMemoryBound(to: mach_header_t.self)
        } else if let slice = Self.parseFAT(bytes: data.bytes, forArch: arch) {
            header = slice
        } else {
            return nil
        }
        super.init(imageNumber: Self.fileNumber, typeMask: typeMask)
        guard imageHeader.pointee.magic == MH_MAGIC_64 else { return nil }
        Self.filePaths[Self.fileNumber] = path
        trie_register(path, header)
        Self.fileNumber += 1
    }

    open func save(to path: String) -> Bool {
        return data.write(toFile: path, atomically: true)
    }
}
#endif
#endif
