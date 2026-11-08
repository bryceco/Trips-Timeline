//
//  PhotoLibrary.swift
//  Trips Timeline
//
//  Created by Bryce Cogswell on 12/15/25.
//

import Photos
import SwiftReverseGeoCode
import Combine

struct Place: Equatable, Hashable, Codable {
    let city: String
    let state: String
    let country: String

    /// Key used for storing the user's verdict on this place.
    var key: String { "\(city)|\(state)|\(country)" }

    var flag: String { Flags.flag(forCountry: country) }
}

struct Trip: Identifiable {
    let startDate: Date
    var endDate: Date
    let location: CLLocation
    let place: Place
    var photos: [String] = []

    /// Stable across runs, so selection and sheets survive a reload.
    var id: String { "\(place.key)@\(startDate.timeIntervalSinceReferenceDate)" }
}

/// Country flag emoji, found by matching the geocoder's country name against the
/// system's English region names.
enum Flags {
    private static let codes: [String: String] = {
        let english = Locale(identifier: "en_US")
        var codes: [String: String] = [:]
        for region in Locale.Region.isoRegions where region.identifier.count == 2 {
            if let name = english.localizedString(forRegionCode: region.identifier) {
                codes[name] = region.identifier
            }
        }
        // Names the geocoder uses that differ from the system's
        for (name, code) in ["The Netherlands": "NL", "Turkey": "TR", "Vatican": "VA", "Macao": "MO",
                             "Bonaire, Saint Eustatius and Saba": "BQ", "Czech Republic": "CZ",
                             "Russia": "RU", "South Korea": "KR", "Vietnam": "VN", "Laos": "LA",
                             "Iran": "IR", "Syria": "SY", "Bolivia": "BO", "Venezuela": "VE",
                             "Tanzania": "TZ", "Moldova": "MD", "Brunei": "BN", "Micronesia": "FM"]
        {
            codes[name] = code
        }
        return codes
    }()

    static func flag(forCountry name: String) -> String {
        guard let code = codes[name] else { return "🏳️" }
        return String(code.unicodeScalars.map { Character(UnicodeScalar(0x1F1E6 + $0.value - 65)!) })
    }
}

/// What the user has said about a place: a real trip destination, or not (home, errands,
/// someone else's photo). Unknown places are shown for review.
@MainActor
final class PlaceVerdicts: ObservableObject {
    @Published private(set) var verdicts: [String: Bool]

    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("PlaceVerdicts.json")
    }

    init() {
        verdicts = (try? JSONDecoder().decode([String: Bool].self, from: Data(contentsOf: Self.fileURL))) ?? [:]
    }

    /// The place's own verdict, else the whole country's, else nil.
    func verdict(for place: Place) -> Bool? {
        verdicts[place.key] ?? verdicts["||" + place.country]
    }

    func set(_ place: Place, isTrip: Bool?) {
        verdicts[place.key] = isTrip
        save()
    }

    func set(country: String, isTrip: Bool?) {
        verdicts["||" + country] = isTrip
        save()
    }

    private func save() {
        try? JSONEncoder().encode(verdicts).write(to: Self.fileURL, options: .atomic)
    }
}

/// Reverse-geocoding results, keyed by coordinate rounded to about 100 m.
final class PlaceStore {
    private var store: [String: Place]
    private var dirty = 0

    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("PlaceStore.json")
    }

    init() {
        store = (try? JSONDecoder().decode([String: Place].self, from: Data(contentsOf: Self.fileURL))) ?? [:]
    }

    private static func key(_ location: CLLocation) -> String {
        "\(Int((location.coordinate.latitude * 1000).rounded())),\(Int((location.coordinate.longitude * 1000).rounded()))"
    }

    func place(for location: CLLocation) -> Place? {
        store[Self.key(location)]
    }

    func add(_ place: Place, for location: CLLocation) {
        store[Self.key(location)] = place
        dirty += 1
        if dirty >= 5000 {
            save()
        }
    }

    func save() {
        dirty = 0
        try? JSONEncoder().encode(store).write(to: Self.fileURL, options: .atomic)
    }
}

func photoName(for asset: PHAsset) async -> String? {
    await Task.detached { () -> String? in
        let resources = PHAssetResource.assetResources(for: asset)

        if let primary = resources.first(where: { $0.type == .photo }) {
            return primary.originalFilename
        }

        if let full = resources.first(where: { $0.type == .fullSizePhoto }) {
            return full.originalFilename
        }

        if let alt = resources.first(where: { $0.type == .alternatePhoto }) {
            return alt.originalFilename
        }

        return resources.first?.originalFilename
    }.value
}

final class ImageStore: Codable {
    private var store: [String: Bool]

    private static let filename = "ImageStore.json"

    private static var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(filename)
    }

    init() {
        // Attempt to load from disk
        if let data = try? Data(contentsOf: Self.fileURL),
           let decoded = try? JSONDecoder().decode(ImageStore.self, from: data)
        {
            store = decoded.store
        } else {
            store = [:]
        }
    }

    func isValid(asset: PHAsset) -> Bool? {
        return store[asset.localIdentifier]
    }

    func add(asset: PHAsset, isValid: Bool) {
        store[asset.localIdentifier] = isValid
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(self)
            try data.write(to: Self.fileURL, options: [.atomic])
        } catch {
            print("ImageStore.save() failed:", error)
        }
    }
}

extension PHImageManager {
    struct ImageDataResult {
        let data: Data
        let uti: String?
        let orientation: CGImagePropertyOrientation
        let info: [AnyHashable: Any]
    }

    func requestImageDataAndOrientation(for asset: PHAsset,
                                        options: PHImageRequestOptions? = nil) async -> ImageDataResult?
    {
        await withCheckedContinuation { continuation in
            self.requestImageDataAndOrientation(for: asset,
                                                options: options)
            { data, uti, orientation, info in
                guard let data = data, let info = info else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(
                    returning: ImageDataResult(
                        data: data,
                        uti: uti,
                        orientation: orientation,
                        info: info
                    )
                )
            }
        }
    }
}

extension PHAsset {
    func isOriginal() async -> Bool {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.version = .current // not original
        options.deliveryMode = .highQualityFormat
        let image = await PHImageManager.default().requestImageDataAndOrientation(for: self, options: options)

        guard
            let data = image?.data,
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return false
        }

        // EXIF and TIFF dictionaries
        guard
            let exif = metadata[kCGImagePropertyExifDictionary] as? [CFString: Any],
            let tiff = metadata[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        else {
            return false
        }

        // Look for any camera‑related fields
        return exif[kCGImagePropertyExifFocalLength] != nil ||
            exif[kCGImagePropertyExifISOSpeedRatings] != nil ||
            exif[kCGImagePropertyExifExposureTime] != nil ||
            exif[kCGImagePropertyExifApertureValue] != nil ||
            exif[kCGImagePropertyExifLensModel] != nil ||
            tiff[kCGImagePropertyTIFFModel] != nil ||
            tiff[kCGImagePropertyTIFFMake] != nil
    }
}

class PhotoLibrary {
    static let shared = PhotoLibrary()

    func photoLibraryMetadata() async -> [(date: Date, location: CLLocation, asset: PHAsset)] {
        let status: PHAuthorizationStatus = await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard status == .authorized || status == .limited else {
            print("Photo library access denied.")
            return []
        }

        let options = PHFetchOptions()

        let assets = PHAsset.fetchAssets(with: .image, options: options)
        var metadata: [(date: Date, location: CLLocation, asset: PHAsset)] = []

        for index in 0 ..< assets.count {
            let asset = assets.object(at: index)
            guard
                let creationDate = asset.creationDate,
                let location = asset.location
            else {
                continue
            }
            metadata.append((date: creationDate, location: location, asset: asset))
        }

        return metadata
    }

    let reverseService = {
        let resourcePaths = Bundle.main.paths(forResourcesOfType: "bundle", inDirectory: nil)
        for path in resourcePaths {
            guard let bundle = Bundle(path: path) else { continue }
            let url = bundle.url(forResource: "geocitydb", withExtension: "sqlite")!
            let service: ReverseGeoCodeService
            do {
                service = try ReverseGeoCodeService(database: url.path)
            } catch {
                fatalError()
            }
            return service
        }
        fatalError()
    }()

    let places = PlaceStore()

    func placeName(for location: CLLocation) async -> Place? {
        if let cached = places.place(for: location) {
            return cached
        }
        do {
            let loc = try reverseService.reverseGeoCode(latitude: location.coordinate.latitude,
                                                        longitude: location.coordinate.longitude)
            let place = Place(city: loc.name,
                              state: loc.adminName,
                              country: loc.countryName)
            places.add(place, for: location)
            return place
        } catch {
            return nil
        }
    }

    /// Days without photos inside a stay at one place are still part of the stay.
    static let maxGapDays = 3.0

    /// Stays this close together (between different places) are one journey, and the
    /// photo-less days between them belong to it.
    static let maxJourneyGapDays = 4.0

    /// Photos taken from a plane: higher than any road, or moving faster than any car
    /// relative to both neighbouring photos.
    static let airborneAltitude = 6000.0   // metres
    static let airborneSpeed = 250.0       // km/h

    static func isAirborne(_ list: [(date: Date, location: CLLocation, asset: PHAsset)], at i: Int) -> Bool {
        let here = list[i]
        if here.location.verticalAccuracy >= 0, here.location.altitude > airborneAltitude {
            return true
        }
        func speed(to j: Int) -> Double? {
            guard list.indices.contains(j) else { return nil }
            let hours = abs(list[j].date.timeIntervalSince(here.date)) / 3600
            let km = list[j].location.distance(from: here.location) / 1000
            return km < 20 ? 0 : km / max(hours, 1.0 / 60)  // ignore short hops; cap tiny intervals
        }
        if let before = speed(to: i - 1), let after = speed(to: i + 1) {
            return before > airborneSpeed && after > airborneSpeed
        }
        return false
    }

    let dateFormatter = {
        let format = DateFormatter()
        format.dateFormat = "yyyy-MM-dd"
        return format
    }()

    func formatDateShort(_ date: Date) -> String {
        return dateFormatter.string(from: date)
    }

    let iPhonePhotoDimensions: [(width: Int, height: Int)] = [
    ]

    func allTrips() async -> [Trip] {
        let store = ImageStore()
        let photoListAll = await photoLibraryMetadata().sorted { $0.date < $1.date }
        var trips: [Trip] = []

        var lastDate = Date()
        var photoListValid: [(date: Date, location: CLLocation, asset: PHAsset)] = []
        for index in photoListAll.indices {
            // update progress
            if Date().timeIntervalSince(lastDate) > 10.0 {
                print("\(index)/\(photoListAll.count)")
                store.save()
                lastDate = lastDate.addingTimeInterval(10.0)
            }

            // check if we already validated the photo
            let entry = photoListAll[index]
            if let valid = store.isValid(asset: entry.asset) {
                if valid {
                    photoListValid.append(entry)
                }
                continue
            }

            // validate the photo
            let isValid = await entry.asset.isOriginal()
            store.add(asset: entry.asset, isValid: isValid)

            guard isValid else {
                if let place = await placeName(for: entry.location) {
                    print("Camera info discard: \(place.country), \(place.state), \(place.city)")
                }
                continue
            }

            photoListValid.append(entry)
        }
        store.save()

        // Consecutive photos at the same place form a stay; a few photo-less days don't end it.
        for (i, entry) in photoListValid.enumerated() {
            if Self.isAirborne(photoListValid, at: i) {
                continue
            }
            guard let place = await placeName(for: entry.location) else {
                continue
            }

            if let lastTrip = trips.last,
               lastTrip.place == place,
               entry.date.timeIntervalSince(lastTrip.endDate) <= Self.maxGapDays * 86400
            {
                trips[trips.count - 1].endDate = entry.date
                trips[trips.count - 1].photos.append(entry.asset.localIdentifier)
            } else {
                trips.append(Trip(startDate: entry.date,
                                  endDate: entry.date,
                                  location: entry.location,
                                  place: place,
                                  photos: [entry.asset.localIdentifier]))
            }
        }

        places.save()
        return trips
    }
}
