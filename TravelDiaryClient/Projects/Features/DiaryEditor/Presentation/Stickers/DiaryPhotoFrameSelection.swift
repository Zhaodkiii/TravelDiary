import Foundation

extension DiaryPhotoFrameCatalog {
    enum Style: String { case lightPaper, botanical }
    enum Accent: Hashable { case plain, curl, torn, tape, caption, botanical }
    struct Profile {
        let aspectRatio: CGFloat
        let style: Style
        let decoration: Int
        let accent: Accent
    }
    /// Curated style/decoration tags; aspect ratios are measured from the actual opening in pixels.
    static let profiles: [String: Profile] = [
        "diary_frame_81599c4dbb": Profile(aspectRatio: 0.680101, style: .lightPaper, decoration: 0, accent: .curl),
        "diary_frame_1794e316eb": Profile(aspectRatio: 0.679457, style: .lightPaper, decoration: 0, accent: .curl),
        "diary_frame_977e6006c7": Profile(aspectRatio: 0.837927, style: .botanical, decoration: 3, accent: .botanical),
        "diary_frame_cfe9c71f9a": Profile(aspectRatio: 0.880835, style: .lightPaper, decoration: 1, accent: .tape),
        "diary_frame_64000cb2ca": Profile(aspectRatio: 0.667882, style: .botanical, decoration: 3, accent: .botanical),
        "diary_frame_62154094ae": Profile(aspectRatio: 1.145579, style: .botanical, decoration: 3, accent: .botanical),
        "diary_frame_40f4355996": Profile(aspectRatio: 0.927093, style: .botanical, decoration: 3, accent: .botanical),
        "diary_frame_9754e7d86e": Profile(aspectRatio: 0.505066, style: .lightPaper, decoration: 0, accent: .plain),
        "diary_frame_d7c70c3d97": Profile(aspectRatio: 1.427600, style: .botanical, decoration: 3, accent: .botanical),
        "diary_frame_c3a046d48f": Profile(aspectRatio: 0.802171, style: .botanical, decoration: 3, accent: .botanical),
        "diary_frame_2aed1fbd2a": Profile(aspectRatio: 1.607020, style: .lightPaper, decoration: 1, accent: .tape),
        "diary_frame_ffa75cda88": Profile(aspectRatio: 0.685124, style: .lightPaper, decoration: 0, accent: .plain),
        "diary_frame_7ffa577d63": Profile(aspectRatio: 0.826964, style: .botanical, decoration: 3, accent: .botanical),
        "diary_frame_8073b107ff": Profile(aspectRatio: 0.853738, style: .botanical, decoration: 3, accent: .botanical),
        "diary_frame_db35575ef6": Profile(aspectRatio: 0.860311, style: .botanical, decoration: 3, accent: .botanical),
        "diary_frame_6af5b15a20": Profile(aspectRatio: 0.907525, style: .lightPaper, decoration: 1, accent: .tape),
        "diary_frame_0689278c91": Profile(aspectRatio: 0.846722, style: .botanical, decoration: 3, accent: .botanical),
        "diary_frame_9aaff1b86a": Profile(aspectRatio: 0.664849, style: .botanical, decoration: 3, accent: .botanical),
        "diary_frame_5904e10b83": Profile(aspectRatio: 0.833227, style: .botanical, decoration: 3, accent: .botanical),
        "diary_frame_63908a77c6": Profile(aspectRatio: 0.974519, style: .botanical, decoration: 3, accent: .botanical),
        "diary_frame_410b032fbe": Profile(aspectRatio: 0.727661, style: .botanical, decoration: 3, accent: .botanical),
        "diary_frame_e7161ec5e5": Profile(aspectRatio: 1.375466, style: .botanical, decoration: 3, accent: .botanical),
        "diary_frame_42d9e15407": Profile(aspectRatio: 1.087057, style: .botanical, decoration: 3, accent: .botanical),
        "diary_frame_18ed59f0ff": Profile(aspectRatio: 0.829645, style: .lightPaper, decoration: 0, accent: .plain),
        "diary_frame_ee5cecdfd5": Profile(aspectRatio: 0.579128, style: .botanical, decoration: 3, accent: .botanical),
        "diary_frame_41373ebf07": Profile(aspectRatio: 1.220970, style: .botanical, decoration: 3, accent: .botanical),
        "diary_frame_fcab74596d": Profile(aspectRatio: 0.850709, style: .botanical, decoration: 3, accent: .botanical),
        "diary_frame_dd5fee6df2": Profile(aspectRatio: 0.777170, style: .botanical, decoration: 3, accent: .botanical),
        "diary_frame_6950b1211b": Profile(aspectRatio: 0.879378, style: .botanical, decoration: 3, accent: .botanical),
        "diary_frame_1252486d05": Profile(aspectRatio: 1.603634, style: .lightPaper, decoration: 0, accent: .torn),
        "diary_frame_ff7be467dc": Profile(aspectRatio: 0.828284, style: .lightPaper, decoration: 1, accent: .tape),
        "diary_frame_85e952845d": Profile(aspectRatio: 0.729449, style: .botanical, decoration: 3, accent: .botanical),
        "diary_frame_b398250f22": Profile(aspectRatio: 1.049573, style: .lightPaper, decoration: 1, accent: .caption),
        "diary_frame_9b16ec0763": Profile(aspectRatio: 0.656408, style: .botanical, decoration: 3, accent: .botanical),
        "diary_frame_d0136a6d1f": Profile(aspectRatio: 0.947821, style: .botanical, decoration: 3, accent: .botanical),
        "diary_frame_0d320dbabd": Profile(aspectRatio: 2.271380, style: .lightPaper, decoration: 1, accent: .tape),
        "diary_frame_f625a5255e": Profile(aspectRatio: 1.900179, style: .lightPaper, decoration: 1, accent: .caption),
        "diary_frame_15003062b9": Profile(aspectRatio: 1.698220, style: .lightPaper, decoration: 1, accent: .caption),
        "diary_frame_65ffe1a6dd": Profile(aspectRatio: 1.758381, style: .lightPaper, decoration: 1, accent: .tape),
        "diary_frame_5677d18169": Profile(aspectRatio: 1.356837, style: .lightPaper, decoration: 1, accent: .tape),
        "diary_frame_75291a4942": Profile(aspectRatio: 0.878840, style: .lightPaper, decoration: 1, accent: .tape),
        "diary_frame_467d6c6abf": Profile(aspectRatio: 1.348936, style: .lightPaper, decoration: 1, accent: .tape),
        "diary_frame_4ed7524bd6": Profile(aspectRatio: 0.757484, style: .botanical, decoration: 3, accent: .botanical),
        "diary_frame_d95bc23c2f": Profile(aspectRatio: 0.752035, style: .botanical, decoration: 3, accent: .botanical),
        "diary_frame_0dd6dca833": Profile(aspectRatio: 0.961474, style: .botanical, decoration: 3, accent: .botanical),
        "diary_frame_0029c7a8ec": Profile(aspectRatio: 0.635514, style: .botanical, decoration: 3, accent: .botanical),
        "diary_frame_ede76dbcfb": Profile(aspectRatio: 0.631737, style: .botanical, decoration: 3, accent: .botanical),
        "diary_frame_ed993f6e1e": Profile(aspectRatio: 0.807650, style: .botanical, decoration: 3, accent: .botanical),
        "diary_frame_eac2df4b3c": Profile(aspectRatio: 3.454958, style: .botanical, decoration: 3, accent: .botanical),
        "diary_frame_4bd4c7dbf7": Profile(aspectRatio: 1.824691, style: .botanical, decoration: 3, accent: .botanical),
        "diary_frame_31368e04ed": Profile(aspectRatio: 0.464461, style: .lightPaper, decoration: 0, accent: .torn),
        "diary_frame_bce1a282d6": Profile(aspectRatio: 1.793868, style: .botanical, decoration: 3, accent: .botanical),
        "diary_frame_79d0ae6346": Profile(aspectRatio: 1.669920, style: .botanical, decoration: 3, accent: .botanical),
        "diary_frame_58e7860208": Profile(aspectRatio: 0.783268, style: .botanical, decoration: 3, accent: .botanical),
        "diary_frame_539ead4430": Profile(aspectRatio: 0.675513, style: .botanical, decoration: 3, accent: .botanical),
    ]

    static func select(for sizes: [CGSize], style: Style = .lightPaper) -> [Item] {
        let styled = items.filter { profiles[$0.id]?.style == style }
        guard !styled.isEmpty else { return [] }
        var used: [String: Int] = [:]
        var usedAccents = Set<Accent>()
        func orientation(_ ratio: CGFloat) -> Int { ratio < 0.9 ? -1 : ratio > 1.1 ? 1 : 0 }
        return sizes.map { size in
            let ratio = max(0.01, size.width / max(1, size.height))
            let sameOrientation = styled.filter {
                let candidateRatio = profiles[$0.id]!.aspectRatio
                // Square photos can use gently portrait/landscape paper without exhausting one or two frames immediately.
                return orientation(ratio) == 0 ? (0.8...1.25).contains(candidateRatio)
                    : orientation(candidateRatio) == orientation(ratio)
            }
            let candidates = sameOrientation.isEmpty ? styled : sameOrientation
            let fresh = candidates.filter { used[$0.id, default: 0] == 0 }
            let pool = fresh.isEmpty ? candidates : fresh
            let chosen = pool.min { a, b in
                let pa = profiles[a.id]!, pb = profiles[b.id]!
                if fresh.isEmpty {
                    // When repeats are necessary, keep the page quiet with simpler decoration.
                    if pa.decoration != pb.decoration { return pa.decoration < pb.decoration }
                    if used[a.id, default: 0] != used[b.id, default: 0] { return used[a.id, default: 0] < used[b.id, default: 0] }
                }
                let sa = abs(log(pa.aspectRatio / ratio)) + CGFloat(pa.decoration) * 0.06
                    + (usedAccents.contains(pa.accent) ? 0.3 : 0)
                let sb = abs(log(pb.aspectRatio / ratio)) + CGFloat(pb.decoration) * 0.06
                    + (usedAccents.contains(pb.accent) ? 0.3 : 0)
                return sa == sb ? a.id < b.id : sa < sb
            }!
            used[chosen.id, default: 0] += 1
            usedAccents.insert(profiles[chosen.id]!.accent)
            return chosen
        }
    }
}
