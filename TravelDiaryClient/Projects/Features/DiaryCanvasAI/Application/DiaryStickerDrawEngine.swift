import Foundation

/// Deterministic sampling. Resource preparation and publication happen outside this pure engine.
nonisolated enum DiaryStickerDrawEngine {
    struct Candidate: Equatable {
        var id: String
        var pack: String
        var themeMatches = false
    }
    struct Result: Equatable {
        var ids: [String]
        var seed: UInt64
    }
    struct Generator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var x = state
            x = (x ^ (x >> 30)) &* 0xBF58476D1CE4E5B9
            x = (x ^ (x >> 27)) &* 0x94D049BB133111EB
            return x ^ (x >> 31)
        }
    }
    static func draw(candidates: [Candidate], current: [String], kept: Set<String>, excluded: Set<String>, history: [[String]], seed: UInt64) -> Result {
        var rng = Generator(state: seed)
        let locked = current.filter { kept.contains($0) }
        if !current.isEmpty && locked.count == current.count { return .init(ids: current, seed: seed) }
        let n = 3 + Int(rng.next() % 4)
        let target = locked.count >= 6 ? min(8, current.count) : max(n, locked.count)
        var seen = Set<String>()
        var pool = candidates.filter { seen.insert($0.id).inserted && !excluded.contains($0.id) && !current.contains($0.id) }
        var picked: [String] = []
        let recent = Set(history.suffix(2).flatMap { $0 })
        var preferredPack = candidates.first { locked.contains($0.id) }?.pack
        while picked.count < target - locked.count && !pool.isEmpty {
            let fresh = pool.filter { !recent.contains($0.id) }
            let available = fresh.isEmpty ? pool : fresh
            let weights = available.map { item in
                (item.themeMatches ? 3 : 1) * (preferredPack == item.pack ? 2 : 1)
            }
            var ticket = Int(rng.next() % UInt64(weights.reduce(0, +)))
            var index = 0
            for i in weights.indices {
                if ticket < weights[i] { index = i; break }
                ticket -= weights[i]
            }
            let item = available[index]
            if preferredPack == nil { preferredPack = item.pack }
            picked.append(item.id); pool.removeAll { $0.id == item.id }
        }
        // A tiny pool must never appear to successfully replace an unchanged batch.
        if picked.isEmpty && !current.isEmpty { return .init(ids: current, seed: rng.state) }
        var result: [String] = []
        for id in current {
            if kept.contains(id) { result.append(id) }
            else if !picked.isEmpty { result.append(picked.removeFirst()) }
        }
        result += picked
        return .init(ids: Array(result.prefix(8)), seed: rng.state)
    }
}
