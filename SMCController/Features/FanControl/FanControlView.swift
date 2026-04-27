//
//  FanControlView.swift
//  SMCController
//

import SwiftUI
import Observation

struct FanControlView: View {
    var viewModel: FanControlViewModel
    var availableWidthOverride: CGFloat? = nil

    @State private var pidHelpPresented = false

    private var targetCBinding: Binding<Double> {
        Binding(
            get: { viewModel.targetC },
            set: { viewModel.setTargetC($0) }
        )
    }

    private var minCBinding: Binding<Double> {
        Binding(
            get: { viewModel.minC },
            set: { viewModel.setMinC($0) }
        )
    }

    private var maxCBinding: Binding<Double> {
        Binding(
            get: { viewModel.maxC },
            set: { viewModel.setMaxC($0) }
        )
    }

    private var minRPMBinding: Binding<Double> {
        Binding(
            get: { viewModel.minRPM },
            set: { viewModel.setMinRPM($0) }
        )
    }

    private var maxRPMBinding: Binding<Double> {
        Binding(
            get: { viewModel.maxRPM },
            set: { viewModel.setMaxRPM($0) }
        )
    }

    private var fanIndexBinding: Binding<Int> {
        Binding(
            get: { viewModel.fanIndex },
            set: { viewModel.setFanIndex($0) }
        )
    }

    private var intervalBinding: Binding<Double> {
        Binding(
            get: { viewModel.interval },
            set: { viewModel.setInterval($0) }
        )
    }

    var body: some View {
        // @Observable 모델의 바인딩 프로젝션
        @Bindable var b = viewModel

        GeometryReader { proxy in
            let availableWidth = availableWidthOverride ?? proxy.size.width
            let isNarrow = availableWidth < 1100
            let statColumns = [GridItem(.adaptive(minimum: 150, maximum: 220), alignment: .leading)]
            let labelWidth: CGFloat = 120

            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        HStack(spacing: 8) {
                            Button {
                                viewModel.addPoint()
                            } label: {
                                Label("Add Point", systemImage: "plus.circle")
                            }
                            .disabled(!viewModel.canAddPoint())

                            Button(role: .destructive) {
                                viewModel.removePoint()
                            } label: {
                                Label("Remove Point", systemImage: "minus.circle")
                            }
                            .disabled(!viewModel.canRemovePoint())
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 16)

                    FanCurveEditorView(points: $b.curve,
                                       minC: minCBinding, maxC: maxCBinding,
                                       minRPM: minRPMBinding, maxRPM: maxRPMBinding,
                                       currentTemp: viewModel.lastTempC,
                                       currentRPM: viewModel.lastAppliedRPM)
                        .frame(height: 300)
                        .padding(.horizontal, 16)

                    VStack(spacing: 12) {
                        if isNarrow {
                            VStack(alignment: .leading, spacing: 12) {
                                GroupBox("Curve Points") {
                                    VStack(alignment: .leading, spacing: 8) {
                                        ForEach(b.curve.indices, id: \.self) { idx in
                                            HStack(spacing: 12) {
                                                Text("P\(idx + 1)")
                                                    .frame(width: 28, alignment: .leading)
                                                    .foregroundStyle(.secondary)

                                                HStack {
                                                    Text("Temp °C").frame(width: 64, alignment: .leading)
                                                    TextField("",
                                                              value: Binding(
                                                                get: { b.curve[idx].tempC },
                                                                set: { b.curve[idx].tempC = $0 }
                                                              ),
                                                              format: .number)
                                                        .frame(width: 70)
                                                }

                                                HStack {
                                                    Text("RPM").frame(width: 44, alignment: .leading)
                                                    TextField("",
                                                              value: Binding(
                                                                get: { b.curve[idx].rpm },
                                                                set: { b.curve[idx].rpm = $0 }
                                                              ),
                                                              format: .number)
                                                        .frame(width: 80)
                                                }

                                                Spacer()
                                            }
                                        }
                                        Text("온도는 \(Int(viewModel.minC))–\(Int(viewModel.maxC))°C, RPM은 \(Int(viewModel.minRPM))–\(Int(viewModel.maxRPM)) 범위로 자동 보정됩니다.")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                            .padding(.top, 6)
                                    }
                                    .textFieldStyle(.roundedBorder)
                                }
                                GroupBox {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Toggle("Enable PID", isOn: $b.usePID)
                                        HStack {
                                            Text("Target (°C)"); Spacer()
                                            TextField("", value: targetCBinding, format: .number)
                                                .frame(width: 70)
                                        }
                                        HStack {
                                            Text("Kp"); Spacer()
                                            TextField("", value: $b.kp, format: .number)
                                                .frame(width: 70)
                                        }
                                        HStack {
                                            Text("Ki"); Spacer()
                                            TextField("", value: $b.ki, format: .number)
                                                .frame(width: 70)
                                        }
                                        HStack {
                                            Text("Kd"); Spacer()
                                            TextField("", value: $b.kd, format: .number)
                                                .frame(width: 70)
                                        }
                                    }
                                    .textFieldStyle(.roundedBorder)
                                } label: {
                                    HStack {
                                        Text("PID")
                                        Spacer()
                                        Button {
                                            pidHelpPresented.toggle()
                                        } label: {
                                            Label("Help", systemImage: "questionmark.circle")
                                                .labelStyle(.iconOnly)
                                        }
                                        .buttonStyle(.borderless)
                                        .help("PID 설명 보기")
                                        .popover(isPresented: $pidHelpPresented, arrowEdge: .top) {
                                            PIDHelpView()
                                                .frame(width: 360)
                                                .padding()
                                        }
                                    }
                                }
                                GroupBox("Hardware") {
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                                            Text("Sensor Key")
                                                .frame(width: labelWidth, alignment: .leading)
                                            TextField("Key", text: $b.sensorKey)
                                                .frame(maxWidth: 120)
                                            Spacer()
                                        }
                                        HStack(alignment: .top, spacing: 8) {
                                            Text("Extra Sensor Keys")
                                                .frame(width: labelWidth, alignment: .leading)
                                            TextField("TC0P,TG0P", text: $b.extraSensorKeysText, axis: .vertical)
                                                .lineLimit(2...4)
                                                .frame(minWidth: 200, maxWidth: .infinity)
                                                .fixedSize(horizontal: false, vertical: true)
                                                .help("Comma-separated keys to monitor (read-only)")
                                        }
                                        Stepper(value: fanIndexBinding, in: 0...viewModel.maxSelectableFanIndex) {
                                            Text("Fan Index: \(viewModel.fanIndex)")
                                        }
                                        .disabled(viewModel.fanCount <= 1)
                                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                                            Text("Interval (s)")
                                                .frame(width: labelWidth, alignment: .leading)
                                            TextField("", value: intervalBinding, format: .number)
                                                .frame(width: 70)
                                            Spacer()
                                        }
                                        
                                        Divider()
                                        
                                        HStack {
                                            Text("Min: \(Int(viewModel.minRPM)) RPM")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            Text("Max: \(Int(viewModel.maxRPM)) RPM")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        
                                        Button {
                                            viewModel.refreshFanLimits()
                                        } label: {
                                            Label("Refresh Fan Limits", systemImage: "arrow.clockwise")
                                                .font(.caption)
                                        }
                                        .buttonStyle(.borderless)
                                        .help("Reload min/max RPM from SMC hardware")
                                    }
                                    .textFieldStyle(.roundedBorder)
                                }
                            }
                            .padding(.horizontal, 16)
                        } else {
                            HStack(alignment: .top, spacing: 12) {
                                GroupBox("Curve Points") {
                                    VStack(alignment: .leading, spacing: 8) {
                                        ForEach(b.curve.indices, id: \.self) { idx in
                                            HStack(spacing: 12) {
                                                Text("P\(idx + 1)")
                                                    .frame(width: 28, alignment: .leading)
                                                    .foregroundStyle(.secondary)

                                                HStack {
                                                    Text("Temp °C").frame(width: 64, alignment: .leading)
                                                    TextField("",
                                                              value: Binding(
                                                                get: { b.curve[idx].tempC },
                                                                set: { b.curve[idx].tempC = $0 }
                                                              ),
                                                              format: .number)
                                                        .frame(width: 70)
                                                }

                                                HStack {
                                                    Text("RPM").frame(width: 44, alignment: .leading)
                                                    TextField("",
                                                              value: Binding(
                                                                get: { b.curve[idx].rpm },
                                                                set: { b.curve[idx].rpm = $0 }
                                                              ),
                                                              format: .number)
                                                        .frame(width: 80)
                                                }

                                                Spacer()
                                            }
                                        }
                                        Text("온도는 \(Int(viewModel.minC))–\(Int(viewModel.maxC))°C, RPM은 \(Int(viewModel.minRPM))–\(Int(viewModel.maxRPM)) 범위로 자동 보정됩니다.")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                            .padding(.top, 6)
                                    }
                                    .textFieldStyle(.roundedBorder)
                                }
                                    .frame(minWidth: 320, maxWidth: .infinity, alignment: .topLeading)
                                GroupBox {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Toggle("Enable PID", isOn: $b.usePID)
                                        HStack {
                                            Text("Target (°C)"); Spacer()
                                            TextField("", value: targetCBinding, format: .number)
                                                .frame(width: 70)
                                        }
                                        HStack {
                                            Text("Kp"); Spacer()
                                            TextField("", value: $b.kp, format: .number)
                                                .frame(width: 70)
                                        }
                                        HStack {
                                            Text("Ki"); Spacer()
                                            TextField("", value: $b.ki, format: .number)
                                                .frame(width: 70)
                                        }
                                        HStack {
                                            Text("Kd"); Spacer()
                                            TextField("", value: $b.kd, format: .number)
                                                .frame(width: 70)
                                        }
                                    }
                                    .textFieldStyle(.roundedBorder)
                                } label: {
                                    HStack {
                                        Text("PID")
                                        Spacer()
                                        Button {
                                            pidHelpPresented.toggle()
                                        } label: {
                                            Label("Help", systemImage: "questionmark.circle")
                                                .labelStyle(.iconOnly)
                                        }
                                        .buttonStyle(.borderless)
                                        .help("PID 설명 보기")
                                        .popover(isPresented: $pidHelpPresented, arrowEdge: .top) {
                                            PIDHelpView()
                                                .frame(width: 360)
                                                .padding()
                                        }
                                    }
                                }
                                    .frame(minWidth: 260, maxWidth: 300, alignment: .topLeading)
                                GroupBox("Hardware") {
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                                            Text("Sensor Key")
                                                .frame(width: labelWidth, alignment: .leading)
                                            TextField("Key", text: $b.sensorKey)
                                                .frame(maxWidth: 120)
                                            Spacer()
                                        }
                                        HStack(alignment: .top, spacing: 8) {
                                            Text("Extra Sensor Keys")
                                                .frame(width: labelWidth, alignment: .leading)
                                            TextField("TC0P,TG0P", text: $b.extraSensorKeysText, axis: .vertical)
                                                .lineLimit(2...4)
                                                .frame(minWidth: 200, maxWidth: .infinity)
                                                .fixedSize(horizontal: false, vertical: true)
                                                .help("Comma-separated keys to monitor (read-only)")
                                        }
                                        Stepper(value: fanIndexBinding, in: 0...viewModel.maxSelectableFanIndex) {
                                            Text("Fan Index: \(viewModel.fanIndex)")
                                        }
                                        .disabled(viewModel.fanCount <= 1)
                                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                                            Text("Interval (s)")
                                                .frame(width: labelWidth, alignment: .leading)
                                            TextField("", value: intervalBinding, format: .number)
                                                .frame(width: 70)
                                            Spacer()
                                        }
                                        
                                        Divider()
                                        
                                        HStack {
                                            Text("Min: \(Int(viewModel.minRPM)) RPM")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            Text("Max: \(Int(viewModel.maxRPM)) RPM")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        
                                        Button {
                                            viewModel.refreshFanLimits()
                                        } label: {
                                            Label("Refresh Fan Limits", systemImage: "arrow.clockwise")
                                                .font(.caption)
                                        }
                                        .buttonStyle(.borderless)
                                        .help("Reload min/max RPM from SMC hardware")
                                    }
                                    .textFieldStyle(.roundedBorder)
                                }
                                    .frame(minWidth: 320, maxWidth: .infinity, alignment: .topLeading)
                            }
                            .padding(.horizontal, 16)
                        }
                    }

                    GroupBox("Monitoring") {
                        LazyVGrid(columns: statColumns, alignment: .leading, spacing: 12) {
                            stat(label: "CPU Avg", value: formattedTemp(viewModel.cpuAvgC))
                            stat(label: "CPU Hot", value: formattedTemp(viewModel.cpuHotC))
                            stat(label: "GPU", value: formattedTemp(viewModel.gpuC))
                            stat(label: "Fan RPM", value: formattedRPM(viewModel.fanRPM))
                            stat(label: "CPU Power", value: formattedPower(viewModel.cpuPowerW))
                            stat(label: "GPU Power", value: formattedPower(viewModel.gpuPowerW))
                            stat(label: "DC In", value: formattedPower(viewModel.dcInW))
                        }
                        .font(.system(.body, design: .rounded))
                    }
                    .padding(.horizontal, 16)

                    HStack {
                        if viewModel.isRunning {
                            Label("Running", systemImage: "wind").foregroundStyle(.green)
                        } else {
                            Label("Stopped", systemImage: "pause.circle").foregroundStyle(.secondary)
                        }
                        if viewModel.isMonitoring {
                            Label("Monitoring", systemImage: "waveform.path.ecg").foregroundStyle(.blue)
                        }
                        if let status = viewModel.statusMessage {
                            messageBadge(status, color: .blue, systemImage: "info.circle")
                        }
                        if let warning = viewModel.warningMessage {
                            messageBadge(warning, color: .orange, systemImage: "exclamationmark.triangle")
                        }
                        if let error = viewModel.errorMessage {
                            messageBadge(error, color: .red, systemImage: "xmark.octagon")
                        }
                        Spacer()
                        Button(viewModel.isRunning ? "Stop" : "Start") {
                            if viewModel.isRunning { viewModel.stop() } else { viewModel.start() }
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Monitor Only") { viewModel.startMonitoringOnly() }
                            .buttonStyle(.bordered)
                        Button("Apply") { viewModel.applyChanges() }
                            .disabled(!viewModel.isRunning)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
                .frame(minWidth: 900, maxWidth: .infinity, alignment: .topLeading)
                .padding(.top, 12)
            }
        }
    }

    // MARK: - Small helpers
    private func stat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold))
        }
        .frame(width: 160, alignment: .leading)
    }

    private func formattedTemp(_ v: Double?) -> String {
        if let v { return "\(Int(round(v))) °C" }
        return "—"
    }

    private func formattedRPM(_ v: Int?) -> String {
        if let v { return "\(v) RPM" }
        return "—"
    }
    
    private func formattedPower(_ v: Double?) -> String {
        if let v {
            return String(format: "%.1f W", v)
        }
        return "—"
    }

    private func messageBadge(_ text: String, color: Color, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .lineLimit(2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }

}

private struct PIDHelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("PID란?")
                    .font(.headline)
                Text("PID는 목표 온도와 현재 온도의 차이(오차)를 이용해 팬 RPM을 자동으로 보정하는 피드백 제어입니다. P(비례), I(적분), D(미분) 세 성분의 합으로 동작합니다.")

                Group {
                    Text("각 성분의 역할")
                        .font(.subheadline.weight(.semibold))
                    bullet("P: 오차에 비례해 즉각 반응. 반응이 빠르지만 잔류 오차가 남을 수 있음.")
                    bullet("I: 오차를 누적해 잔류 오차를 없앰. 너무 크면 느려지고 진동/overshoot 증가.")
                    bullet("D: 오차 변화율에 반응해 제동. 과도한 튐/진동을 줄이지만 노이즈에 민감.")
                }

                Group {
                    Text("튜닝 순서")
                        .font(.subheadline.weight(.semibold))
                    bullet("1) 먼저 PID를 끄고 곡선(Curve)만으로 기본 동작을 맞춥니다.")
                    bullet("2) PID 켠 뒤 Kp를 조금씩 올려 반응 속도를 확보합니다.")
                    bullet("3) 목표 온도에 잔류 오차가 크면 Ki를 아주 작게 추가합니다.")
                    bullet("4) 변화가 급할 때 흔들리면 Kd를 조금 올려 안정화합니다.")
                    bullet("한 번에 하나씩, 작은 값으로 바꾸며 관찰하세요.")
                }

                Group {
                    Text("이 앱에서의 동작")
                        .font(.subheadline.weight(.semibold))
                    bullet("기본 RPM은 커브로 계산합니다.")
                    bullet("PID가 켜지면 error = 현재온도 - Target(°C)을 계산합니다.")
                    bullet("pid(Kp, Ki, Kd) 보정값을 RPM에 더한 후, 최종적으로 min/max RPM으로 클램프합니다.")
                }

                Text("팁: 지나치게 큰 Kp/Ki/Kd는 팬이 불안정하게 요동치게 만들 수 있습니다. 작은 값부터 시작하세요.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•")
            Text(text)
        }
    }
}

#Preview {
    FanControlView(viewModel: FanControlViewModel())
        .frame(width: 900, height: 560)
}
