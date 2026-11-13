import AppKit
import CoreText

extension LEDMatrix {
    /// Rasterises an emoji (or any single character) down to the 9×9 display.
    ///
    /// The glyph is drawn large, cropped to its inked area, and each of the 81
    /// cells is lit when it is mostly covered and not markedly darker than the
    /// rest of the glyph. That keeps dark features such as eyes and mouths as
    /// holes in an otherwise lit shape.
    init(glyph text: String) {
        self.init()
        if let drawn = Self.handDrawn[text.replacingOccurrences(of: "\u{FE0F}", with: "")] {
            self = drawn
            return
        }
        let size = 144
        let font = NSFont(name: "Apple Color Emoji", size: 110) ?? NSFont.systemFont(ofSize: 110)
        let attributed = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: NSColor.white,
        ])
        let line = CTLineCreateWithAttributedString(attributed)

        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        guard let ctx = CGContext(
            data: &pixels, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        let bounds = CTLineGetImageBounds(line, ctx)
        ctx.textPosition = CGPoint(x: (CGFloat(size) - bounds.width) / 2 - bounds.minX,
                                   y: (CGFloat(size) - bounds.height) / 2 - bounds.minY)
        CTLineDraw(line, ctx)

        // Bitmap rows run top to bottom. Find the inked bounding box.
        func alpha(_ x: Int, _ y: Int) -> Int { Int(pixels[(y * size + x) * 4 + 3]) }
        var minX = size, maxX = -1, minY = size, maxY = -1
        for y in 0..<size {
            for x in 0..<size where alpha(x, y) > 128 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return }

        // Square crop around the glyph so it fills the display without distortion.
        let side = max(maxX - minX, maxY - minY) + 1
        let originX = Double(minX + maxX + 1) / 2 - Double(side) / 2
        let originY = Double(minY + maxY + 1) / 2 - Double(side) / 2
        let cell = Double(side) / 9

        var coverage = [Double](repeating: 0, count: 81)
        var luminance = [Double](repeating: 0, count: 81)
        for r in 0..<9 {
            for c in 0..<9 {
                var a = 0.0, lum = 0.0, n = 0.0
                let x0 = Int((originX + Double(c) * cell).rounded(.down))
                let x1 = Int((originX + Double(c + 1) * cell).rounded(.up))
                let y0 = Int((originY + Double(r) * cell).rounded(.down))
                let y1 = Int((originY + Double(r + 1) * cell).rounded(.up))
                for y in y0..<y1 {
                    for x in x0..<x1 {
                        n += 1
                        guard x >= 0, x < size, y >= 0, y < size else { continue }
                        let i = (y * size + x) * 4
                        a += Double(pixels[i + 3]) / 255
                        // Premultiplied, so this is already weighted by coverage.
                        lum += (0.299 * Double(pixels[i]) + 0.587 * Double(pixels[i + 1])
                            + 0.114 * Double(pixels[i + 2])) / 255
                    }
                }
                coverage[r * 9 + c] = n > 0 ? a / n : 0
                luminance[r * 9 + c] = a > 0 ? lum / a : 0
            }
        }

        let solid = (0..<81).filter { coverage[$0] >= 0.5 }.map { luminance[$0] }.sorted()
        let typical = solid.isEmpty ? 0 : solid[solid.count * 3 / 4]
        for i in 0..<81 {
            bits[i] = coverage[i] >= 0.42 && luminance[i] >= typical * 0.72
        }
        centre()
    }

    /// Shifts the lit area to the middle of the display.
    private mutating func centre() {
        let lit = (0..<81).filter { bits[$0] }
        guard let top = lit.map({ $0 / 9 }).min(), let bottom = lit.map({ $0 / 9 }).max(),
              let left = lit.map({ $0 % 9 }).min(), let right = lit.map({ $0 % 9 }).max() else { return }
        let dy = (8 - bottom - top) / 2, dx = (8 - right - left) / 2
        guard dx != 0 || dy != 0 else { return }
        var moved = [Bool](repeating: false, count: 81)
        for i in lit { moved[(i / 9 + dy) * 9 + (i % 9 + dx)] = true }
        bits = moved
    }

    /// The frame as nine lines of text, for checking a rendering in a terminal.
    var ascii: String {
        (0..<9).map { r in (0..<9).map { bits[r * 9 + $0] ? "██" : "  " }.joined() }.joined(separator: "\n")
    }

    /// Pixel art for common emojis, where automatic rasterising loses the detail.
    static let handDrawn: [String: LEDMatrix] = [
        "😀": LEDMatrix(["..#####..", ".#######.", "##.###.##", "##.###.##", "#########",
                         "#.#####.#", "##.....##", ".#######.", "..#####.."]),
        "🙂": LEDMatrix(["..#####..", ".#######.", "##.###.##", "##.###.##", "#########",
                         "#########", "##.###.##", ".##...##.", "..#####.."]),
        "🙁": LEDMatrix(["..#####..", ".#######.", "##.###.##", "##.###.##", "#########",
                         "###...###", "##.###.##", ".#######.", "..#####.."]),
        "😎": LEDMatrix(["..#####..", ".#######.", "#########", "#...#...#", "#...#...#",
                         "#########", "##.....##", ".##...##.", "..#####.."]),
        "😉": LEDMatrix(["..#####..", ".#######.", "##.######", "##.##...#", "#########",
                         "#.#####.#", "##.....##", ".#######.", "..#####.."]),
        "❤": LEDMatrix([".........", ".##...##.", "####.####", "#########", "#########",
                        ".#######.", "..#####..", "...###...", "....#...."]),
        "👍": LEDMatrix(["....#....", "...##....", "...##....", "..###....", "#.######.",
                         "#.######.", "#.######.", "#.#####..", "#.####..."]),
        "👎": LEDMatrix(["#.####...", "#.#####..", "#.######.", "#.######.", "#.######.",
                         "..###....", "...##....", "...##....", "....#...."]),
        "🔥": LEDMatrix(["....#....", "...##....", "...###...", "..####.#.", ".#####.##",
                         ".###.####", ".##...###", ".##...##.", "..#####.."]),
        "⭐": LEDMatrix(["....#....", "....#....", "...###...", "#########", ".#######.",
                        "..#####..", "..#####..", ".##...##.", ".#.....#."]),
        "✅": LEDMatrix([".........", "........#", ".......##", "......##.", "#....##..",
                        "##..##...", ".####....", "..##.....", "........."]),
        "❌": LEDMatrix(["#.......#", ".#.....#.", "..#...#..", "...#.#...", "....#....",
                        "...#.#...", "..#...#..", ".#.....#.", "#.......#"]),
        "🎵": LEDMatrix(["...#####.", "...#####.", "...#...#.", "...#...#.", "...#...#.",
                         ".###.###.", "####.###.", ".##...#..", "........."]),
        "☀": LEDMatrix(["#...#...#", ".#.....#.", "...###...", "..#####..", "#.#####.#",
                        "..#####..", "...###...", ".#.....#.", "#...#...#"]),
        "🌙": LEDMatrix(["...###...", "..###....", ".###.....", ".###.....", ".###.....",
                         ".####....", "..#####.#", "...#####.", "........."]),
        "💀": LEDMatrix(["..#####..", ".#######.", "#########", "#..###..#", "#..###..#",
                         "####.####", ".#######.", "..#.#.#..", "..#.#.#.."]),
        "👻": LEDMatrix(["..#####..", ".#######.", "##.###.##", "##.###.##", "#########",
                         "#########", "#########", "#########", "#.##.##.#"]),
        "☕": LEDMatrix(["..#.#.#..", "..#.#.#..", ".........", "#######..", "#######.#",
                        "#######.#", "#######..", ".#####...", "#########"]),
        "🔔": LEDMatrix(["....#....", "...###...", "..#####..", "..#####..", "..#####..",
                         ".#######.", "#########", ".........", "...###..."]),
        "⚡": LEDMatrix([".....##..", "....##...", "...##....", "..######.", ".....##..",
                        "....##...", "...##....", "..##.....", ".##......"]),
    ]
}
