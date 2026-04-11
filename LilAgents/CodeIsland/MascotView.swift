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

    private let svgCursorPixels: [CursorPixel] = [
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

    // pixet fun-ghost matrix
    private let openMatrix: [[Int]] = [
        [0,0,1,1,1,1,0,0],
        [0,1,1,1,1,1,1,0],
        [1,1,0,1,1,0,1,1],
        [1,1,1,1,1,1,1,1],
        [1,1,1,1,1,1,1,1],
        [1,1,1,1,1,1,1,1],
        [1,1,1,1,1,1,1,1],
        [1,0,1,0,0,1,0,1],
    ]

    private let blinkMatrix: [[Int]] = [
        [0,0,1,1,1,1,0,0],
        [0,1,1,1,1,1,1,0],
        [1,1,1,1,1,1,1,1],
        [1,1,1,1,1,1,1,1],
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

    private func isCursorVisible(_ t: Double) -> Bool {
        let cycle = max(0.42, 1.24 / max(speed, 0.5))
        return t.truncatingRemainder(dividingBy: cycle) < cycle * 0.48
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.04)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let blinking = isBlinking(t)
            let cursorVisible = isCursorVisible(t)
            let matrix = blinking ? blinkMatrix : openMatrix
            let pulse = 1.0
            // 像素比例
            let pixel = max(1.5, floor(size / 8.5))
            let ghostWidth = CGFloat(matrix[0].count) * pixel
            let ghostHeight = CGFloat(matrix.count) * pixel
            let cursorHeight = pixel * 5
            let cursorSize = cursorHeight
            let cursorViewSize = cursorSize * 1.2
            let cursorSpacing = pixel + 1

            HStack(alignment: .center, spacing: cursorSpacing) {
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

                // 光标闪动
                Canvas { context, canvasSize in
                    let scale = min(canvasSize.width / 142, canvasSize.height / 142)*1.1
                    let rectSize = 16 * scale
                    let cornerRadius = 2 * scale
                    let ox = (canvasSize.width - 142 * scale) / 2
                    let oy = (canvasSize.height - 142 * scale) / 2

                    for pixel in svgCursorPixels {
                        let rect = CGRect(
                            x: ox + pixel.x * scale,
                            y: oy + pixel.y * scale,
                            width: rectSize,
                            height: rectSize
                        )
                        context.fill(
                            Path(roundedRect: rect, cornerRadius: cornerRadius),
                            with: .color(pixel.color)
                        )
                    }
                }
                .frame(width: cursorViewSize, height: cursorViewSize)
                    .shadow(color: Color(red: 1.0, green: 82.0 / 255.0, blue: 17.0 / 255.0).opacity(0.35), radius: 6)
                    .opacity(cursorVisible ? 1 : 0)
            }
            .frame(width: ghostWidth + cursorSpacing + cursorViewSize, height: max(ghostHeight, cursorViewSize))
            .offset(x: 6)  // 整体向右偏移6点
        }
        .onAppear {
            DepartureMonoFont.registerIfNeeded()
        }
    }
}
