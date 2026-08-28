import SwiftUI

struct ContentView: View {
    @State private var viewModel = TrafficLightViewModel()

    var body: some View {
        VStack(spacing: 24) {
            Picker("FSM Variant", selection: $viewModel.variant) {
                ForEach(FSMVariant.allCases) { variant in
                    Text(variant.rawValue).tag(variant)
                }
            }
            .pickerStyle(.segmented)

            LampHousing(current: viewModel.current)
                .frame(width: 140, height: 340)

            HStack(spacing: 16) {
                ForEach(LightColor.allCases, id: \.self) { color in
                    Button(color.description.capitalized) {
                        viewModel.fire(color)
                    }
                    .buttonStyle(.bordered)
                    .tint(color.tint)
                }
            }

            VStack(spacing: 8) {
                Toggle("Maintenance Mode", isOn: Binding(
                    get: { viewModel.maintenanceMode },
                    set: { viewModel.setMaintenanceMode($0) }
                ))
                Toggle("Automatic Mode", isOn: Binding(
                    get: { viewModel.automaticMode },
                    set: { viewModel.setAutomaticMode($0) }
                ))
            }
            .toggleStyle(.switch)
            .frame(maxWidth: 240)

            GroupBox("Event Log") {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(viewModel.eventLog.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.caption.monospaced())
                                    .id(index)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: viewModel.eventLog.count) {
                        proxy.scrollTo(viewModel.eventLog.count - 1, anchor: .bottom)
                    }
                }
            }
            .frame(minHeight: 160)
        }
        .padding()
        .frame(minWidth: 320, minHeight: 640)
    }
}

/// Three lamps stacked in a housing; the lamp matching `current` is lit,
/// the other two are dimmed.
private struct LampHousing: View {
    let current: LightColor

    var body: some View {
        VStack(spacing: 16) {
            ForEach(LightColor.allCases, id: \.self) { color in
                Circle()
                    .fill(color.tint)
                    .opacity(color == current ? 1.0 : 0.15)
                    .overlay(
                        Circle().strokeBorder(.black.opacity(0.3), lineWidth: 2)
                    )
                    .shadow(color: color == current ? color.tint : .clear, radius: 12)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24).fill(.black.opacity(0.85))
        )
        .animation(.easeInOut(duration: 0.25), value: current)
    }
}

private extension LightColor {
    var tint: Color {
        switch self {
        case .red: .red
        case .yellow: .yellow
        case .green: .green
        }
    }
}

#Preview {
    ContentView()
}
