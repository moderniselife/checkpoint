import SwiftUI

/// A form in a sheet, done the platform's way: on iOS a navigation bar with Cancel and
/// the confirm action (and a large, scrolling form); on the Mac a grouped form with the
/// buttons along the bottom.
struct FormSheet<Content: View>: View {
    let title: String
    var confirmTitle: String
    var canConfirm: Bool = true
    var busy: Bool = false
    var width: CGFloat = 480
    var cancelTitle: String = "Cancel"
    let onConfirm: () -> Void
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if os(iOS)
        NavigationStack {
            Form { content }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(cancelTitle) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if busy {
                            ProgressView()
                        } else {
                            Button(confirmTitle, action: onConfirm)
                                .fontWeight(.semibold)
                                .disabled(!canConfirm)
                        }
                    }
                }
        }
        .presentationDetents([.large])
        #else
        VStack(spacing: 0) {
            Form {
                content
            }
            .formStyle(.grouped)
            HStack {
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                Button(cancelTitle) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(confirmTitle, action: onConfirm)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canConfirm || busy)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: width)
        .frame(minHeight: 360, idealHeight: 520)
        .navigationTitle(title)
        #endif
    }
}
