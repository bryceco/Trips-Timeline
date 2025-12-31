//
//  PhotoMapView.swift
//  Trips Timeline
//
//  Created by Bryce Cogswell on 12/17/25.
//

import SwiftUI
import MapKit
import Photos

final class PhotoAnnotation: NSObject, MKAnnotation {
	let coordinate: CLLocationCoordinate2D
	let assetIdentifier: String
	var title: String? = "Photo"

	init(assetIdentifier: String, coordinate: CLLocationCoordinate2D) {
		self.assetIdentifier = assetIdentifier
		self.coordinate = coordinate
		super.init()
	}
}

struct PhotoMapView: UIViewRepresentable {
	let identifiers: [String]
	var onPhotoTapped: ((String) -> Void)? = nil

	func makeUIView(context: Context) -> MKMapView {
		let mapView = MKMapView()
		mapView.delegate = context.coordinator
		updateAnnotations(on: mapView)
		return mapView
	}

	func updateUIView(_ uiView: MKMapView, context: Context) {
		updateAnnotations(on: uiView)
	}

	func makeCoordinator() -> Coordinator {
		Coordinator(parent: self)
	}

	private func updateAnnotations(on mapView: MKMapView) {
		mapView.removeAnnotations(mapView.annotations)

		let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
		var annotations: [PhotoAnnotation] = []

		assets.enumerateObjects { asset, _, _ in
			if let location = asset.location {
				let annotation = PhotoAnnotation(assetIdentifier: asset.localIdentifier,
												 coordinate: location.coordinate)
				annotations.append(annotation)
			}
		}

		mapView.addAnnotations(annotations)
		if !annotations.isEmpty {
			mapView.showAnnotations(annotations, animated: true)
		}
	}

	class Coordinator: NSObject, MKMapViewDelegate {
		var parent: PhotoMapView

		init(parent: PhotoMapView) {
			self.parent = parent
		}

		func mapView(_ mapView: MKMapView,
					 viewFor annotation: MKAnnotation) -> MKAnnotationView?
		{
			guard let photo = annotation as? PhotoAnnotation else { return nil }

			let identifier = "PhotoThumb"
			var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)

			if view == nil {
				view = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
				view?.canShowCallout = false   // tap goes directly to preview
			} else {
				view?.annotation = annotation
			}

			// Load thumbnail
			let options = PHImageRequestOptions()
			options.deliveryMode = .fastFormat
			options.resizeMode = .fast
			options.isSynchronous = false

			let targetSize = CGSize(width: 40, height: 40)

			PHImageManager.default().requestImage(
				for: PHAsset.fetchAssets(withLocalIdentifiers: [photo.assetIdentifier], options: nil).firstObject!,
				targetSize: targetSize,
				contentMode: .aspectFill,
				options: options
			) { image, _ in
				guard let image else { return }

				// Make it circular
				let renderer = UIGraphicsImageRenderer(size: targetSize)
				let rounded = renderer.image { ctx in
					UIBezierPath(ovalIn: CGRect(origin: .zero, size: targetSize)).addClip()
					image.draw(in: CGRect(origin: .zero, size: targetSize))
				}

				view?.image = rounded
				view?.frame.size = targetSize
			}

			return view
		}

		func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
			guard let annotation = view.annotation as? PhotoAnnotation else { return }
			parent.onPhotoTapped?(annotation.assetIdentifier)
		}

		func mapView(_ mapView: MKMapView,
					 annotationView view: MKAnnotationView,
					 calloutAccessoryControlTapped control: UIControl) {

			guard
				let annotation = view.annotation as? PhotoAnnotation
			else { return }

			parent.onPhotoTapped?(annotation.assetIdentifier)
		}
	}
}
