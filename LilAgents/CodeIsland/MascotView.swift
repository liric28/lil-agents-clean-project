import SwiftUI
import AppKit
import CoreText

// MARK: - Mascot Animation Speed Environment

private struct MascotSpeedKey: EnvironmentKey {
    static let defaultValue: Double = 1.0
}

extension EnvironmentValues {
    var mascotSpeed: Double {
        get { self[MascotSpeedKey.self] }
        set { self[MascotSpeedKey.self] = newValue }
    }
}

/// Routes a CLI source identifier to the correct pixel mascot view.
struct MascotView: View {
    let source: String
    let status: AgentStatus
    var size: CGFloat = 27
    @AppStorage(SettingsKey.mascotSpeed) private var speedPct = SettingsDefaults.mascotSpeed

    var body: some View {
        Group {
            switch source {
            case "codex":
                DexView(status: status, size: size)
            case "gemini":
                GeminiView(status: status, size: size)
            case "cursor":
                CursorView(status: status, size: size)
            case "copilot":
                CopilotView(status: status, size: size)
            case "qoder":
                QoderView(status: status, size: size)
            case "droid":
                DroidView(status: status, size: size)
            case "codebuddy":
                BuddyView(status: status, size: size)
            case "opencode":
                OpenCodeView(status: status, size: size)
            default:
//                ClawdView(status: status, size: size)
                GhostPixelMascotView(status: status, size: size)
            }
        }
        .environment(\.mascotSpeed, Double(speedPct) / 100.0)
    }
}

private struct GhostPixelMascotView: View {
    let status: AgentStatus
    var size: CGFloat = 27
    @Environment(\.mascotSpeed) private var speed

    private struct CursorPixel {
        let x: CGFloat
        let y: CGFloat
        let color: Color
    }

    private enum IndicatorStyle {
        case classicCursor
        case waterRing
    }

    private var indicatorStyle: IndicatorStyle {
        status == .processing ? .waterRing : .classicCursor
    }

    private let classicCursorPixels: [CursorPixel] = [
        .init(x: 54, y: 0, color: Color(red: 1.0, green: 0.0, blue: 122.0 / 255.0)),
        .init(x: 72, y: 0, color: Color(red: 1.0, green: 0.0, blue: 122.0 / 255.0)),
        .init(x: 54, y: 18, color: Color(red: 1.0, green: 27.0 / 255.0, blue: 87.0 / 255.0)),
        .init(x: 72, y: 18, color: Color(red: 1.0, green: 27.0 / 255.0, blue: 87.0 / 255.0)),
        .init(x: 54, y: 36, color: Color(red: 1.0, green: 55.0 / 255.0, blue: 52.0 / 255.0)),
        .init(x: 72, y: 36, color: Color(red: 1.0, green: 55.0 / 255.0, blue: 52.0 / 255.0)),
        .init(x: 54, y: 54, color: Color(red: 1.0, green: 82.0 / 255.0, blue: 17.0 / 255.0)),
        .init(x: 72, y: 54, color: Color(red: 1.0, green: 82.0 / 255.0, blue: 17.0 / 255.0)),
        .init(x: 54, y: 72, color: Color(red: 1.0, green: 113.0 / 255.0, blue: 0.0)),
        .init(x: 72, y: 72, color: Color(red: 1.0, green: 113.0 / 255.0, blue: 0.0)),
        .init(x: 54, y: 108, color: Color(red: 1.0, green: 180.0 / 255.0, blue: 0.0)),
        .init(x: 72, y: 108, color: Color(red: 1.0, green: 180.0 / 255.0, blue: 0.0)),
        .init(x: 54, y: 126, color: Color(red: 1.0, green: 214.0 / 255.0, blue: 0.0)),
        .init(x: 72, y: 126, color: Color(red: 1.0, green: 214.0 / 255.0, blue: 0.0)),
    ]

    private let waterRingPixels: [CursorPixel] = [
        .init(x: 36, y: 0, color: Color(red: 0.0, green: 240.0 / 255.0, blue: 1.0)),
        .init(x: 54, y: 0, color: Color(red: 0.0, green: 240.0 / 255.0, blue: 1.0)),
        .init(x: 72, y: 0, color: Color(red: 0.0, green: 240.0 / 255.0, blue: 1.0)),
        .init(x: 90, y: 0, color: Color(red: 0.0, green: 240.0 / 255.0, blue: 1.0)),
        .init(x: 18, y: 18, color: Color(red: 0.0, green: 208.0 / 255.0, blue: 1.0)),
        .init(x: 54, y: 18, color: Color(red: 0.0, green: 208.0 / 255.0, blue: 1.0)),
        .init(x: 72, y: 18, color: Color(red: 0.0, green: 208.0 / 255.0, blue: 1.0)),
        .init(x: 108, y: 18, color: Color(red: 0.0, green: 208.0 / 255.0, blue: 1.0)),
        .init(x: 0, y: 36, color: Color(red: 0.0, green: 176.0 / 255.0, blue: 1.0)),
        .init(x: 36, y: 36, color: Color(red: 0.0, green: 176.0 / 255.0, blue: 1.0)),
        .init(x: 54, y: 36, color: Color(red: 0.0, green: 176.0 / 255.0, blue: 1.0)),
        .init(x: 72, y: 36, color: Color(red: 0.0, green: 176.0 / 255.0, blue: 1.0)),
        .init(x: 90, y: 36, color: Color(red: 0.0, green: 176.0 / 255.0, blue: 1.0)),
        .init(x: 126, y: 36, color: Color(red: 0.0, green: 176.0 / 255.0, blue: 1.0)),
        .init(x: 0, y: 54, color: Color(red: 0.0, green: 144.0 / 255.0, blue: 1.0)),
        .init(x: 18, y: 54, color: Color(red: 0.0, green: 144.0 / 255.0, blue: 1.0)),
        .init(x: 36, y: 54, color: Color(red: 0.0, green: 144.0 / 255.0, blue: 1.0)),
        .init(x: 54, y: 54, color: Color(red: 0.0, green: 144.0 / 255.0, blue: 1.0)),
        .init(x: 72, y: 54, color: Color(red: 0.0, green: 144.0 / 255.0, blue: 1.0)),
        .init(x: 90, y: 54, color: Color(red: 0.0, green: 144.0 / 255.0, blue: 1.0)),
        .init(x: 108, y: 54, color: Color(red: 0.0, green: 144.0 / 255.0, blue: 1.0)),
        .init(x: 126, y: 54, color: Color(red: 0.0, green: 144.0 / 255.0, blue: 1.0)),
        .init(x: 0, y: 72, color: Color(red: 0.0, green: 110.0 / 255.0, blue: 1.0)),
        .init(x: 36, y: 72, color: Color(red: 0.0, green: 110.0 / 255.0, blue: 1.0)),
        .init(x: 54, y: 72, color: Color(red: 0.0, green: 110.0 / 255.0, blue: 1.0)),
        .init(x: 72, y: 72, color: Color(red: 0.0, green: 110.0 / 255.0, blue: 1.0)),
        .init(x: 90, y: 72, color: Color(red: 0.0, green: 110.0 / 255.0, blue: 1.0)),
        .init(x: 126, y: 72, color: Color(red: 0.0, green: 110.0 / 255.0, blue: 1.0)),
        .init(x: 18, y: 90, color: Color(red: 0.0, green: 73.0 / 255.0, blue: 1.0)),
        .init(x: 54, y: 90, color: Color(red: 0.0, green: 73.0 / 255.0, blue: 1.0)),
        .init(x: 72, y: 90, color: Color(red: 0.0, green: 73.0 / 255.0, blue: 1.0)),
        .init(x: 108, y: 90, color: Color(red: 0.0, green: 73.0 / 255.0, blue: 1.0)),
        .init(x: 36, y: 108, color: Color(red: 0.0, green: 37.0 / 255.0, blue: 1.0)),
        .init(x: 54, y: 108, color: Color(red: 0.0, green: 37.0 / 255.0, blue: 1.0)),
        .init(x: 72, y: 108, color: Color(red: 0.0, green: 37.0 / 255.0, blue: 1.0)),
        .init(x: 90, y: 108, color: Color(red: 0.0, green: 37.0 / 255.0, blue: 1.0)),
    ]

    // pixet fun-ghost matrix
    private let openMatrix: [[Int]] = [
        [0,0,1,1,1,1,0,0],
        [0,1,1,1,1,1,1,0],
        [1,1,0,0,1,0,0,1],
        [1,1,0,0,1,0,0,1],
        [1,1,1,1,1,1,1,1],
        [1,1,1,1,1,1,1,1],
        [1,1,1,1,1,1,1,1],
        [1,0,1,0,0,1,0,1],
    ]

    private let blinkMatrix: [[Int]] = [
        [0,0,1,1,1,1,0,0],
        [0,1,1,1,1,1,1,0],
        [1,1,1,1,1,1,1,1],
        [1,1,0,0,1,0,0,1],
        [1,1,1,1,1,1,1,1],
        [1,1,1,1,1,1,1,1],
        [1,1,1,1,1,1,1,1],
        [1,0,1,0,0,1,0,1],
    ]

    private let colors: [Color] = [
        Color(red: 0.35, green: 1.0, blue: 0.35),
        Color(red: 0.25, green: 0.92, blue: 0.32),
        Color(red: 0.18, green: 0.78, blue: 0.28),
        Color(red: 0.12, green: 0.62, blue: 0.22),
    ]

    private func isBlinking(_ t: Double) -> Bool {
        let cycle = max(2, 3 / max(speed, 0.65))
        let phase = t.truncatingRemainder(dividingBy: cycle)
        return phase > cycle * 0.76 && phase < cycle * 0.86
    }

    private func waterPixelOpacity(_ pixel: CursorPixel, time t: Double) -> Double {
        let cx: CGFloat = 71
        let cy: CGFloat = 71
        let px = pixel.x + 8
        let py = pixel.y + 8
        var angle = atan2(py - cy, px - cx)
        if angle < 0 { angle += 2 * .pi }

        let normalizedAngle = angle / (2 * .pi)
        let phase = (t * max(speed, 0.55) * 0.22).truncatingRemainder(dividingBy: 1)
        let delta = abs(normalizedAngle - phase)
        let wrappedDelta = min(delta, 1 - delta)
        let head = max(0, 1 - wrappedDelta / 0.14)
        let tail = max(0, 1 - wrappedDelta / 0.34)
        return min(1, 0.10 + tail * 0.35 + head * 0.65)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.04)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let blinking = isBlinking(t)
            let matrix = blinking ? blinkMatrix : openMatrix
            let pulse = 1.0
            // 像素比例
            let pixel = max(1.5, floor(size / 8.5))
            let ghostWidth = CGFloat(matrix[0].count) * pixel
            let ghostHeight = CGFloat(matrix.count) * pixel
            let indicatorPixels = indicatorStyle == .waterRing ? waterRingPixels : classicCursorPixels
            let indicatorSize = indicatorStyle == .waterRing ? max(pixel * 6.4, ghostHeight * 0.84) : pixel * 5
            let indicatorViewSize = indicatorStyle == .waterRing ? indicatorSize * 1.06 : indicatorSize * 1.2
            let indicatorSpacing = pixel + 4

            HStack(alignment: .center, spacing: indicatorSpacing) {
                Canvas { context, canvasSize in
                    let ox = (canvasSize.width - ghostWidth) / 2
                    let oy = (canvasSize.height - ghostHeight) / 2
                    for (rowIndex, row) in matrix.enumerated() {
                        for (colIndex, value) in row.enumerated() {
                            guard value == 1 else { continue }
                            let colorIndex = min(colors.count - 1, rowIndex / 2)
                            let rect = CGRect(
                                x: ox + CGFloat(colIndex) * pixel,
                                y: oy + CGFloat(rowIndex) * pixel,
                                width: pixel,
                                height: pixel
                            )
                            context.fill(Path(roundedRect: rect, cornerRadius: max(1, pixel * 0.16)), with: .color(colors[colorIndex].opacity(pulse)))
                        }
                    }
                }
                .frame(width: ghostWidth, height: ghostHeight)
                .shadow(color: colors[0].opacity(0.44), radius: 6)
                .shadow(color: colors[1].opacity(0.28), radius: 12)

                Canvas { context, canvasSize in
                    let scale = min(canvasSize.width / 142, canvasSize.height / 142)
                    let rectSize = 16 * scale
                    let cornerRadius = 2 * scale
                    let ox = (canvasSize.width - 142 * scale) / 2
                    let oy = (canvasSize.height - 142 * scale) / 2

                    for pixel in indicatorPixels {
                        let rect = CGRect(
                            x: ox + pixel.x * scale,
                            y: oy + pixel.y * scale,
                            width: rectSize,
                            height: rectSize
                        )

                        let opacity: Double
                        switch indicatorStyle {
                        case .classicCursor:
                            let cycle = max(0.42, 1.24 / max(speed, 0.5))
                            opacity = t.truncatingRemainder(dividingBy: cycle) < cycle * 0.48 ? 1 : 0
                        case .waterRing:
                            opacity = waterPixelOpacity(pixel, time: t)
                        }

                        context.fill(
                            Path(roundedRect: rect, cornerRadius: cornerRadius),
                            with: .color(pixel.color.opacity(opacity))
                        )
                    }
                }
                .frame(width: indicatorViewSize, height: indicatorViewSize)
                    .shadow(
                        color: (indicatorStyle == .waterRing
                            ? Color(red: 0.0, green: 176.0 / 255.0, blue: 1.0)
                            : Color(red: 1.0, green: 82.0 / 255.0, blue: 17.0 / 255.0)
                        ).opacity(0.34),
                        radius: 6
                    )
                    .shadow(
                        color: (indicatorStyle == .waterRing
                            ? Color(red: 0.0, green: 110.0 / 255.0, blue: 1.0)
                            : Color(red: 1.0, green: 82.0 / 255.0, blue: 17.0 / 255.0)
                        ).opacity(0.20),
                        radius: indicatorStyle == .waterRing ? 12 : 6
                    )
            }
            .frame(width: ghostWidth + indicatorSpacing + indicatorViewSize, height: max(ghostHeight, indicatorViewSize))
            .offset(x: 6)  // 整体向右偏移6点
        }
        .onAppear {
            DepartureMonoFont.registerIfNeeded()
        }
    }
}
