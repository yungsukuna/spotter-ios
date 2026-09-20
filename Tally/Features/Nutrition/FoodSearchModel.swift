import Foundation

/// Drives the Search tab of the add-food flow.
///
/// Debouncing and in-flight-task cancellation live here, independent of any
/// view, so the state machine (idle → searching → loaded/failed) can be
/// exercised in tests without a running UI or a real network. Every call to
/// ``query``'s setter cancels whatever search was previously scheduled or
/// running, so a user typing "chicken" one letter at a time produces exactly
/// one network call rather than five.
@MainActor
@Observable
final class FoodSearchModel {
    enum Phase: Equatable {
        case idle
        case searching
        case loaded([FoodRecord])
        case failed(FoodDataError)
    }

    private(set) var phase: Phase = .idle

    var query: String = "" {
        didSet {
            guard query != oldValue else { return }
            scheduleSearch()
        }
    }

    private let dataSource: any FoodDataSource
    private let debounce: Duration
    private var searchTask: Task<Void, Never>?

    init(dataSource: any FoodDataSource, debounce: Duration = .milliseconds(300)) {
        self.dataSource = dataSource
        self.debounce = debounce
    }

    /// Re-run the current query, e.g. after the user taps Retry on an error.
    /// A no-op on an empty query, since there is nothing to search for.
    func retry() {
        guard !trimmedQuery.isEmpty else { return }
        scheduleSearch()
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func scheduleSearch() {
        searchTask?.cancel()

        let trimmed = trimmedQuery
        guard !trimmed.isEmpty else {
            phase = .idle
            return
        }

        phase = .searching
        searchTask = Task { [weak self, dataSource, debounce] in
            do {
                try await Task.sleep(for: debounce)
            } catch {
                // Cancelled by a newer keystroke before the debounce elapsed.
                return
            }
            guard !Task.isCancelled, let self else { return }

            do {
                let results = try await dataSource.search(query: trimmed)
                guard !Task.isCancelled else { return }
                self.phase = .loaded(results)
            } catch let error as FoodDataError {
                guard !Task.isCancelled else { return }
                self.phase = .failed(error)
            } catch {
                guard !Task.isCancelled else { return }
                // A source is only allowed to throw `FoodDataError`, but the
                // protocol doesn't enforce that statically — fall back rather
                // than losing the failure silently.
                self.phase = .failed(.serverError(status: -1))
            }
        }
    }
}
