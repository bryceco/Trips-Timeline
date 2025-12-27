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
			guard !(annotation is MKUserLocation) else { return nil }

			let identifier = "PhotoMarker"
			var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView

			if view == nil {
				view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
				view?.canShowCallout = true
				view?.markerTintColor = .systemBlue
				view?.glyphText = "📷"

				// Add a thumbnail button on the right side
				let button = UIButton(type: .detailDisclosure)
				view?.rightCalloutAccessoryView = button
			} else {
				view?.annotation = annotation
			}

			return view
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
