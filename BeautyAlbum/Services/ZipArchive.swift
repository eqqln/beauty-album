import Foundation
import Compression

// MARK: - 错误

enum ZipError: LocalizedError {
    case cannotCreate
    case badArchive
    case zip64Unsupported
    case unsupportedCompression(UInt16)
    case ioFailure(String)

    var errorDescription: String? {
        switch self {
        case .cannotCreate: return "无法创建压缩包文件"
        case .badArchive: return "压缩包已损坏或格式不正确"
        case .zip64Unsupported: return "暂不支持 ZIP64 格式（超过 4GB 的备份）"
        case .unsupportedCompression(let m): return "不支持的压缩方式：\(m)"
        case .ioFailure(let s): return "读写失败：\(s)"
        }
    }
}

// MARK: - CRC32

enum CRC32 {
    private static let table: [UInt32] = {
        var t = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1)
            }
            t[i] = c
        }
        return t
    }()

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            for i in 0..<raw.count {
                crc = table[Int((crc ^ UInt32(base[i])) & 0xFF)] ^ (crc >> 8)
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

// MARK: - 字节工具

private extension Data {
    mutating func put16(_ v: UInt16) {
        append(UInt8(v & 0xFF))
        append(UInt8((v >> 8) & 0xFF))
    }

    mutating func put32(_ v: UInt32) {
        append(UInt8(v & 0xFF))
        append(UInt8((v >> 8) & 0xFF))
        append(UInt8((v >> 16) & 0xFF))
        append(UInt8((v >> 24) & 0xFF))
    }
}

private func read16(_ b: [UInt8], _ o: Int) -> UInt16 {
    guard o + 1 < b.count else { return 0 }
    return UInt16(b[o]) | (UInt16(b[o + 1]) << 8)
}

private func read32(_ b: [UInt8], _ o: Int) -> UInt32 {
    guard o + 3 < b.count else { return 0 }
    return UInt32(b[o]) | (UInt32(b[o + 1]) << 8) | (UInt32(b[o + 2]) << 16) | (UInt32(b[o + 3]) << 24)
}

private func dosDateTime(_ date: Date) -> (time: UInt16, date: UInt16) {
    let cal = Calendar(identifier: .gregorian)
    let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    let year = max(1980, c.year ?? 1980)
    let month = max(1, min(12, c.month ?? 1))
    let day = max(1, min(31, c.day ?? 1))
    let hour = max(0, min(23, c.hour ?? 0))
    let minute = max(0, min(59, c.minute ?? 0))
    let second = max(0, min(59, c.second ?? 0)) / 2
    let t = UInt16((hour << 11) | (minute << 5) | second)
    let d = UInt16(((year - 1980) << 9) | (month << 5) | day)
    return (t, d)
}

// MARK: - 写入

/// 最小 ZIP 写入器：store 模式（不压缩），支持中文文件名。
/// 图片本身已是 JPEG 压缩数据，再套 deflate 收益极低，所以直接存储换取速度。
final class ZipWriter {
    private let handle: FileHandle
    private var records: [Record] = []
    private var closed = false
    let url: URL

    private struct Record {
        var name: Data
        var crc: UInt32
        var size: UInt32
        var offset: UInt32
        var time: UInt16
        var date: UInt16
    }

    init(url: URL) throws {
        self.url = url
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            try? fm.removeItem(at: url)
        }
        guard fm.createFile(atPath: url.path, contents: nil) else {
            throw ZipError.cannotCreate
        }
        do {
            handle = try FileHandle(forWritingTo: url)
        } catch {
            throw ZipError.ioFailure(error.localizedDescription)
        }
    }

    // MARK: 添加内容

    func addDirectory(_ path: String, date: Date = Date()) throws {
        var name = path
        if !name.hasSuffix("/") { name += "/" }
        let nameData = Data(name.utf8)
        let dt = dosDateTime(date)
        let offset = try handle.offset()

        var local = Data()
        local.put32(0x0403_4b50)
        local.put16(20)
        local.put16(0x0800)          // UTF-8 文件名
        local.put16(0)               // store
        local.put16(dt.time)
        local.put16(dt.date)
        local.put32(0)               // crc
        local.put32(0)               // comp size
        local.put32(0)               // uncomp size
        local.put16(UInt16(nameData.count))
        local.put16(0)
        local.append(nameData)
        try handle.write(contentsOf: local)

        records.append(Record(name: nameData, crc: 0, size: 0,
                              offset: UInt32(truncatingIfNeeded: offset),
                              time: dt.time, date: dt.date))
    }

    func addFile(path: String, data: Data, date: Date = Date()) throws {
        let nameData = Data(path.utf8)
        guard nameData.count <= 0xFFFF else { throw ZipError.ioFailure("路径过长：\(path)") }
        let crc = CRC32.checksum(data)
        let size = UInt32(data.count)
        let dt = dosDateTime(date)
        let offset = try handle.offset()

        var local = Data()
        local.put32(0x0403_4b50)
        local.put16(20)
        local.put16(0x0800)
        local.put16(0)
        local.put16(dt.time)
        local.put16(dt.date)
        local.put32(crc)
        local.put32(size)
        local.put32(size)
        local.put16(UInt16(nameData.count))
        local.put16(0)
        local.append(nameData)

        try handle.write(contentsOf: local)
        if !data.isEmpty { try handle.write(contentsOf: data) }

        records.append(Record(name: nameData, crc: crc, size: size,
                              offset: UInt32(truncatingIfNeeded: offset),
                              time: dt.time, date: dt.date))
    }

    func addFile(path: String, fileURL: URL) throws {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        } catch {
            throw ZipError.ioFailure(error.localizedDescription)
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let date = (attrs?[.modificationDate] as? Date) ?? Date()
        try addFile(path: path, data: data, date: date)
    }

    // MARK: 收尾

    @discardableResult
    func finish() throws -> URL {
        guard !closed else { return url }
        closed = true

        let cdStart = try handle.offset()
        var cd = Data()
        for r in records {
            cd.put32(0x0201_4b50)
            cd.put16(20)             // version made by
            cd.put16(20)             // version needed
            cd.put16(0x0800)
            cd.put16(0)
            cd.put16(r.time)
            cd.put16(r.date)
            cd.put32(r.crc)
            cd.put32(r.size)
            cd.put32(r.size)
            cd.put16(UInt16(r.name.count))
            cd.put16(0)              // extra
            cd.put16(0)              // comment
            cd.put16(0)              // disk start
            cd.put16(0)              // internal attrs
            cd.put32(0)              // external attrs
            cd.put32(r.offset)
            cd.append(r.name)
        }
        try handle.write(contentsOf: cd)

        var eocd = Data()
        eocd.put32(0x0605_4b50)
        eocd.put16(0)
        eocd.put16(0)
        eocd.put16(UInt16(records.count))
        eocd.put16(UInt16(records.count))
        eocd.put32(UInt32(cd.count))
        eocd.put32(UInt32(truncatingIfNeeded: cdStart))
        eocd.put16(0)
        try handle.write(contentsOf: eocd)

        try handle.close()
        return url
    }

    deinit {
        if !closed {
            try? handle.close()
        }
    }
}

// MARK: - 读取

struct ZipEntry {
    var name: String
    var isDirectory: Bool
    var compression: UInt16
    var crc: UInt32
    var compressedSize: UInt32
    var uncompressedSize: UInt32
    var localHeaderOffset: UInt32
}

final class ZipReader {
    private let handle: FileHandle
    private let fileSize: UInt64
    let url: URL
    private(set) var entries: [ZipEntry] = []

    init(url: URL) throws {
        self.url = url
        do {
            handle = try FileHandle(forReadingFrom: url)
            fileSize = try handle.seekToEnd()
        } catch {
            throw ZipError.ioFailure(error.localizedDescription)
        }
        try readCentralDirectory()
    }

    deinit {
        try? handle.close()
    }

    // MARK: 中央目录

    private func readCentralDirectory() throws {
        let tailSize = 66_000
        let start = fileSize > UInt64(tailSize) ? fileSize - UInt64(tailSize) : 0
        try handle.seek(toOffset: start)
        guard let tail = try handle.read(upToCount: Int(fileSize - start)), !tail.isEmpty else {
            throw ZipError.badArchive
        }
        let bytes = [UInt8](tail)

        var eocdIndex: Int? = nil
        var i = bytes.count - 22
        while i >= 0 {
            if bytes[i] == 0x50, bytes[i + 1] == 0x4b, bytes[i + 2] == 0x05, bytes[i + 3] == 0x06 {
                eocdIndex = i
                break
            }
            i -= 1
        }
        guard let e = eocdIndex else { throw ZipError.badArchive }

        let total = Int(read16(bytes, e + 10))
        let cdSize = Int(read32(bytes, e + 12))
        let cdOffset = Int(read32(bytes, e + 16))

        if total == 0xFFFF || cdSize == 0xFFFF_FFFF || cdOffset == 0xFFFF_FFFF {
            throw ZipError.zip64Unsupported
        }
        guard cdSize > 0, cdOffset >= 0 else { throw ZipError.badArchive }

        try handle.seek(toOffset: UInt64(cdOffset))
        guard let cdData = try handle.read(upToCount: cdSize), !cdData.isEmpty else {
            throw ZipError.badArchive
        }
        let cd = [UInt8](cdData)

        var p = 0
        var parsed: [ZipEntry] = []
        while p + 46 <= cd.count, read32(cd, p) == 0x0201_4b50 {
            let compression = read16(cd, p + 10)
            let crc = read32(cd, p + 16)
            let compSize = read32(cd, p + 20)
            let uncompSize = read32(cd, p + 24)
            let nameLen = Int(read16(cd, p + 28))
            let extraLen = Int(read16(cd, p + 30))
            let commentLen = Int(read16(cd, p + 32))
            let localOffset = read32(cd, p + 42)

            let nameStart = p + 46
            guard nameStart + nameLen <= cd.count else { break }
            let nameBytes = Array(cd[nameStart..<(nameStart + nameLen)])
            let name = String(decoding: nameBytes, as: UTF8.self)

            parsed.append(ZipEntry(
                name: name,
                isDirectory: name.hasSuffix("/"),
                compression: compression,
                crc: crc,
                compressedSize: compSize,
                uncompressedSize: uncompSize,
                localHeaderOffset: localOffset
            ))

            p = nameStart + nameLen + extraLen + commentLen
        }

        entries = parsed
        if entries.isEmpty { throw ZipError.badArchive }
    }

    // MARK: 解出单个条目

    func data(for entry: ZipEntry) throws -> Data {
        if entry.isDirectory { return Data() }

        try handle.seek(toOffset: UInt64(entry.localHeaderOffset))
        guard let header = try handle.read(upToCount: 30), header.count == 30 else {
            throw ZipError.badArchive
        }
        let h = [UInt8](header)
        guard read32(h, 0) == 0x0403_4b50 else { throw ZipError.badArchive }
        let nameLen = Int(read16(h, 26))
        let extraLen = Int(read16(h, 28))
        let dataOffset = UInt64(entry.localHeaderOffset) + 30 + UInt64(nameLen) + UInt64(extraLen)

        try handle.seek(toOffset: dataOffset)
        guard let raw = try handle.read(upToCount: Int(entry.compressedSize)) else {
            throw ZipError.badArchive
        }

        switch entry.compression {
        case 0:
            return raw
        case 8:
            guard let out = ZipReader.inflate(raw, expected: Int(entry.uncompressedSize)) else {
                throw ZipError.ioFailure("解压失败：\(entry.name)")
            }
            return out
        default:
            throw ZipError.unsupportedCompression(entry.compression)
        }
    }

    private static func inflate(_ data: Data, expected: Int) -> Data? {
        guard expected > 0 else { return Data() }
        var output = Data(count: expected)
        let written = output.withUnsafeMutableBytes { dst -> Int in
            guard let dstPtr = dst.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return data.withUnsafeBytes { src -> Int in
                guard let srcPtr = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(dstPtr, expected, srcPtr, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }
        return output.prefix(written)
    }

    // MARK: 整体解压

    @discardableResult
    func extract(to directory: URL, progress: ((String) -> Void)? = nil) throws -> [URL] {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        var written: [URL] = []

        for entry in entries {
            let clean = entry.name.replacingOccurrences(of: "\\", with: "/")
            // 防目录穿越
            if clean.contains("..") || clean.hasPrefix("/") { continue }

            let target = directory.appendingPathComponent(clean)
            if entry.isDirectory {
                try? fm.createDirectory(at: target, withIntermediateDirectories: true)
                continue
            }
            try? fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try data(for: entry)
            do {
                try data.write(to: target, options: .atomic)
                written.append(target)
                progress?(clean)
            } catch {
                throw ZipError.ioFailure("\(clean)：\(error.localizedDescription)")
            }
        }
        return written
    }
}
