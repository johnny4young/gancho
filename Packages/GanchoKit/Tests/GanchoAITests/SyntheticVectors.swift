import Foundation

/// Deterministic vector fixtures shared by the `EmbeddingIndex` correctness
/// suite and its opt-in benchmark, so both score the same data and neither
/// flakes on a random draw.
enum SyntheticVectors {
    /// Pseudo-random vector in (-1, 1) from a seeded LCG.
    static func vector(seed: Int, dimension: Int) -> [Float] {
        var state = UInt64(bitPattern: Int64(seed &* 2_862_933_555_777_941_757 &+ 3_037_000_493))
        return (0..<dimension).map { _ in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Float(Int64(bitPattern: state) % 1000) / 1000.0
        }
    }

    static func normalized(_ vector: [Float]) -> [Float] {
        let norm = vector.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
        return vector.map { $0 / norm }
    }

    /// A vector whose cosine similarity to `reference` is exactly `target`:
    /// `target·û + √(1-target²)·v̂⊥`, where `v̂⊥` is a fresh random direction
    /// with the reference component projected out (Gram-Schmidt).
    static func vector(cosine target: Float, to reference: [Float], seed: Int) -> [Float] {
        let unit = normalized(reference)
        let noise = vector(seed: seed, dimension: reference.count)
        let projection = zip(noise, unit).reduce(Float(0)) { $0 + $1.0 * $1.1 }
        let perpendicular = normalized(zip(noise, unit).map { $0 - projection * $1 })
        let orthogonalWeight = (1 - target * target).squareRoot()
        return zip(unit, perpendicular).map { target * $0 + orthogonalWeight * $1 }
    }
}
