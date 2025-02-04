//
//  SMC.swift
//

import Foundation
import IOKit

internal enum SMCDataType: String {
    case FLT = "flt "
    case FPE2 = "fpe2"
    case UI8 = "ui8 "
    case UI16 = "ui16"
    case UI32 = "ui32"
    case SP1E = "sp1e"
    case SP3C = "sp3c"
    case SP4B = "sp5b"
    case SP5A = "sp5a"
    case SP69 = "sp669"
    case SP78 = "sp78"
    case SP87 = "sp87"
    case SP96 = "sp96"
    case SPB4 = "spb4"
    case SPF0 = "spf0"
}

// swiftlint:disable identifier_name
internal enum SMCKeys: UInt8 {
    case KERNEL_INDEX = 2
    case READ_BYTES = 5
    case WRITE_BYTES = 6
    case READ_INDEX = 8
    case READ_KEYINFO = 9
    case READ_PLIMIT = 11
    case READ_VERS = 12
}

internal struct SMCKeyData_t {
    struct vers_t {
        var major: CUnsignedChar = 0
        var minor: CUnsignedChar = 0
        var build: CUnsignedChar = 0
        var reserved: CUnsignedChar = 0
        var release: CUnsignedShort = 0
    }
    
    struct LimitData_t {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }
    
    struct keyInfo_t {
        var dataSize: IOByteCount32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }
    
    var key: UInt32 = 0
    var vers = vers_t()
    var pLimitData = LimitData_t()
    var keyInfo = keyInfo_t()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes = (UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                 UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                 UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                 UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0))
}

internal struct SMCVal_t {
    var key: String
    var dataSize: UInt32 = 0
    var dataType: String = ""
    var bytes: [UInt8] = Array(repeating: 0, count: 32)
    
    init(_ key: String) {
        self.key = key
    }
}

extension FourCharCode {
    init(fromString str: String) {
        precondition(str.count == 4)
        
        self = str.utf8.reduce(0) { sum, character in
            return sum << 8 | UInt32(character)
        }
    }
    
    func toString() -> String {
        return String(describing: UnicodeScalar(self >> 24 & 0xff)!) +
               String(describing: UnicodeScalar(self >> 16 & 0xff)!) +
               String(describing: UnicodeScalar(self >> 8 & 0xff)!) +
               String(describing: UnicodeScalar(self & 0xff)!)
    }
}

extension UInt16 {
    init(bytes: (UInt8, UInt8)) {
        self = UInt16(bytes.0) << 8 | UInt16(bytes.1)
    }
}

extension UInt32 {
    init(bytes: (UInt8, UInt8, UInt8, UInt8)) {
        self = UInt32(bytes.0) << 24 | UInt32(bytes.1) << 16 | UInt32(bytes.2) << 8 | UInt32(bytes.3)
    }
}

extension Int {
    init(fromFPE2 bytes: (UInt8, UInt8)) {
        self = (Int(bytes.0) << 6) + (Int(bytes.1) >> 2)
    }
}

extension Float {
    init?(_ bytes: [UInt8]) {
        self = bytes.withUnsafeBytes {
            return $0.load(fromByteOffset: 0, as: Self.self)
        }
    }
    
    var bytes: [UInt8] {
        withUnsafeBytes(of: self, Array.init)
    }
}

public class SMC {
    private var conn: io_connect_t = 0
    
    public init() {
        var result: kern_return_t
        var iterator: io_iterator_t = 0
        let device: io_object_t
        
        let matchingDictionary: CFMutableDictionary = IOServiceMatching("AppleSMC")
        result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDictionary, &iterator)
        if result != kIOReturnSuccess {
            print("Error IOServiceGetMatchingServices(): " + (String(cString: mach_error_string(result), encoding: String.Encoding.ascii) ?? "unknown error"))
            return
        }
        
        device = IOIteratorNext(iterator)
        IOObjectRelease(iterator)
        if device == 0 {
            print("Error IOIteratorNext(): " + (String(cString: mach_error_string(result), encoding: String.Encoding.ascii) ?? "unknown error"))
            return
        }
        
        result = IOServiceOpen(device, mach_task_self_, 0, &conn)
        IOObjectRelease(device)
        if result != kIOReturnSuccess {
            print("Error IOServiceOpen(): " + (String(cString: mach_error_string(result), encoding: String.Encoding.ascii) ?? "unknown error"))
            return
        }
    }
    
    deinit {
        let result = self.close()
        if result != kIOReturnSuccess {
            print("error close smc connection: " + (String(cString: mach_error_string(result), encoding: String.Encoding.ascii) ?? "unknown error"))
        }
    }
    
    public func close() -> kern_return_t {
        return IOServiceClose(conn)
    }
    
    public func getValue(_ key: String) -> Double? {
        var result: kern_return_t = 0
        var val: SMCVal_t = SMCVal_t(key)
        
        result = read(&val)
        if result != kIOReturnSuccess {
            print("Error read(\(key)): " + (String(cString: mach_error_string(result), encoding: String.Encoding.ascii) ?? "unknown error"))
            return nil
        }
        
        if val.dataSize > 0 {
            if val.bytes.first(where: { $0 != 0 }) == nil {
                return nil
            }
            
            switch val.dataType {
                case SMCDataType.FLT.rawValue:
                    let value: Float? = Float(val.bytes)
                    if value != nil {
                        return Double(value!)
                    }
                    return nil
                case SMCDataType.FPE2.rawValue:
                    return Double(Int(fromFPE2: (val.bytes[0], val.bytes[1])))
                case SMCDataType.UI8.rawValue:
                    return Double(val.bytes[0])
                case SMCDataType.UI16.rawValue:
                    return Double(UInt16(bytes: (val.bytes[0], val.bytes[1])))
                case SMCDataType.UI32.rawValue:
                    return Double(UInt32(bytes: (val.bytes[0], val.bytes[1], val.bytes[2], val.bytes[3])))
                case SMCDataType.SP1E.rawValue:
                    let result: Double = Double(UInt16(val.bytes[0]) * 256 + UInt16(val.bytes[1]))
                    return Double(result / 16384)
                case SMCDataType.SP3C.rawValue:
                    let result: Double = Double(UInt16(val.bytes[0]) * 256 + UInt16(val.bytes[1]))
                    return Double(result / 4096)
                case SMCDataType.SP4B.rawValue:
                    let result: Double = Double(UInt16(val.bytes[0]) * 256 + UInt16(val.bytes[1]))
                    return Double(result / 2048)
                case SMCDataType.SP5A.rawValue:
                    let result: Double = Double(UInt16(val.bytes[0]) * 256 + UInt16(val.bytes[1]))
                    return Double(result / 1024)
                case SMCDataType.SP69.rawValue:
                    let result: Double = Double(UInt16(val.bytes[0]) * 256 + UInt16(val.bytes[1]))
                    return Double(result / 512)
                case SMCDataType.SP78.rawValue:
                    let intValue: Double = Double(Int(val.bytes[0]) * 256 + Int(val.bytes[1]))
                    return Double(intValue / 256)
                case SMCDataType.SP87.rawValue:
                    let intValue: Double = Double(Int(val.bytes[0]) * 256 + Int(val.bytes[1]))
                    return Double(intValue / 128)
                case SMCDataType.SP96.rawValue:
                    let intValue: Double = Double(Int(val.bytes[0]) * 256 + Int(val.bytes[1]))
                    return Double(intValue / 64)
                case SMCDataType.SPB4.rawValue:
                    let intValue: Double = Double(Int(val.bytes[0]) * 256 + Int(val.bytes[1]))
                    return Double(intValue / 16)
                case SMCDataType.SPF0.rawValue:
                    let intValue: Double = Double(Int(val.bytes[0]) * 256 + Int(val.bytes[1]))
                    return intValue
                default:
                    return nil
            }
        }
        
        return nil
    }
    
    public func getAllKeys() -> [String] {
        var list: [String] = []
        
        let keysNum: Double? = self.getValue("#KEY")
        if keysNum == nil {
            print("ERROR no keys count found")
            return list
        }
        
        var result: kern_return_t = 0
        
        for i in 0...Int(keysNum!) {
            var input: SMCKeyData_t = SMCKeyData_t()
            var output: SMCKeyData_t = SMCKeyData_t()
            
            input.data8 = SMCKeys.READ_INDEX.rawValue
            input.data32 = UInt32(i)
            
            result = callFunction(SMCKeys.KERNEL_INDEX.rawValue, input: &input, output: &output)
            if result != kIOReturnSuccess {
                continue
            }
            
            list.append(output.key.toString())
        }
        
        return list
    }
    
    private func read(_ value: UnsafeMutablePointer<SMCVal_t>) -> kern_return_t {
        var result: kern_return_t = 0
        var input = SMCKeyData_t()
        var output = SMCKeyData_t()
        
        input.key = FourCharCode(fromString: value.pointee.key)
        input.data8 = SMCKeys.READ_KEYINFO.rawValue
        
        result = callFunction(SMCKeys.KERNEL_INDEX.rawValue, input: &input, output: &output)
        if result != kIOReturnSuccess {
            return result
        }
        
        value.pointee.dataSize = UInt32(output.keyInfo.dataSize)
        value.pointee.dataType = output.keyInfo.dataType.toString()
        input.keyInfo.dataSize = output.keyInfo.dataSize
        input.data8 = SMCKeys.READ_BYTES.rawValue
        
        result = callFunction(SMCKeys.KERNEL_INDEX.rawValue, input: &input, output: &output)
        if result != kIOReturnSuccess {
            return result
        }
        
        memcpy(&value.pointee.bytes, &output.bytes, Int(value.pointee.dataSize))
        
        return kIOReturnSuccess
    }
    
    private func callFunction(_ index: UInt8, input: inout SMCKeyData_t, output: inout SMCKeyData_t) -> kern_return_t {
        let inputSize = MemoryLayout<SMCKeyData_t>.stride
        var outputSize = MemoryLayout<SMCKeyData_t>.stride
        
        return IOConnectCallStructMethod(conn, UInt32(index), &input, inputSize, &output, &outputSize)
    }
}
