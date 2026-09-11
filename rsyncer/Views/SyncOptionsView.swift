import SwiftUI

struct SyncOptionsView: View {
    @Binding var options: SyncOptions
    var twoWay = false
    @State private var advanced = false
    @State private var confirmDeletion = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Make it your sync").font(.system(size: 16, weight: .semibold))
                Text("Thoughtful defaults. Fine-tune the details below.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 28), GridItem(.flexible())], alignment: .leading, spacing: 20) {
                OptionRow(title: "Preserve timestamps", detail: "Keep original modification dates", value: $options.preserveTimes).disabled(twoWay)
                OptionRow(title: "Skip newer files", detail: "Keep newer destination versions", value: $options.skipNewer).disabled(twoWay)
                OptionRow(title: "Keep Mac metadata", detail: "Copy attributes and resource forks during sync; omitted from preview", value: $options.extendedAttributes)
                OptionRow(title: "Verify with checksums", detail: "Compare contents instead of size and date", value: $options.checksum)
                OptionRow(title: "Preserve symbolic links", detail: "Copy links without following their targets", value: $options.preserveLinks)
                OptionRow(title: "Keep partial transfers", detail: "Keep incomplete files for the next run", value: $options.keepPartial)
            }
            Divider()
            if !twoWay {
                OptionRow(title: "Delete extra destination files", detail: "Remove destination files missing from the source. Excluded files are kept.", value: Binding(get: { options.deleteExtraneous }, set: { if $0 { confirmDeletion = true } else { options.deleteExtraneous = false } }), destructive: true)
                if options.deleteExtraneous {
                    Label("Deletion is enabled, including for scheduled runs. Preview before syncing.", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11)).foregroundStyle(.orange)
                }
            } else {
                Text("Two-way sync always preserves timestamps and newer files, and keeps files found on only one side.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            DisclosureGroup("More options & exclusions", isExpanded: $advanced) {
                VStack(alignment: .leading, spacing: 20) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 28), GridItem(.flexible())], alignment: .leading, spacing: 20) {
                        OptionRow(title: "Preserve permissions", detail: "Copy source Unix permission bits", value: $options.preservePermissions)
                        OptionRow(title: "Only add new files", detail: "Skip all existing destination files", value: $options.ignoreExisting)
                        OptionRow(title: "Stay on one filesystem", detail: "Do not descend into nested mounts", value: $options.oneFileSystem)
                        OptionRow(title: "Preserve hard links", detail: "Keep linked files linked together", value: $options.preserveHardLinks)
                        OptionRow(title: "Compress transfers", detail: "Usually unnecessary for local drives", value: $options.compress)
                        OptionRow(title: "Whole-file transfers", detail: "Disable delta-based file updates", value: $options.wholeFile)
                        OptionRow(title: "Skip hidden files", detail: "Exclude names beginning with a dot", value: $options.excludeHidden)
                    }
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Bandwidth limit").font(.system(size: 12, weight: .medium))
                            Text("KiB/s · 0 means unlimited").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        TextField("0", value: $options.bandwidthLimit, format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder).frame(width: 100)
                            .accessibilityLabel("Bandwidth limit in KiB per second")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Exclude patterns").font(.system(size: 12, weight: .medium))
                        Text("One rsync pattern per line. For example: *.tmp or node_modules/").font(.system(size: 10)).foregroundStyle(.secondary)
                        TextEditor(text: $options.excludePatterns).font(.system(size: 11, design: .monospaced))
                            .frame(height: 100).padding(6).background(.background, in: RoundedRectangle(cornerRadius: 6))
                            .overlay { RoundedRectangle(cornerRadius: 6).stroke(.primary.opacity(0.1)) }
                            .accessibilityLabel("Exclude patterns")
                    }
                }.padding(.top, 18)
            }.font(.system(size: 12, weight: .medium))
        }
        .confirmationDialog("Enable destination deletion?", isPresented: $confirmDeletion) {
            Button("Enable deletion", role: .destructive) { options.deleteExtraneous = true }
        } message: {
            Text("Extra destination files will be permanently deleted by manual and scheduled syncs. This does not use the Trash. Excluded files are protected.")
        }
    }
}

struct OptionRow: View {
    let title: String
    let detail: String
    @Binding var value: Bool
    var destructive = false
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Toggle(title, isOn: $value).labelsHidden().accessibilityLabel(title)
                .toggleStyle(.switch).controlSize(.small).tint(destructive ? .orange : Palette.green)
        }
    }
}
