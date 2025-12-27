//
//  PhotoLibrary.swift
//  Trips Timeline
//
//  Created by Bryce Cogswell on 12/15/25.
//

import CoreLocation
import MapKit
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

class PhotoLibrary {

	static let shared = PhotoLibrary()

	func photoLibraryMetadata() async -> [(date: Date, location: CLLocation, id: String)] {
		let status: PHAuthorizationStatus = await withCheckedContinuation { continuation in
			PHPhotoLibrary.requestAuthorization { status in
				continuation.resume(returning: status)
			}
		}

		guard status == .authorized || status == .limited else {
			print("Photo library access denied.")
			return []
		}

		let assets = PHAsset.fetchAssets(with: .image, options: nil)
		var metadata: [(date: Date, location: CLLocation, id: String)] = []

		assets.enumerateObjects { asset, _, _ in
			guard let creationDate = asset.creationDate,
				  let location = asset.location
			else { return }

			metadata.append((date: creationDate, location: location, id: asset.localIdentifier))
		}

		return metadata
	}

	let reverseService = {
		let resourcePaths = Bundle.main.paths(forResourcesOfType: "bundle", inDirectory: nil)
		for path in resourcePaths {
			guard let bundle = Bundle(path: path) else { continue }
			let url = bundle.url(forResource: "geocitydb", withExtension: "sqlite")!
			return ReverseGeoCodeService(database: url.path)
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

	func allTrips() async -> [Trip] {
		let metadata = await photoLibraryMetadata().sorted { $0.date < $1.date }
		var trips: [Trip] = []
		for entry in metadata {
			guard let place = await placeName(for: entry.location) else {
				continue
			}

			if let lastTrip = trips.last,
			   lastTrip.place == place
			{
				trips[trips.count - 1].endDate = entry.date
				trips[trips.count - 1].photos.append(entry.id)
			} else {
				trips.append(Trip(startDate: entry.date,
								  endDate: entry.date,
								  location: entry.location,
								  place: place,
								  photos: [entry.id]))
			}
		}
#if false
		for trip in trips {
			let d1 = formatDateShort(trip.startDate)
			let d2 = formatDateShort(trip.endDate)
			print("\(d1)...\(d2): \(trip.locationName) (\(trip.photos.count)) - \(trip.location.altitude)")
		}
#endif

		return trips.filter{
			$0.place.country != "United States" ||
			$0.place.state != "Washington"
		}
	}
}
