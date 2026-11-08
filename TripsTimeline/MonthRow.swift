//
//  MonthRow.swift
//  Trips Timeline
//
//  Created by Bryce Cogswell on 12/16/25.
//

import CoreLocation
import SwiftUI

// MARK: - Month Row

struct MonthRow: View {
    let monthStart: Date
    let monthEnd: Date
    let trips: [Trip]
    let onTripTapped: ((Trip) -> Void)?
    @ObservedObject var verdicts: PlaceVerdicts

    private let daysInMonth: Int

    init(monthStart: Date, trips: [Trip], verdicts: PlaceVerdicts, onTripTapped: ((Trip) -> Void)?) {
        let daysInMonth = Calendar.current.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        let monthEnd = monthStart.addingTimeInterval(TimeInterval(daysInMonth * 24 * 60 * 60))

        self.monthStart = monthStart
        self.monthEnd = monthEnd
        self.trips = trips.filter { $0.startDate <= monthEnd && $0.endDate >= monthStart }
        self.verdicts = verdicts
        self.onTripTapped = onTripTapped
        self.daysInMonth = daysInMonth
    }

    /// Trips the user hasn't ruled out, in date order.
    private var shownTrips: [Trip] {
        trips.filter { verdicts.verdict(for: $0.place) != false }
    }

    private var monthLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yy MMM"
        return formatter.string(from: monthStart)
    }

    /// e.g. "🇫🇷 Paris, Lyon · 🇪🇸 Barcelona?" — a "?" marks a place awaiting a verdict.
    private var monthText: String {
        var byCountry: [(flag: String, cities: [String])] = []
        for trip in shownTrips {
            let city = trip.place.city + (verdicts.verdict(for: trip.place) == nil ? "?" : "")
            if let last = byCountry.last, last.flag == trip.place.flag {
                if !byCountry[byCountry.count - 1].cities.contains(city) {
                    byCountry[byCountry.count - 1].cities.append(city)
                }
            } else {
                byCountry.append((trip.place.flag, [city]))
            }
        }
        return byCountry.map { "\($0.flag) " + $0.cities.prefix(4).joined(separator: ", ") + ($0.cities.count > 4 ? "…" : "") }
            .joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                Text(monthLabel)
                    .font(.caption)
                    .frame(width: 50, alignment: .leading)

                GeometryReader { geo in
                    let dayWidth = geo.size.width / CGFloat(daysInMonth)
                    ZStack(alignment: .topLeading) {
                        HStack(spacing: 0) {
                            ForEach(1 ... daysInMonth, id: \.self) { day in
                                let dayDate = Calendar.current.date(bySetting: .day, value: day, of: monthStart)!
                                let trip = tripForDay(dayDate)
                                Rectangle()
                                    .fill(fill(for: trip))
                                    .frame(width: dayWidth, height: 28)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if let trip { onTripTapped?(trip) }
                                    }
                                    .contextMenu {
                                        if let trip { verdictMenu(for: trip) }
                                    }
                            }
                        }
                        // One flag per stay, centered over its days in this month.
                        ForEach(shownTrips) { trip in
                            let (first, last) = dayRange(of: trip)
                            let width = CGFloat(last - first + 1) * dayWidth
                            if width >= 18 {
                                Text(trip.place.flag)
                                    .font(.system(size: min(18, width * 0.9)))
                                    .frame(width: width, height: 28)
                                    .offset(x: CGFloat(first - 1) * dayWidth)
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                }
                .frame(height: 28)
            }
            .padding(.horizontal, 5)
            if !monthText.isEmpty {
                Text(monthText)
                    .font(.caption)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private func verdictMenu(for trip: Trip) -> some View {
        let place = trip.place
        Text("\(place.flag) \(place.city), \(place.state)")
        Button("\(place.city) is a trip destination", systemImage: "checkmark") {
            verdicts.set(place, isTrip: true)
        }
        Button("\(place.city) is not a trip (home, errands…)", systemImage: "house") {
            verdicts.set(place, isTrip: false)
        }
        Divider()
        Button("All of \(place.country) is trips", systemImage: "checkmark.circle") {
            verdicts.set(country: place.country, isTrip: true)
        }
        Button("All of \(place.country) is not trips", systemImage: "house.circle") {
            verdicts.set(country: place.country, isTrip: false)
        }
        if verdicts.verdict(for: place) != nil {
            Divider()
            Button("Forget verdict for \(place.city)", systemImage: "questionmark") {
                verdicts.set(place, isTrip: nil)
            }
        }
    }

    private func fill(for trip: Trip?) -> Color {
        guard let trip else { return Color.gray.opacity(0.15) }
        switch verdicts.verdict(for: trip.place) {
        case true: return Color.accentColor.opacity(0.35)
        case false: return Color.gray.opacity(0.15)
        default: return Color.yellow.opacity(0.35) // awaiting a verdict
        }
    }

    /// First and last day-of-month this trip covers.
    private func dayRange(of trip: Trip) -> (Int, Int) {
        let cal = Calendar.current
        let first = trip.startDate < monthStart ? 1 : cal.component(.day, from: trip.startDate)
        let last = trip.endDate >= monthEnd ? daysInMonth : cal.component(.day, from: trip.endDate)
        return (first, max(first, last))
    }

    private func tripForDay(_ date: Date) -> Trip? {
        let dayEnd = date.addingTimeInterval(24 * 60 * 60)
        return trips.first { $0.startDate < dayEnd && $0.endDate >= date }
    }
}

// MARK: - Month Scroll View

struct MonthScrollView: View {
    let startDate: Date
    let numberOfMonths: Int
    let trips: [Trip]
    @ObservedObject var verdicts: PlaceVerdicts
    let onTripTapped: ((Trip) -> Void)?

    init(trips: [Trip], verdicts: PlaceVerdicts, onTripTapped: ((Trip) -> Void)?) {
        // start date should be midnight on first day of the month
        let components = Calendar.current.dateComponents([.year, .month],
                                                         from: trips.first?.startDate ?? Date())
        let monthStart = Calendar.current.date(from: components)!

        // compute number of months until today
        let numberOfMonths = Calendar.current.dateComponents([.month], from: monthStart, to: Date()).month!

        startDate = monthStart
        self.numberOfMonths = numberOfMonths + 1
        self.trips = trips
        self.verdicts = verdicts
        self.onTripTapped = onTripTapped
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(0 ..< numberOfMonths, id: \.self) { monthOffset in
                    let monthDate = Calendar.current.date(byAdding: .month, value: monthOffset, to: startDate)!
                    MonthRow(monthStart: monthDate,
                             trips: trips,
                             verdicts: verdicts,
                             onTripTapped: onTripTapped)
                }
            }
            .padding(.vertical)
        }
    }
}

extension Sequence where Element: Hashable {
    func uniqueInOrder() -> [Element] {
        var seen: Set<Element> = []
        var result: [Element] = []

        for element in self {
            if seen.insert(element).inserted {
                result.append(element)
            }
        }

        return result
    }
}
