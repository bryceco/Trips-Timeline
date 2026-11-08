//
//  ContentView.swift
//  Trips Timeline
//
//  Created by Bryce Cogswell on 12/15/25.
//

import SwiftUI

struct ContentView: View {
    @State private var trips: [Trip] = []
    @State private var selectedTrip: Trip? = nil
    @StateObject private var verdicts = PlaceVerdicts()

    var body: some View {
        Group {
            if !trips.isEmpty {
                MonthScrollView(trips: trips, verdicts: verdicts) { trip in
                    selectedTrip = trip
                }
            } else {
                VStack {
                    Text("Loading trips...")
                    ProgressView()
                }
            }
        }
        .onAppear {
            Task {
                trips = await PhotoLibrary.shared.allTrips()
            }
        }
        .sheet(item: $selectedTrip) { trip in
            PhotoMapSheet(identifiers: trip.photos, title: "\(trip.place.flag) \(trip.place.city)")
                .edgesIgnoringSafeArea(.all)
        }
    }
}

#Preview {
    ContentView()
}
