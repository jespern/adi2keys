// Usage: swift normalize-linkedit.swift <mach-o>
//
// `codesign --remove-signature` leaves one field different from a never-signed binary: the
// __LINKEDIT segment's vmsize stays enlarged for the removed signature. This resets it to the
// unsigned value, the segment's filesize rounded up to the 16 KB page size, so a stripped release
// can be compared byte for byte with an unsigned rebuild. 64-bit, single-architecture Mach-O only.
import Foundation

let path = CommandLine.arguments[1]
var data = try Data(contentsOf: URL(filePath: path))

func read<T: FixedWidthInteger>(_: T.Type, at offset: Int) -> T {
    data.withUnsafeBytes { T(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: T.self)) }
}

guard data.count >= 32, read(UInt32.self, at: 0) == 0xFEED_FACF else {
    FileHandle.standardError.write(Data("\(path): not a 64-bit Mach-O\n".utf8))
    exit(1)
}

let pageSize: UInt64 = 0x4000
var offset = 32
for _ in 0..<read(UInt32.self, at: 16) {
    let command = read(UInt32.self, at: offset)
    let size = Int(read(UInt32.self, at: offset + 4))
    let name = String(decoding: data[(offset + 8)..<(offset + 24)].prefix { $0 != 0 }, as: UTF8.self)
    if command == 0x19, name == "__LINKEDIT" {   // LC_SEGMENT_64
        let filesize = read(UInt64.self, at: offset + 48)
        let vmsize = (filesize + pageSize - 1) / pageSize * pageSize
        withUnsafeBytes(of: vmsize.littleEndian) { data.replaceSubrange((offset + 32)..<(offset + 40), with: $0) }
    }
    offset += size
}
try data.write(to: URL(filePath: path))
