import SwiftUI

struct AdvancedTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Picker("Check usage every", selection: $settings.pollIntervalMinutes) {
                    Text("1 minute").tag(1)
                    Text("2 minutes").tag(2)
                    Text("5 minutes").tag(5)
                    Text("10 minutes").tag(10)
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                }
            } header: {
                Text("Polling")
            } footer: {
                captionFooter("On rate limiting (429), Burnrate automatically backs off to 10 minutes. Changes apply from the next check.")
            }

            Section {
                Toggle("Simulate usage", isOn: $settings.debugSimulate)

                HStack {
                    Text("Session")
                    Slider(value: $settings.debugSessionPercent, in: 0...100, step: 1)
                    Text("\(Int(settings.debugSessionPercent))%")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
                HStack {
                    Text("Weekly")
                    Slider(value: $settings.debugWeeklyPercent, in: 0...100, step: 1)
                    Text("\(Int(settings.debugWeeklyPercent))%")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }

                Button {
                    settings.debugSimulate = true
                    settings.debugSessionPercent = min(100, settings.debugSessionPercent + 5)
                } label: {
                    Label("Burn +5%", systemImage: "flame.fill")
                }
            } header: {
                Text("Simulated values (no real tokens used)")
            } footer: {
                captionFooter("Overrides what the menu bar and popover display so you can preview colors and thresholds. Real usage is unaffected.")
            }
        }
        .formStyle(.grouped)
    }
}
