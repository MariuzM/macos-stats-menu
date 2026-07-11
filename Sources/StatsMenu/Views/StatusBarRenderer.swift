import AppKit

enum StatusBarRenderer {
    static let barHeight: CGFloat = 18
    static let barWidth: CGFloat = 6
    static let gap: CGFloat = 3
    static let cornerRadius: CGFloat = 1.5
    static let netGap: CGFloat = 10
    static let netFont = NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .regular)
    private static let netWidth = ("000.0 MB/s" as NSString).size(withAttributes: [.font: netFont]).width

    struct Metric {
        let value: Double
        let color: NSColor
    }

    static func signature(for engine: StatsEngine) -> String {
        let bars = [engine.cpu, engine.memory.percent, engine.gpu].map(fillPixels)
        return "\(bars)|\(rate(engine.network.downBytesPerSec))|\(rate(engine.network.upBytesPerSec))"
    }

    private static func fillPixels(_ value: Double) -> Int {
        let fraction = max(0, min(1, value / 100))
        return Int((barHeight * CGFloat(fraction)).rounded())
    }

    static func image(for engine: StatsEngine) -> NSImage {
        let metrics = [
            Metric(value: engine.cpu, color: .systemBlue),
            Metric(value: engine.memory.percent, color: .systemGreen),
            Metric(value: engine.gpu, color: .systemPurple),
        ]

        let thickness = NSStatusBar.system.thickness
        let barsWidth = barWidth * CGFloat(metrics.count) + gap * CGFloat(metrics.count - 1)

        let downText = rate(engine.network.downBytesPerSec)
        let upText = rate(engine.network.upBytesPerSec)
        let downAttrs: [NSAttributedString.Key: Any] = [.font: netFont, .foregroundColor: NSColor.systemTeal]
        let upAttrs: [NSAttributedString.Key: Any] = [.font: netFont, .foregroundColor: NSColor.systemOrange]
        let downSize = (downText as NSString).size(withAttributes: downAttrs)
        let upSize = (upText as NSString).size(withAttributes: upAttrs)

        let totalWidth = barsWidth + netGap + netWidth
        let yInset = (thickness - barHeight) / 2

        let image = NSImage(size: NSSize(width: totalWidth, height: thickness))
        image.lockFocus()

        var x: CGFloat = 0
        for metric in metrics {
            drawBar(value: metric.value, color: metric.color,
                    in: NSRect(x: x, y: yInset, width: barWidth, height: barHeight))
            x += barWidth + gap
        }

        let netX = barsWidth + netGap
        let lineHeight = downSize.height
        let blockBottom = (thickness - lineHeight * 2) / 2
        (downText as NSString).draw(at: NSPoint(x: netX + netWidth - downSize.width, y: blockBottom + lineHeight),
                                    withAttributes: downAttrs)
        (upText as NSString).draw(at: NSPoint(x: netX + netWidth - upSize.width, y: blockBottom),
                                  withAttributes: upAttrs)

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func drawBar(value: Double, color: NSColor, in rect: NSRect) {
        let track = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
        color.withAlphaComponent(0.18).setFill()
        track.fill()

        let fraction = max(0, min(1, value / 100))
        guard fraction > 0 else { return }
        let fillHeight = max(1, rect.height * CGFloat(fraction))
        let fillRect = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: fillHeight)
        let fill = NSBezierPath(roundedRect: fillRect, xRadius: cornerRadius, yRadius: cornerRadius)
        color.setFill()
        fill.fill()
    }

    private static func rate(_ bps: Double) -> String {
        guard bps >= 1024 else { return "0 KB/s" }
        let units = ["KB/s", "MB/s", "GB/s"]
        var value = bps / 1024
        var unit = 0
        while value >= 1000 && unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        let number = (unit == 0 || value >= 100)
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
        return "\(number) \(units[unit])"
    }
}
