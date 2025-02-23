import Foundation
import SwiftNetCDF
import CHelper


struct Array2DFastSpace {
    var data: [Float]
    let nLocations: Int
    let nTime: Int
    
    public init(data: [Float], nLocations: Int, nTime: Int) {
        precondition(data.count == nLocations * nTime)
        self.data = data
        self.nLocations = nLocations
        self.nTime = nTime
    }

    func writeNetcdf(filename: String, nx: Int, ny: Int) throws {
        let file = try NetCDF.create(path: filename, overwriteExisting: true)

        try file.setAttribute("TITLE", "My data set")

        let dimensions = [
            try file.createDimension(name: "TIME", length: nTime),
            try file.createDimension(name: "LAT", length: ny),
            try file.createDimension(name: "LON", length: nx)
        ]

        var variable = try file.createVariable(name: "MyData", type: Float.self, dimensions: dimensions)
        try variable.write(data)
    }
    
    @inlinable subscript(time: Int, location: Int) -> Float {
        get {
            precondition(location < nLocations, "location subscript invalid: \(location) with nLocations=\(nLocations)")
            precondition(time < nTime, "time subscript invalid: \(nTime) with nTime=\(nTime)")
            return data[time * nLocations + location]
        }
        set {
            precondition(location < nLocations, "location subscript invalid: \(location) with nLocations=\(nLocations)")
            precondition(time < nTime, "time subscript invalid: \(nTime) with nTime=\(nTime)")
            data[time * nLocations + location] = newValue
        }
    }
    
    @inlinable subscript(time: Int, location: Range<Int>) -> ArraySlice<Float> {
        get {
            precondition(location.upperBound < nLocations, "location subscript invalid: \(location) with nLocations=\(nLocations)")
            precondition(time < nTime, "time subscript invalid: \(nTime) with nTime=\(nTime)")
            return data[location.add(time * nLocations)]
        }
        set {
            precondition(location.upperBound < nLocations, "location subscript invalid: \(location) with nLocations=\(nLocations)")
            precondition(time < nTime, "time subscript invalid: \(nTime) with nTime=\(nTime)")
            data[location.add(time * nLocations)] = newValue
        }
    }
    
    /// Transpose to fast time
    func transpose() -> Array2DFastTime {
        precondition(data.count == nLocations * nTime)
        return data.withUnsafeBufferPointer { data in
            let out = [Float](unsafeUninitializedCapacity: data.count) { buffer, initializedCount in
                for l in 0..<nLocations {
                    for t in 0..<nTime {
                        buffer[l * nTime + t] = data[t * nLocations + l]
                    }
                }
                initializedCount += data.count
            }
            return Array2DFastTime(data: out, nLocations: nLocations, nTime: nTime)
        }
    }
}

struct Array2DFastTime {
    var data: [Float]
    let nLocations: Int
    let nTime: Int
    
    public init(data: [Float], nLocations: Int, nTime: Int) {
        precondition(data.count == nLocations * nTime)
        self.data = data
        self.nLocations = nLocations
        self.nTime = nTime
    }
    
    @inlinable subscript(location: Int, time: Int) -> Float {
        get {
            precondition(location < nLocations, "location subscript invalid: \(location) with nLocations=\(nLocations)")
            precondition(time < nTime, "time subscript invalid: \(nTime) with nTime=\(nTime)")
            return data[location * nTime + time]
        }
        set {
            precondition(location < nLocations, "location subscript invalid: \(location) with nLocations=\(nLocations)")
            precondition(time < nTime, "time subscript invalid: \(nTime) with nTime=\(nTime)")
            data[location * nTime + time] = newValue
        }
    }
    
    @inlinable subscript(location: Int, time: Range<Int>) -> ArraySlice<Float> {
        get {
            precondition(location < nLocations, "location subscript invalid: \(location) with nLocations=\(nLocations)")
            precondition(time.upperBound < nTime, "time subscript invalid: \(nTime) with nTime=\(nTime)")
            return data[time.add(location * nTime)]
        }
        set {
            precondition(location < nLocations, "location subscript invalid: \(location) with nLocations=\(nLocations)")
            precondition(time.upperBound < nTime, "time subscript invalid: \(nTime) with nTime=\(nTime)")
            data[time.add(location * nTime)] = newValue
        }
    }
    
    /// Transpose to fast space
    func transpose() -> Array2DFastSpace {
        precondition(data.count == nLocations * nTime)
        return data.withUnsafeBufferPointer { data in
            let out = [Float](unsafeUninitializedCapacity: data.count) { buffer, initializedCount in
                for t in 0..<nTime {
                    for l in 0..<nLocations {
                        buffer[t * nLocations + l] = data[l * nTime + t]
                    }
                }
                initializedCount += data.count
            }
            return Array2DFastSpace(data: out, nLocations: nLocations, nTime: nTime)
        }
    }
}

extension Array where Element == Float {
    func max(by: Int) -> [Float] {
        return stride(from: 0, through: count-24, by: 24).map { i in
            return self[i..<i+24].max()!
        }
    }
    func min(by: Int) -> [Float] {
        return stride(from: 0, through: count-24, by: 24).map { i in
            return self[i..<i+24].min()!
        }
    }
    func sum(by: Int) -> [Float] {
        return stride(from: 0, through: count-24, by: 24).map { i in
            return self[i..<i+24].reduce(0, +)
        }
    }
    func mean(by: Int) -> [Float] {
        return stride(from: 0, through: count-24, by: 24).map { i in
            return self[i..<i+24].reduce(0, +) / Float(by)
        }
    }
    
    mutating func rounded(digits: Int) {
        let roundExponent = powf(10, Float(digits))
        for i in indices {
            self[i] = Foundation.round(self[i] * roundExponent) / roundExponent
        }
    }
    
    func round(digits: Int) -> [Float] {
        let roundExponent = powf(10, Float(digits))
        return map {
            return Foundation.round($0 * roundExponent) / roundExponent
        }
    }
}
