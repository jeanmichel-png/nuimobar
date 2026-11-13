import Foundation

/// A 9×9 frame for the Nuimo's LED matrix.
struct LEDMatrix: Equatable {
    var bits = [Bool](repeating: false, count: 81)

    init() {}

    /// Nine rows of nine characters; anything other than space or "." is lit.
    init(_ rows: [String]) {
        for (r, row) in rows.prefix(9).enumerated() {
            for (c, ch) in row.prefix(9).enumerated() where ch != " " && ch != "." {
                bits[r * 9 + c] = true
            }
        }
    }

    /// 13-byte payload: 81 bits (LSB first, row by row), brightness, duration in 0.1 s.
    func payload(brightness: Double = 1.0, seconds: Double = 1.5, fade: Bool = false) -> Data {
        var bytes = [UInt8](repeating: 0, count: 13)
        for (i, on) in bits.enumerated() where on {
            bytes[i / 8] |= 1 << UInt8(i % 8)
        }
        if fade { bytes[10] |= 0x10 }
        bytes[11] = UInt8(max(0, min(255, brightness * 255)))
        bytes[12] = UInt8(max(0, min(255, seconds * 10)))
        return Data(bytes)
    }

    /// A bar that fills from the bottom, for levels in 0...1.
    static func level(_ value: Double) -> LEDMatrix {
        var m = LEDMatrix()
        let lit = Int((max(0, min(1, value)) * 9).rounded())
        for r in 0..<9 where (8 - r) < lit {
            for c in 2...6 { m.bits[r * 9 + c] = true }
        }
        if lit == 0 { for c in 2...6 where c % 2 == 0 { m.bits[8 * 9 + c] = true } }
        return m
    }

    static let playPause = LEDMatrix([
        ".........",
        ".#...#.#.",
        ".##..#.#.",
        ".###.#.#.",
        ".###.#.#.",
        ".###.#.#.",
        ".##..#.#.",
        ".#...#.#.",
        ".........",
    ])

    static let next = LEDMatrix([
        ".........",
        ".#...#...",
        ".##..##..",
        ".###.###.",
        ".########",
        ".###.###.",
        ".##..##..",
        ".#...#...",
        ".........",
    ])

    static let previous = LEDMatrix([
        ".........",
        "...#...#.",
        "..##..##.",
        ".###.###.",
        "########.",
        ".###.###.",
        "..##..##.",
        "...#...#.",
        ".........",
    ])

    static let mute = LEDMatrix([
        ".........",
        "#.......#",
        ".#.....#.",
        "..#...#..",
        "...#.#...",
        "....#....",
        "...#.#...",
        "..#...#..",
        ".#.....#.",
    ])

    static let hoverOn = LEDMatrix([
        "....#....",
        "...###...",
        "..#.#.#..",
        "....#....",
        "....#....",
        "....#....",
        "..#.#.#..",
        "...###...",
        "....#....",
    ])

    static let hoverOff = LEDMatrix([
        ".........",
        ".........",
        ".........",
        ".........",
        ".#######.",
        ".........",
        ".........",
        ".........",
        ".........",
    ])

    static let dot = LEDMatrix([
        ".........",
        ".........",
        ".........",
        "...###...",
        "...###...",
        "...###...",
        ".........",
        ".........",
        ".........",
    ])

    static let hello = LEDMatrix([
        ".........",
        "...###...",
        "..#...#..",
        ".#.....#.",
        ".#.....#.",
        ".#.....#.",
        "..#...#..",
        "...###...",
        ".........",
    ])
}
