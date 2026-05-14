import SwiftUI

struct TeamSnapshotDetailView: View {
    let detail: TeamSnapshotDetailModel?

    var body: some View {
        Group {
            if let detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(detail.title)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .textSelection(.enabled)

                        Grid(alignment: .topLeading, horizontalSpacing: 24, verticalSpacing: 14) {
                            GridRow {
                                fieldSection(
                                    title: "Documented Fields",
                                    systemImage: "doc.text",
                                    fields: detail.documentedFields
                                )
                                fieldSection(
                                    title: "Additional Fields",
                                    systemImage: "curlybraces",
                                    fields: detail.additionalFields
                                )
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "sidebar.left")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Select a Team")
                        .font(.headline)
                    Text("Choose a team from the sidebar to inspect documented and additional fields.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func fieldSection(
        title: String,
        systemImage: String,
        fields: [FieldDisplay]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)

            ForEach(fields) { field in
                VStack(alignment: .leading, spacing: 3) {
                    Text(field.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(field.value)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(6)
                }
                .padding(.vertical, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
