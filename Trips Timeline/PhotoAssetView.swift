//
//  PhotoViewer.swift
//  Trips Timeline
//
//  Created by Bryce Cogswell on 12/27/25.
//

import SwiftUI
import Photos

struct PhotoAssetView: View {
	var asset: PHAsset
	@State private var image: UIImage? = nil

	var body: some View {
		VStack {
			if let image = image {
				Image(uiImage: image)
					.resizable()
					.aspectRatio(contentMode: .fit)
					.padding()
			} else {
				ProgressView()
					.onAppear {
						loadImage()
					}
			}
		}
	}

	private func loadImage() {
		let imageManager = PHImageManager.default()
		let requestOptions = PHImageRequestOptions()
		requestOptions.isSynchronous = true

		imageManager.requestImage(for: asset, targetSize: CGSize(width: 300, height: 300), contentMode: .aspectFill, options: requestOptions) { img, _ in
			self.image = img
		}
	}
}
