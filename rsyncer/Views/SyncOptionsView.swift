import SwiftUI

struct SyncOptionsView: View {
    @Binding var options: SyncOptions
    var twoWay = false
    @State private var advanced = false
    @State private var exclusions = false
    @State private var confirmDeletion = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Sync options").font(.system(size: 16, weight: .semibold))
                Text("Choose what gets copied and how existing files are handled.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }

            OptionsSection(title: "Existing files", symbol: "doc.on.doc") {
                if twoWay {
                    Label("Changes made to the same file on both sides are detected after the first successful sync.", systemImage: "arrow.left.arrow.right")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Divider()
                    Picker("When both copies changed", selection: $options.conflictPolicy) {
                        ForEach(ConflictPolicy.allCases) { policy in Text(policy.title).tag(policy) }
                    }
                    .font(.system(size: 12))
                    Text(options.conflictPolicy == .keepBoth
                         ? "The destination copy is preserved with “conflict from Destination” in its name before syncing."
                         : "The chosen side replaces the other copy before syncing.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    Divider()
                } else {
                    OptionRow(title: "Protect newer destination files", detail: "Skip a file when the destination has a more recent version.", value: $options.skipNewer)
                        .disabled(options.ignoreExisting)
                    Divider()
                }
                OptionRow(title: "Only add new files", detail: twoWay ? "Copy missing files in either direction. Leave all existing files unchanged." : "Copy missing files only. Leave all existing destination files unchanged.", value: $options.ignoreExisting)
                if !twoWay {
                    Divider()
                    OptionRow(title: "Delete extra destination files", detail: "Permanently remove destination files missing from the source. Excluded files are kept.", value: Binding(get: { options.deleteExtraneous }, set: { if $0 { confirmDeletion = true } else { options.deleteExtraneous = false } }), destructive: true)
                    if options.deleteExtraneous {
                        Label("Deletion also applies to scheduled runs and bypasses the Trash. Preview to review what will be removed.", systemImage: "exclamationmark.triangle")
                            .font(.system(size: 11)).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            OptionsSection(title: "Volume matching", symbol: "externaldrive") {
                OptionRow(title: "Match volumes by UUID", detail: "Off by default: match the mounted volume’s path so encrypted vaults can reconnect. Enable to also require the saved volume UUID. Mount paths accept any volume mounted at that location.", value: $options.matchVolumesByUUID)
            }

            OptionsSection(title: "File details", symbol: "doc.text") {
                OptionRow(title: "Preserve timestamps", detail: twoWay ? "Always on for two-way sync so newer versions can be identified." : "Keep the original modification dates on copied files.", value: twoWay ? .constant(true) : $options.preserveTimes)
                    .disabled(twoWay)
                Divider()
                OptionRow(title: "Keep Mac metadata", detail: "Copy Finder tags, extended attributes and resource forks. Can slow syncing on network or encrypted volumes. Off by default; not checked in Preview. Metadata stored inside files, such as photo EXIF, is always copied with the file.", value: $options.extendedAttributes)
                Divider()
                OptionRow(title: "Preserve symbolic links", detail: "Copy links as links, rather than copying the files they point to.", value: $options.preserveLinks)
            }

            OptionsSection(title: "Files to skip", symbol: "line.3.horizontal.decrease.circle") {
                OptionRow(title: "Skip hidden files", detail: "Exclude files and folders whose names begin with a dot.", value: $options.excludeHidden)
                Divider()
                ExpandableGroup(isExpanded: $exclusions) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("One rsync pattern per line. Use *.tmp for temporary files or node_modules/ for that folder. Excluded files are also protected from deletion.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        TextEditor(text: $options.excludePatterns)
                            .font(.system(size: 11, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .frame(height: 100).padding(8)
                            .background(.background, in: RoundedRectangle(cornerRadius: 6))
                            .overlay { RoundedRectangle(cornerRadius: 6).stroke(.primary.opacity(0.1)) }
                            .accessibilityLabel("Exclude patterns")
                    }.padding(.top, 10)
                } label: {
                    HStack {
                        Text("Exclude patterns")
                        Spacer()
                        Text("\(patternCount) patterns").foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 12, weight: .medium))
            }

            ExpandableGroup(isExpanded: $advanced) {
                VStack(alignment: .leading, spacing: 16) {
                    OptionsSection(title: "Comparison & transfers", symbol: "arrow.triangle.2.circlepath") {
                        OptionRow(title: "Compare file contents", detail: "Use checksums instead of size and date to detect changes. Reads every file and can take longer.", value: $options.checksum)
                        Divider()
                        OptionRow(title: "Keep partial transfers", detail: "Keep incomplete files so a later sync can reuse transferred data.", value: $options.keepPartial)
                        Divider()
                        OptionRow(title: "Compress transfers", detail: "Compress data during transfer. Usually unnecessary for local drives.", value: $options.compress)
                        Divider()
                        OptionRow(title: "Whole-file transfers", detail: "Send each changed file in full instead of only its changed parts.", value: $options.wholeFile)
                        Divider()
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Bandwidth limit").font(.system(size: 12, weight: .medium))
                                Text("Set to 0 for unlimited speed.").font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 12)
                            TextField("0", value: $options.bandwidthLimit, format: .number.grouping(.never))
                                .textFieldStyle(.roundedBorder).frame(width: 80)
                                .accessibilityLabel("Bandwidth limit in KiB per second")
                            Text("KiB/s").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    OptionsSection(title: "Permissions & links", symbol: "folder.badge.gearshape") {
                        OptionRow(title: "Preserve permissions", detail: "Keep the source file’s Unix read, write and execute permissions.", value: $options.preservePermissions)
                        Divider()
                        OptionRow(title: "Preserve hard links", detail: "Keep files that share the same data linked together at the destination.", value: $options.preserveHardLinks)
                        Divider()
                        OptionRow(title: "Stay on one filesystem", detail: "Skip other volumes mounted inside the folder being copied.", value: $options.oneFileSystem)
                    }
                }.padding(.top, 14)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Advanced options").font(.system(size: 12, weight: .semibold))
                    Text("Checksums, transfer speed, permissions and links")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: 760, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .confirmationDialog("Enable destination deletion?", isPresented: $confirmDeletion) {
            Button("Enable deletion", role: .destructive) { options.deleteExtraneous = true }
        } message: {
            Text("Extra destination files will be permanently deleted by manual and scheduled syncs. This does not use the Trash. Excluded files are protected.")
        }
    }

    private var patternCount: Int {
        options.excludePatterns.split(whereSeparator: \.isNewline)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }
}

private struct OptionsSection<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 12) { content }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

struct OptionRow: View {
    let title: String
    let detail: String
    @Binding var value: Bool
    var destructive = false

    var body: some View {
        Toggle(isOn: $value) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch).controlSize(.small)
        .tint(destructive ? .orange : Palette.accent)
        .accessibilityLabel(title)
        .accessibilityHint(detail)
    }
}
