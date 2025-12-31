//
//  PhotoLibrary.swift
//  Trips Timeline
//
//  Created by Bryce Cogswell on 12/15/25.
//

import Photos
import SwiftReverseGeoCode

struct Place: Equatable {
	let city: String
	let state: String
	let country: String
}

struct Trip: Identifiable {
	let id = UUID()
	let startDate: Date
	var endDate: Date
	let location: CLLocation
	let place: Place
	var photos: [String] = []
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
		   let decoded = try? JSONDecoder().decode(ImageStore.self, from: data) {
			self.store = decoded.store
		} else {
			self.store = [:]
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
												options: options
			) { data, uti, orientation, info in

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
		let hasCameraInfo =
			exif[kCGImagePropertyExifFocalLength] != nil ||
			exif[kCGImagePropertyExifISOSpeedRatings] != nil ||
			exif[kCGImagePropertyExifExposureTime] != nil ||
			exif[kCGImagePropertyExifApertureValue] != nil ||
			exif[kCGImagePropertyExifLensModel] != nil ||
			tiff[kCGImagePropertyTIFFModel] != nil ||
			tiff[kCGImagePropertyTIFFMake] != nil
		return hasCameraInfo
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

		for index in 0..<assets.count {
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

	func placeName(for location: CLLocation) async -> Place? {
		do {
			let loc = try reverseService.reverseGeoCode(latitude: location.coordinate.latitude,
														longitude: location.coordinate.longitude)
			return Place(city: loc.name,
							state: loc.adminName,
							country: loc.countryName)
		} catch {
			return nil
		}
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

		let whiteList = [
			"Aruba",
			"Austria",
			"Belgium",
			"Bonaire, Saint Eustatius and Saba",
			"Canada",
			"Costa Rica",
			"Cyprus",
			"Czechia",
			"Dominica",
			"France",
			"Germany",
			"Gibraltar",
			"Grenada",
			"Hong Kong",
			"Hungary",
			"Iceland",
			"Ireland",
			"Italy",
			"Japan",
			"Kenya",
			"Macao",
			"Mexico",
			"Netherlands",
			"Portugal",
			"Puerto Rico",
			"Singapore",
			"South Africa",
			"Spain",
			"Switzerland",
			"Tanzania",
			"Taiwan",
			"The Netherlands",
			"Turkey",
			"United Arab Emirates",
			"United Kingdom",
			"United States",
			"Vatican",
			"Zimbabwe"
		]

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

		for entry in photoListValid {
			guard let place = await placeName(for: entry.location) else {
				continue
			}

			guard
				whiteList.contains(place.country)
			else {
				let name = await photoName(for: entry.asset) ?? ""
				let date = entry.asset.creationDate
				print("Not whitelisted: \(entry.asset.pixelWidth) x \(entry.asset.pixelHeight) - \(place.country),\(place.city) - \(name) - \(date ?? Date())")
				continue
			}

			if let lastTrip = trips.last,
			   lastTrip.place == place
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

#if false
		for trip in trips {
			let d1 = formatDateShort(trip.startDate)
			let d2 = formatDateShort(trip.endDate)
			print("\(d1)...\(d2): \(trip.locationName) (\(trip.photos.count)) - \(trip.location.altitude)")
		}
#endif

		return trips.filter {
			switch ($0.place.country, $0.place.state) {
			case ("United States", "Washington"):
				return false
			case ("China",_):
				print($0.place.state)
				return false
			default:
				return true
			}
		}
	}
}

