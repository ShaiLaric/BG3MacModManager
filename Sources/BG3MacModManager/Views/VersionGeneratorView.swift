import SwiftUI

/// Tool for converting between BG3's Version64 Int64 format and human-readable version strings.
struct VersionGeneratorView: View {
    @State private var versionString: String = "1.0.0.0"
    @State private var int64String: String = "36028797018963968"
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Version Generator")
                    .font(.title2.bold())
                Spacer()
            }
            .padding()

            Divider()

            VStack(spacing: 20) {
                Spacer()

                GroupBox("Version String to Int64") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Enter a version like \"1.0.0.0\" (major.minor.revision.build)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            TextField("Version (e.g. 1.0.0.0)", text: $versionString)
                                .textFieldStyle(.roundedBorder)
                                .font(.body.monospaced())
                                .frame(maxWidth: 250)
                                .onSubmit { convertFromVersionString() }

                            Button("Convert") {
                                convertFromVersionString()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(4)
                }
                .frame(maxWidth: 500)

                Image(systemName: "arrow.up.arrow.down")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                GroupBox("Int64 to Version String") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Enter a raw Int64 value used in meta.lsx / info.json")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            TextField("Int64 (e.g. 36028797018963968)", text: $int64String)
                                .textFieldStyle(.roundedBorder)
                                .font(.body.monospaced())
                                .frame(maxWidth: 250)
                                .onSubmit { convertFromInt64() }

                            Button("Convert") {
                                convertFromInt64()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(4)
                }
                .frame(maxWidth: 500)

                if let error = errorText {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                HStack(spacing: 16) {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(versionString, forType: .string)
                    } label: {
                        Label("Copy Version String", systemImage: "doc.on.doc")
                    }
                    .help("Copy \(versionString) to clipboard")

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(int64String, forType: .string)
                    } label: {
                        Label("Copy Int64", systemImage: "doc.on.doc")
                    }
                    .help("Copy \(int64String) to clipboard")
                }

                Spacer()
            }
            .padding()
        }
    }

    // MARK: - Conversion Logic

    private func convertFromVersionString() {
        errorText = nil
        guard let version = Version64(versionString: versionString) else {
            errorText = "Invalid version string. Use format: major.minor.revision.build (e.g. 1.0.0.0)"
            return
        }
        int64String = String(version.rawValue)
    }

    private func convertFromInt64() {
        errorText = nil
        guard let value = Int64(int64String) else {
            errorText = "Invalid Int64 value. Enter a numeric value."
            return
        }
        let version = Version64(rawValue: value)
        versionString = version.description
    }
}
