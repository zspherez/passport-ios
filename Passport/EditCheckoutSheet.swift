import SwiftUI

/// Sheet for adjusting a recorded checkout time. Used both to correct a
/// forgotten tap (e.g. the user only realized in the next city) and to fix
/// an auto-estimated value the client guessed wrong. Constrains the picker
/// to the window between the original check-in time and now so we never
/// surface an invalid range to the server.
struct EditCheckoutSheet: View {
    let target: PassportView.EditingCheckoutTarget
    let onSave: (Date) -> Void
    let onCancel: () -> Void

    @State private var picked: Date

    init(target: PassportView.EditingCheckoutTarget,
         onSave: @escaping (Date) -> Void,
         onCancel: @escaping () -> Void) {
        self.target = target
        self.onSave = onSave
        self.onCancel = onCancel
        self._picked = State(initialValue: target.currentCheckedOutAt)
    }

    var body: some View {
        ZStack {
            Brand.bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                Text("Edit check-out time")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundColor(.white)
                Text("Adjust when you left \(target.venueId.displayName). Must be between your check-in and now.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                DatePicker(
                    "Check-out time",
                    selection: $picked,
                    in: target.checkedInAt...Date(),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .tint(Brand.gold)
                .frame(maxWidth: .infinity)

                HStack(spacing: 10) {
                    Button("Cancel", action: onCancel)
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(white: 0.18))
                        .cornerRadius(12)
                    Button("Save") { onSave(picked) }
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Brand.gold)
                        .cornerRadius(12)
                }
            }
            .padding(20)
        }
        .preferredColorScheme(.dark)
    }
}
