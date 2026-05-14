import SwiftUI

struct EnrichedSpaceDetailView: View {
    let detail: EnrichedSpaceDetailModel?

    var body: some View {
        Group {
            if let detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(detail.title)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .textSelection(.enabled)

                        HStack(alignment: .top, spacing: 16) {
                            fieldSection(
                                title: "Wire-faithful WebexSpace",
                                systemImage: "network",
                                fields: detail.wireFields
                            )
                            fieldSection(
                                title: "SDK-derived enriched",
                                systemImage: "sparkles",
                                fields: detail.enrichedFields
                            )
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
                    Text("Select a Space")
                        .font(.headline)
                    Text("Choose a space from the sidebar to inspect wire and enriched fields.")
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
                        .lineLimit(4)
                }
                .padding(.vertical, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
