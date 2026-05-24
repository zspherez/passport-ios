import SwiftUI

/// Sheet for managing the customer's flight itinerary. Two modes:
///   - List existing flights, with a per-row remove action.
///   - Tap "Add flight" → mini search form (origin city → dest city → date)
///     that hits the backend's `/flights/search` proxy and shows scheduled
///     non-stop results.
///     Tapping a result adds it to LocalStore and pops back to the list.
struct FlightsView: View {
    @Binding var flights: [Flight]
    let onDismiss: () -> Void

    @State private var isAdding = false

    var body: some View {
        NavigationView {
            ZStack {
                Brand.bg.ignoresSafeArea()
                if isAdding {
                    AddFlightForm(
                        onAdded: { flight in
                            flights.append(flight)
                            LocalStore.flights = flights
                            isAdding = false
                        },
                        onCancel: { isAdding = false }
                    )
                } else {
                    flightList
                }
            }
            .navigationTitle(isAdding ? "Add flight" : "My flights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !isAdding {
                        Button("Done", action: onDismiss).tint(Brand.gold)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var flightList: some View {
        VStack(spacing: 14) {
            if flights.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "airplane")
                        .font(.system(size: 38))
                        .foregroundColor(.secondary)
                    Text("No flights added yet")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("Add the legs you're flying today so the app can\ncount down to your next gate.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(flights) { flight in
                            flightRow(flight)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            Spacer()
            Button(action: { isAdding = true }) {
                Label("Add flight", systemImage: "plus")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Brand.gold)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private func flightRow(_ flight: Flight) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(flight.originAirport) → \(flight.destinationAirport)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                Text("\(flight.flightCodes) · \(formatDeparture(flight))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                flights.removeAll { $0.id == flight.id }
                LocalStore.flights = flights
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color(white: 0.10))
        .cornerRadius(12)
    }

    private func formatDeparture(_ flight: Flight) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d · h:mm a"
        return f.string(from: flight.departureAt)
    }
}

// MARK: - Add flight form

private struct AddFlightForm: View {
    let onAdded: (Flight) -> Void
    let onCancel: () -> Void

    /// Specific airport (not metro) — letting the customer pin LGA→MDW
    /// keeps the result list short and avoids surfacing flights from
    /// terminals they're not actually using.
    @State private var origin: AirportOption = AirportOption.all.first { $0.code == "JFK" } ?? AirportOption.all[0]
    @State private var destination: AirportOption = AirportOption.all.first { $0.code == "ORD" } ?? AirportOption.all[1]
    @State private var date: Date = Date()
    @State private var results: [FlightSearchResult] = []
    @State private var isSearching = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("From").font(.footnote).foregroundStyle(.secondary)
                Picker("From", selection: $origin) {
                    ForEach(AirportOption.all) { a in
                        Text(a.displayLabel).tag(a)
                    }
                }
                .pickerStyle(.menu)
                .tint(Brand.gold)
                .padding(10)
                .background(Color(white: 0.13))
                .cornerRadius(8)

                Text("To").font(.footnote).foregroundStyle(.secondary)
                Picker("To", selection: $destination) {
                    ForEach(AirportOption.all) { a in
                        Text(a.displayLabel).tag(a)
                    }
                }
                .pickerStyle(.menu)
                .tint(Brand.gold)
                .padding(10)
                .background(Color(white: 0.13))
                .cornerRadius(8)

                Text("Travel date").font(.footnote).foregroundStyle(.secondary)
                DatePicker("", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .tint(Brand.gold)
            }
            .padding(.horizontal, 16)

            HStack(spacing: 10) {
                Button("Cancel", action: onCancel)
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(white: 0.18))
                    .cornerRadius(10)
                Button(action: search) {
                    HStack {
                        if isSearching { ProgressView().tint(.black) }
                        Text(isSearching ? "Searching…" : "Search")
                    }
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Brand.gold)
                    .cornerRadius(10)
                }
                .disabled(isSearching || origin.code == destination.code)
            }
            .padding(.horizontal, 16)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .padding(.horizontal, 16)
            }

            if !results.isEmpty {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(results) { r in
                            Button {
                                if let f = FlightsAPI.flight(from: r) { onAdded(f) }
                            } label: {
                                resultRow(r)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .padding(.top, 12)
    }

    private func resultRow(_ r: FlightSearchResult) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(r.flightCodes) · \(r.origin)→\(r.destination)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                Text("\(r.departureTime) – \(r.arrivalTime) · \(formatDuration(r.duration))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "plus.circle.fill")
                .foregroundColor(Brand.gold)
        }
        .padding(12)
        .background(Color(white: 0.10))
        .cornerRadius(10)
    }

    private func formatDuration(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private func search() {
        errorMessage = nil
        results = []
        isSearching = true
        Task {
            defer { isSearching = false }
            do {
                results = try await FlightsAPI.search(
                    origins: [origin.code],
                    destinations: [destination.code],
                    date: date
                )
                if results.isEmpty {
                    errorMessage = "No non-stop flights found for that route + date."
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
