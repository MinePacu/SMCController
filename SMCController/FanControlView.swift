//
//  FanControlView.swift
//  SMCController
//

import SwiftUI
import Observation

struct FanControlView: View {
    var viewModel: FanControlViewModel

    var onNavigate: ((String, String) -> Void)?

    @State private var pidHelpPresented = false

    var body: some View {
        // @Observable 모델의 바인딩 프로젝션
        @Bindable var b = viewModel

        ScrollView {
            VStack(spacing: 16) {
            // 네비게이션 예시 버튼
            HStack {
                Button {
                    onNavigate?("Fan Detail", "Here is a pushed detail screen.")
                } label: {
                    Label("Open Detail", systemImage: "arrow.right.square")
                }
                .buttonStyle(.bordered)

                Spacer()

                // 포인트 추가/제거 버튼 (메서드는 원본 model에서 호출)
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
            }
            .padding(.horizontal, 16)

            // 그래프 에디터 (바인딩은 프로젝션 b 사용)
            FanCurveEditorView(points: $b.curve,
                               minC: $b.minC, maxC: $b.maxC,
                               minRPM: $b.minRPM, maxRPM: $b.maxRPM,
                               currentTemp: viewModel.lastTempC,
                               currentRPM: viewModel.lastAppliedRPM)
                .frame(height: 300)
                .padding(.horizontal, 16)

            // 설정 UI
            HStack(alignment: .top, spacing: 24) {
                GroupBox("Curve Points") {
                    VStack(alignment: .leading, spacing: 8) {
                        // 바인딩 가능한 컬렉션을 기준으로 ForEach 수행
                        ForEach(Array(b.curve.enumerated()), id: \.offset) { idx, _ in
                            HStack(spacing: 12) {
                                Text("P\(idx + 1)")
                                    .frame(width: 28, alignment: .leading)
                                    .foregroundStyle(.secondary)

                                HStack {
                                    Text("Temp °C").frame(width: 64, alignment: .leading)
                                    // 배열 요소 바인딩은 $b.curve[idx].프로퍼티
                                    TextField("", value: $b.curve[idx].tempC, format: .number)
                                        .frame(width: 70)
                                }

                                HStack {
                                    Text("RPM").frame(width: 44, alignment: .leading)
                                    TextField("", value: $b.curve[idx].rpm, format: .number)
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
                    .frame(width: 360)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Enable PID", isOn: $b.usePID)
                        HStack {
                            Text("Target (°C)"); Spacer()
                            TextField("", value: $b.targetC, format: .number)
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
                    .frame(width: 280)
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
                        HStack {
                            Text("Sensor Key"); Spacer()
                            TextField("Key", text: $b.sensorKey)
                                .frame(width: 100)
                        }
                        HStack(alignment: .top) {
                            Text("Extra Sensor Keys")
                            Spacer()
                            TextField("TC0P,TG0P", text: $b.extraSensorKeysText, axis: .vertical)
                                .lineLimit(2...4)
                                .frame(width: 200)
                                .help("Comma-separated keys to monitor (read-only)")
                        }
                        Stepper(value: $b.fanIndex, in: 0...3) {
                            Text("Fan Index: \(viewModel.fanIndex)")
                        }
                        HStack {
                            Text("Interval (s)"); Spacer()
                            TextField("", value: $b.interval, format: .number)
                                .frame(width: 70)
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
                    .frame(width: 260)
                }
            }
            .padding(.horizontal, 16)

            // Monitoring UI
            GroupBox("Monitoring") {
                HStack(alignment: .top, spacing: 24) {
                    stat(label: "CPU Avg", value: formattedTemp(viewModel.cpuAvgC))
                    stat(label: "CPU Hot", value: formattedTemp(viewModel.cpuHotC))
                    stat(label: "GPU", value: formattedTemp(viewModel.gpuC))
                    stat(label: "Fan RPM", value: formattedRPM(viewModel.fanRPM))
                    stat(label: "CPU Power", value: formattedPower(viewModel.cpuPowerW))
                    stat(label: "GPU Power", value: formattedPower(viewModel.gpuPowerW))
                    stat(label: "DC In", value: formattedPower(viewModel.dcInW))
                    Spacer()
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
                if let err = viewModel.monitoringError {
                    Text(err).foregroundStyle(.red).lineLimit(2)
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
            .frame(minWidth: 1000, maxWidth: .infinity, alignment: .topLeading)
            .padding(.top, 12)
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
