//
//  FanCurveEditorView.swift
//  SMCController
//

import SwiftUI

// 그래프에서 사용할 포인트 타입은 FanPolicy.swift의 FanCurvePoint와 동일해야 합니다.
// public struct FanCurvePoint { var tempC: Double; var rpm: Int }

struct FanCurveEditorView: View {
    @Binding var points: [FanCurvePoint]
    @Binding var minC: Double
    @Binding var maxC: Double
    @Binding var minRPM: Double
    @Binding var maxRPM: Double

    // 현재 온도/적용 RPM 표시(옵션)
    var currentTemp: Double?
    var currentRPM: Int?

    private let padding: CGFloat = 32
    private let pointRadius: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 배경 그리드
                grid(in: geo.size)

                // 곡선(선형 보간)
                path(in: geo.size)
                    .stroke(Color.accentColor, lineWidth: 2)

                // 포인트 (드래그만 허용)
                ForEach(Array(points.enumerated()), id: \.offset) { (idx, p) in
                    let pos = toPoint(p, in: geo.size)
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: pointRadius * 2, height: pointRadius * 2)
                        .position(pos)
                        .gesture(dragGesture(for: idx, in: geo.size))
                        .help("Drag to move.")
                }

                // 현재 온도/적용 RPM 보조선
                if let t = currentTemp {
                    let x = xFor(t, in: geo.size)
                    Path { p in
                        p.move(to: CGPoint(x: x, y: padding))
                        p.addLine(to: CGPoint(x: x, y: geo.size.height - padding))
                    }
                    .stroke(Color.orange.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4,4]))
                }
                if let t = currentTemp, let r = currentRPM {
                    let y = yFor(Double(r), in: geo.size)
                    Path { p in
                        p.move(to: CGPoint(x: padding, y: y))
                        p.addLine(to: CGPoint(x: geo.size.width - padding, y: y))
                    }
                    .stroke(Color.green.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4,4]))

                    // 교차점 라벨
                    let x = xFor(t, in: geo.size)
                    Text("\(Int(round(t)))°C / \(r) RPM")
                        .font(.caption)
                        .padding(6)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
                        .position(x: min(max(x + 80, padding + 60), geo.size.width - padding - 60),
                                  y: min(max(y - 20, padding + 12), geo.size.height - padding - 12))
                }
            }
            .contentShape(Rectangle())
        }
        .frame(minHeight: 240)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        }
    }

    // MARK: - Drawing

    private func grid(in size: CGSize) -> some View {
        Canvas { ctx, sz in
            let rect = plotRect(in: sz)
            let stepX = rect.width / 6
            let stepY = rect.height / 4

            var gridPath = Path()
            for i in 0...6 {
                let x = rect.minX + CGFloat(i) * stepX
                gridPath.move(to: CGPoint(x: x, y: rect.minY))
                gridPath.addLine(to: CGPoint(x: x, y: rect.maxY))
            }
            for i in 0...4 {
                let y = rect.minY + CGFloat(i) * stepY
                gridPath.move(to: CGPoint(x: rect.minX, y: y))
                gridPath.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
            ctx.stroke(gridPath, with: .color(.secondary.opacity(0.25)), lineWidth: 1)

            // 테두리
            ctx.stroke(Path(rect), with: .color(.secondary.opacity(0.5)), lineWidth: 1)

            // 축 라벨(간략)
            for i in 0...6 {
                let ratio = Double(i) / 6.0
                let temp = minC + ratio * (maxC - minC)
                let text = Text("\(Int(round(temp)))°")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                let x = rect.minX + CGFloat(ratio) * rect.width
                let y = rect.maxY + 4
                ctx.draw(text, at: CGPoint(x: x, y: y), anchor: .top)
            }
            for i in 0...4 {
                let ratio = Double(i) / 4.0
                let rpm = Int(round(minRPM + (1 - ratio) * (maxRPM - minRPM)))
                let text = Text("\(rpm)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                let x = rect.minX - 6
                let y = rect.minY + CGFloat(ratio) * rect.height
                ctx.draw(text, at: CGPoint(x: x, y: y), anchor: .trailing)
            }
        }
    }

    private func path(in size: CGSize) -> Path {
        let sorted = points.sorted()
        var path = Path()
        guard let first = sorted.first else { return path }
        path.move(to: toPoint(first, in: size))
        for p in sorted.dropFirst() {
            path.addLine(to: toPoint(p, in: size))
        }
        return path
    }

    // MARK: - Gestures

    private func dragGesture(for index: Int, in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                // 위치 -> 값 변환
                var t = tempForX(value.location.x, in: size)
                var r = rpmForY(value.location.y, in: size)

                // 1) 범위 클램프
                t = min(max(t, minC), maxC)
                r = min(max(r, minRPM), maxRPM)

                // 2) 정수 보정 (온도와 RPM 모두 반올림)
                t = round(t) // 1°C 단위
                r = round(r) // 1 RPM 단위

                // 3) 반올림 후 다시 범위 클램프(경계 넘김 방지)
                t = min(max(t, minC), maxC)
                r = min(max(r, minRPM), maxRPM)

                points[index] = FanCurvePoint(tempC: t, rpm: Int(r))
                points.sort()
            }
    }

    // MARK: - Coordinate transforms

    private func plotRect(in size: CGSize) -> CGRect {
        CGRect(x: padding, y: padding, width: size.width - 2 * padding, height: size.height - 2 * padding)
    }

    private func toPoint(_ p: FanCurvePoint, in size: CGSize) -> CGPoint {
        CGPoint(x: xFor(p.tempC, in: size), y: yFor(Double(p.rpm), in: size))
    }

    private func xFor(_ temp: Double, in size: CGSize) -> CGFloat {
        let rect = plotRect(in: size)
        let ratio = (temp - minC) / max(1e-6, (maxC - minC))
        return rect.minX + CGFloat(ratio) * rect.width
    }

    private func yFor(_ rpm: Double, in size: CGSize) -> CGFloat {
        let rect = plotRect(in: size)
        let ratio = (rpm - minRPM) / max(1e-6, (maxRPM - minRPM))
        // 상단이 maxRPM, 하단이 minRPM이 되도록 뒤집기
        return rect.minY + CGFloat(1 - ratio) * rect.height
    }

    private func tempForX(_ x: CGFloat, in size: CGSize) -> Double {
        let rect = plotRect(in: size)
        let ratio = Double((x - rect.minX) / max(1, rect.width))
        return minC + ratio * (maxC - minC)
    }

    private func rpmForY(_ y: CGFloat, in size: CGSize) -> Double {
        let rect = plotRect(in: size)
        let ratio = Double((y - rect.minY) / max(1, rect.height))
        return minRPM + (1 - ratio) * (maxRPM - minRPM)
    }
}
