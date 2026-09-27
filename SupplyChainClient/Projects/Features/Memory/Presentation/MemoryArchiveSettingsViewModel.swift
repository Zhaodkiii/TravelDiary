import Combine
import Foundation

@MainActor
final class MemoryArchiveSettingsViewModel: ObservableObject {
    @Published private(set) var records: [MemoryRecord] = []
    @Published var preferences: MemoryPreferences = .default
    @Published var searchText: String = ""
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let loadUseCase: LoadMemoryArchiveUseCase
    private let saveUseCase: SaveMemoryUseCase
    private let updateUseCase: UpdateMemoryUseCase
    private let deleteUseCase: DeleteMemoryUseCase
    private let preferencesUseCase: MemoryPreferencesUseCase
    private var cancellables: Set<AnyCancellable> = []

    init(
        loadUseCase: LoadMemoryArchiveUseCase,
        saveUseCase: SaveMemoryUseCase,
        updateUseCase: UpdateMemoryUseCase,
        deleteUseCase: DeleteMemoryUseCase,
        preferencesUseCase: MemoryPreferencesUseCase
    ) {
        self.loadUseCase = loadUseCase
        self.saveUseCase = saveUseCase
        self.updateUseCase = updateUseCase
        self.deleteUseCase = deleteUseCase
        self.preferencesUseCase = preferencesUseCase
        bindSearch()
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        preferences = await preferencesUseCase.load()
        await refresh()
    }

    func refresh() async {
        do {
            records = try await loadUseCase.execute(query: searchText)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func savePreferences() {
        let snapshot = preferences
        Task {
            do {
                try await preferencesUseCase.save(snapshot)
                await refresh()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func addMemory(title: String, content: String, pinned: Bool) async {
        do {
            _ = try await saveUseCase.execute(title: title, content: content, pinned: pinned)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateMemory(_ record: MemoryRecord, title: String, content: String, pinned: Bool) async {
        do {
            _ = try await updateUseCase.execute(id: record.id, title: title, content: content, pinned: pinned)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteMemory(_ record: MemoryRecord) async {
        do {
            try await deleteUseCase.execute(id: record.id)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(at offsets: IndexSet) {
        let selected = offsets.compactMap { records.indices.contains($0) ? records[$0] : nil }
        Task {
            for record in selected {
                await deleteMemory(record)
            }
        }
    }

    func clearAll() async {
        do {
            try await deleteUseCase.deleteAll()
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func bindSearch() {
        $searchText
            .dropFirst()
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.refresh() }
            }
            .store(in: &cancellables)
    }
}

