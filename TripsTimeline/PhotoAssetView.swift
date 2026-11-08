//
//  PhotoAssetView.swift
//  Trips Timeline
//
//  Created by Bryce Cogswell on 12/27/25.
//

import ImageIO
import Photos
import SwiftUI

/// A photo with everything known about it, to judge whether its place and time are right:
/// what the Photos database says, where that puts it, and what the image file itself says.
struct PhotoAssetView: View {
    var asset: PHAsset
    @State private var image: UIImage? = nil
    @State private var place: Place? = nil
    @State private var resources: [(type: String, name: String, uti: String)] = []
    @State private var fileInfo: [(String, String)]? = nil // nil while loading

    var body: some View {
        List {
            Section {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }
            .listRowInsets(EdgeInsets())

            Section("Photos database") {
                row("Date", asset.creationDate.map { $0.formatted(date: .long, time: .standard) })
                row("Modified", asset.modificationDate.map { $0.formatted(date: .abbreviated, time: .shortened) })
                if let location = asset.location {
                    row("Location", String(format: "%.5f, %.5f", location.coordinate.latitude, location.coordinate.longitude))
                    row("Altitude", location.verticalAccuracy >= 0 ? String(format: "%.0f m", location.altitude) : nil)
                    row("Accuracy", location.horizontalAccuracy > 0 ? String(format: "%.0f m", location.horizontalAccuracy) : nil)
                } else {
                    row("Location", "none")
                }
                row("Size", "\(asset.pixelWidth) × \(asset.pixelHeight)")
                row("Subtypes", subtypes)
                row("Favorite", asset.isFavorite ? "yes" : nil)
                row("Source", sourceType)
                row("Identifier", asset.localIdentifier)
            }

            Section("Place") {
                if let place {
                    row("Place", "\(place.flag) \(place.city), \(place.state), \(place.country)")
                } else {
                    row("Place", asset.location == nil ? "no location" : "not found")
                }
            }

            Section("Files") {
                ForEach(resources.indices, id: \.self) { i in
                    row(resources[i].type, "\(resources[i].name)  (\(resources[i].uti))")
                }
            }

            Section("Image file metadata") {
                if let fileInfo {
                    if fileInfo.isEmpty {
                        Text("No camera metadata in the file").foregroundStyle(.secondary)
                    }
                    ForEach(fileInfo.indices, id: \.self) { i in
                        row(fileInfo[i].0, fileInfo[i].1)
                    }
                } else {
                    ProgressView()
                }
            }
        }
        .task {
            loadImage()
            resources = PHAssetResource.assetResources(for: asset).map {
                (Self.resourceName($0.type), $0.originalFilename, $0.uniformTypeIdentifier)
            }
            if let location = asset.location {
                place = await PhotoLibrary.shared.placeName(for: location)
            }
            fileInfo = await readFileMetadata()
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String?) -> some View {
        if let value {
            LabeledContent(label, value: value)
                .textSelection(.enabled)
        }
    }

    private var subtypes: String? {
        var names: [String] = []
        let s = asset.mediaSubtypes
        if s.contains(.photoLive) { names.append("Live") }
        if s.contains(.photoScreenshot) { names.append("Screenshot") }
        if s.contains(.photoHDR) { names.append("HDR") }
        if s.contains(.photoPanorama) { names.append("Panorama") }
        if s.contains(.photoDepthEffect) { names.append("Portrait") }
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    private var sourceType: String? {
        switch asset.sourceType {
        case .typeCloudShared: return "Shared album"
        case .typeiTunesSynced: return "Synced"
        default: return nil
        }
    }

    private static func resourceName(_ type: PHAssetResourceType) -> String {
        switch type {
        case .photo: return "Original"
        case .fullSizePhoto: return "Edited"
        case .adjustmentData: return "Adjustments"
        case .alternatePhoto: return "Alternate"
        case .pairedVideo: return "Live video"
        default: return "Resource \(type.rawValue)"
        }
    }

    private func loadImage() {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .opportunistic
        PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 1200, height: 1200),
                                              contentMode: .aspectFit, options: options)
        { img, _ in
            if let img { image = img }
        }
    }

    /// EXIF, TIFF and GPS fields that bear on place and time, read from the current image file.
    private func readFileMetadata() async -> [(String, String)] {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.version = .current
        options.deliveryMode = .highQualityFormat
        guard let data = await PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options)?.data,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let meta = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return [("File", "couldn't be read")] }

        let exif = meta[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = meta[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let gps = meta[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]
        var rows: [(String, String)] = []
        func add(_ label: String, _ value: Any?) {
            if let value { rows.append((label, "\(value)")) }
        }
        add("Make", tiff[kCGImagePropertyTIFFMake])
        add("Model", tiff[kCGImagePropertyTIFFModel])
        add("Software", tiff[kCGImagePropertyTIFFSoftware])
        add("Lens", exif[kCGImagePropertyExifLensModel])
        add("Taken", exif[kCGImagePropertyExifDateTimeOriginal])
        add("Time zone", exif[kCGImagePropertyExifOffsetTimeOriginal])
        add("Digitized", exif[kCGImagePropertyExifDateTimeDigitized])
        add("File date", tiff[kCGImagePropertyTIFFDateTime])
        if let lat = gps[kCGImagePropertyGPSLatitude] as? Double, let lon = gps[kCGImagePropertyGPSLongitude] as? Double {
            let ns = gps[kCGImagePropertyGPSLatitudeRef] as? String ?? "?"
            let ew = gps[kCGImagePropertyGPSLongitudeRef] as? String ?? "?"
            rows.append(("GPS", String(format: "%.5f %@, %.5f %@", lat, ns, lon, ew)))
        }
        add("GPS date", gps[kCGImagePropertyGPSDateStamp])
        add("GPS time", gps[kCGImagePropertyGPSTimeStamp])
        add("GPS error", gps[kCGImagePropertyGPSHPositioningError])
        add("Exposure", exif[kCGImagePropertyExifExposureTime])
        add("ISO", (exif[kCGImagePropertyExifISOSpeedRatings] as? [Any])?.first)
        if let w = meta[kCGImagePropertyPixelWidth], let h = meta[kCGImagePropertyPixelHeight] {
            rows.append(("File size", "\(w) × \(h)"))
        }
        return rows
    }
}
