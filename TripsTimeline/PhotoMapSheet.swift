//
//  PhotoMapSheet.swift
//  Trips Timeline
//
//  Created by Bryce Cogswell on 12/17/25.
//

import Photos
import SwiftUI

struct PhotoMapSheet: View {
    let identifiers: [String]
    var title = "Photo Map"
    @Environment(\.dismiss) private var dismiss
    @State private var selectedAsset: PHAsset?

    var body: some View {
        NavigationView {
            PhotoMapView(identifiers: identifiers,
                         onPhotoTapped: { id in
                             let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
                             selectedAsset = asset
                         })
                         .edgesIgnoringSafeArea(.all)
                         .navigationTitle(title)
                         .navigationBarTitleDisplayMode(.inline)
                         .toolbar {
                             ToolbarItem(placement: .cancellationAction) {
                                 Button("Done") {
                                     dismiss()
                                 }
                             }
                         }
                         .sheet(item: $selectedAsset) { asset in
                             NavigationStack {
                                 PhotoAssetView(asset: asset)
                                     .toolbar {
                                         ToolbarItem(placement: .cancellationAction) {
                                             Button("Done") { selectedAsset = nil }
                                         }
                                     }
                             }
                         }
        }
    }
}

extension PHAsset: @retroactive Identifiable {
    public var id: String {
        localIdentifier
    }
}
