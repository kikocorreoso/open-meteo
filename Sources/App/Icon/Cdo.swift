import Foundation
import Vapor


extension Process {
    static func bunzip2(file: String) throws {
        try spawnOrDie(cmd: "bunzip2", args: ["--keep", "-f", file])
    }
    
    static public func grib2ToNetcdf(in inn: String, out: String) throws {
        try spawnOrDie(cmd: "cdo", args: ["-s","-f", "nc", "copy", inn, out])
    }
    
    static public func grib2ToNetCDFInvertLatitude(in inn: String, out: String) throws {
        try spawnOrDie(cmd: "cdo", args: ["-s","-f", "nc", "invertlat", inn, out])
    }
}

struct CdoIconGlobal {
    let gridFile: String
    let weightsFile: String
    let logger: Logger

    /// Download and prepare weights for icon global is missing
    public init(logger: Logger, workDirectory: String) throws {
        self.logger = logger
        let fileName = "icon_grid_0026_R03B07_G.nc"
        let remoteFile = "https://opendata.dwd.de/weather/lib/cdo/\(fileName).bz2"
        let localFile = "\(workDirectory)\(fileName).bz2"
        let localUncompressed = "\(workDirectory)\(fileName)"
        gridFile = "\(workDirectory)grid_icogl2world_0125.txt"
        weightsFile = "\(workDirectory)weights_icogl2world_0125.nc"
        let fm = FileManager.default

        if fm.fileExists(atPath: gridFile) && fm.fileExists(atPath: weightsFile) {
            return
        }

        if !fm.fileExists(atPath: gridFile) {
            let gridContext = """
            # Climate Data Operator (CDO) grid description file
            # Input: ICON
            # Area: Global
            # Grid: regular latitude longitude/geographical grid
            # Resolution: 0.125 x 0.125 degrees (approx. 13km)

            gridtype = lonlat
            xsize    = 2879
            ysize    = 1441
            xfirst   = -180
            xinc     = 0.125
            yfirst   = -90
            yinc     = 0.125
            """
            try gridContext.write(toFile: gridFile, atomically: true, encoding: .utf8)
        }

        if !fm.fileExists(atPath: localFile) {
            let curl = Curl(logger: logger)
            try curl.download(url: remoteFile, to: localFile)
        }

        if !fm.fileExists(atPath: localUncompressed) {
            logger.info("Uncompressing \(localFile)")
            try Process.bunzip2(file: localFile)
        }

        logger.info("Generating weights file \(weightsFile)")
        let task = try Process.spawn(cmd: "cdo", args: ["-s","gennn,\(gridFile)", localUncompressed, weightsFile])
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            fatalError("Cdo gennn failed")
        }

        try FileManager.default.removeItem(atPath: localUncompressed)
        try FileManager.default.removeItem(atPath: localFile)
    }

    public func remap(in inn: String, out: String) throws {
        logger.info("Remapping file \(inn)")
        try Process.spawnOrDie(cmd: "cdo", args: ["-s", "-f", "nc", "remap,\(gridFile),\(weightsFile)", inn, out])
    }
}

struct Curl {
    let logger: Logger

    let connectTimeout = 30

    /// Total time it will retry and then give up. Default 2 hourss
    let maxTimeSeconds = 2*3600

    let retryDelaySeconds = 5

    func download(url: String, to: String) throws {
        logger.info("Downloading file \(url)")
        let startTime = Date()
        let args = [
            "-s",
            "--show-error",
            "--fail", // also retry 404
            "--insecure", // ignore expired or invalid SSL certs
            "--retry-connrefused",
            "--limit-rate", "10M", // Limit to 10 MB/s -> 80 Mbps
            "--connect-timeout", "\(connectTimeout)",
            "--max-time", "\(maxTimeSeconds)",
            "-o", to,
            url
        ]
        while true {
            do {
                try Process.spawnOrDie(cmd: "curl", args: args)
                return
            } catch {
                if Int(Date().timeIntervalSince(startTime)) > maxTimeSeconds {
                    throw error
                }
                sleep(UInt32(retryDelaySeconds))
            }
        }
    }
}
