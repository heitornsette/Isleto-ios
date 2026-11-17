import AppIntents
import SwiftUI

/// Content of the small counter widget. Also drawn inside the app, so the CI
/// screenshots show it without adding the widget to a home screen.
struct CounterWidgetView: View {
    /// nil when the shared database could not be read.
    let value: Int?
    let message: String?

    var body: some View {
        VStack(spacing: 6) {
            Text("Contador")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value.map(String.init) ?? "—")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            if let message {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
            } else {
                Button(intent: IncrementCounterIntent()) {
                    Label("+1", systemImage: "plus")
                        .font(.callout.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
