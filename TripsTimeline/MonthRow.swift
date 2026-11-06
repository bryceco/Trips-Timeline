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
    let cityColors: [String: Color]
    let countryColors: [String: Color]
    let onTripTapped: ((Trip) -> Void)?

    // computed stuff
    let homeColor = Color.gray.opacity(0.2)
    private let daysInMonth: Int
    private var monthText: String

    init(monthStart: Date, trips: [Trip], cityColors: [String: Color], countryColors: [String: Color], onTripTapped: ((Trip) -> Void)?) {
        let daysInMonth = Calendar.current.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        let monthEnd = monthStart.addingTimeInterval(TimeInterval(daysInMonth * 24 * 60 * 60))
        let monthTrips = trips.filter { $0.startDate <= monthEnd && $0.endDate >= monthStart }

        self.monthStart = monthStart
        self.monthEnd = monthEnd
        self.trips = monthTrips
        self.cityColors = cityColors
        self.countryColors = countryColors
        self.onTripTapped = onTripTapped

        self.daysInMonth = daysInMonth

        monthText = {
            let countries = monthTrips.map { $0.place.country }.uniqueInOrder()
            let states = monthTrips.map { $0.place.state }.uniqueInOrder()
            let cities = monthTrips.map { $0.place.city }.uniqueInOrder()

            if countries.count > 1 {
                return countries.joined(separator: ", ")
            }
            if countries.count == 1 {
                if cities.count > 5 {
                    return "\(countries.first!): \(states.joined(separator: ", "))"
                }
                return "\(countries.first!): \(cities.joined(separator: ", "))"
            }
            return ""
        }()
    }

    private var monthLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yy MMM" // e.g. Jan 2025
        return formatter.string(from: monthStart)
    }

    var body: some View {
        VStack {
            HStack(spacing: 8) {
                Text(monthLabel)
                    .font(.caption)
                    .frame(width: 50, alignment: .leading)

                GeometryReader { geo in
                    let totalWidth = geo.size.width
                    let horizontalPadding: CGFloat = 0
                    let dayWidth = (totalWidth - horizontalPadding * 2) / CGFloat(daysInMonth)

                    HStack(spacing: 0) {
                        ForEach(1 ... daysInMonth, id: \.self) { day in
                            let dayDate = Calendar.current.date(bySetting: .day, value: day, of: monthStart)!
                            let tripColors = colorsForDay(dayDate)

                            VStack(spacing: 0) {
                                Rectangle()
                                    .fill(tripColors?.0 ?? homeColor)
                                    .frame(width: dayWidth, height: 20)
                                Rectangle()
                                    .fill(tripColors?.1 ?? homeColor)
                                    .frame(width: dayWidth, height: 20)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard let trip = tripForDay(dayDate) else { return }
                                onTripTapped?(trip)
                            }
                        }
                    }
                }
                .frame(height: 40)
            }
            .padding(.horizontal, 5)
            Text(monthText)
                .font(.caption)
        }
    }

    private func intervalsOverlap(start1: Date,
                                  end1: Date,
                                  start2: Date,
                                  end2: Date) -> Bool
    {
        return start1 <= end2 && start2 <= end1
    }

    private func tripForDay(_ date: Date) -> Trip? {
        for trip in trips {
            if intervalsOverlap(start1: date,
                                end1: date.addingTimeInterval(24 * 60 * 60),
                                start2: trip.startDate,
                                end2: trip.endDate)
            {
                return trip
            }
        }
        return nil
    }

    private func colorsForDay(_ date: Date) -> (Color, Color)? {
        guard
            let trip = tripForDay(date)
        else {
            return nil
        }
        let city = cityColors[trip.place.city]!
        let country = countryColors[trip.place.country]!

        // return (city, country)
        _ = city
        return (country, country)
    }
}

// MARK: - Month Scroll View

struct MonthScrollView: View {
    let startDate: Date
    let numberOfMonths: Int
    let trips: [Trip]
    let cityColors: [String: Color]
    let countryColors: [String: Color]
    let onTripTapped: ((Trip) -> Void)?

    init(trips: [Trip], onTripTapped: ((Trip) -> Void)?) {
        // start date should be midnight on first day of the month
        let components = Calendar.current.dateComponents([.year, .month],
                                                         from: trips.first?.startDate ?? Date())
        let monthStart = Calendar.current.date(from: components)!

        // compute number of months until today
        let numberOfMonths = Calendar.current.dateComponents([.month], from: monthStart, to: Date()).month!

        startDate = monthStart
        self.numberOfMonths = numberOfMonths + 1
        self.trips = trips

        // Compute tripColors
        var cityColors = [String: Color]()
        var countryColors = [String: Color]()

        let palette: [Color] = [.red, .blue, .green, .orange, .purple, .pink, .teal]
        var countryIndex = 0
        var cityIndex = 0

        for trip in trips {
            if countryColors[trip.place.country] == nil {
                countryColors[trip.place.country] = palette[countryIndex % palette.count]
                cityIndex = countryIndex
                countryIndex += 1
            }
            if cityColors[trip.place.city] == nil {
                cityColors[trip.place.city] = palette[cityIndex % palette.count]
            }
        }
        self.countryColors = countryColors
        self.cityColors = cityColors
        self.onTripTapped = onTripTapped
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(0 ..< numberOfMonths, id: \.self) { monthOffset in
                    let monthDate = Calendar.current.date(byAdding: .month, value: monthOffset, to: startDate)!
                    MonthRow(monthStart: monthDate,
                             trips: trips,
                             cityColors: cityColors,
                             countryColors: countryColors,
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
