//
//  PhotoMapSheet.swift
//  Trips Timeline
//
//  Created by Bryce Cogswell on 12/17/25.
//

import SwiftUI
import Photos

struct PhotoMapSheet: View {
	let identifiers: [String]
	@Environment(\.dismiss) private var dismiss
	@State private var selectedAsset: PHAsset?

	var body: some View {
		NavigationView {
			PhotoMapView(identifiers: identifiers,
						 onPhotoTapped: { id in
				let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
				selectedAsset = asset }
			)
				.edgesIgnoringSafeArea(.all)
				.navigationTitle("Photo Map")
				.navigationBarTitleDisplayMode(.inline)
				.toolbar {
					ToolbarItem(placement: .cancellationAction) {
						Button("Done") {
							dismiss()
						}
					}
				}
				.sheet(item: $selectedAsset) {
					asset in PhotoAssetView(asset: asset)
				}
		}
	}
}

extension PHAsset: @retroactive Identifiable {
    public var id: String { localIdentifier }
}

