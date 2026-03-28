import SwiftUI

struct ABGroupsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        NavigationStack {
            Group {
                if let error = appModel.abGroupsError, appModel.abGroups.isEmpty {
                    errorView(message: error)
                } else if appModel.abGroups.isEmpty {
                    emptyState
                } else {
                    groupList
                }
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("A/B Groups")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await appModel.refreshABGroups() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(Theme.brandBlue)
                    }
                }
            }
        }
    }

    // MARK: - Group List

    private var groupList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(appModel.abGroups) { group in
                    ABGroupCard(group: group)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .refreshable {
            await appModel.refreshABGroups()
        }
    }

    // MARK: - States

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.left.arrow.right.circle")
                .font(.system(size: 46))
                .foregroundStyle(Theme.mutedText)
            Text("No A/B groups configured")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
            Text("A/B failover groups will appear here once configured on the hub.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 42))
                .foregroundStyle(Theme.mutedText)
            Text("Could not load A/B groups")
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
            Text(message)
                .font(.caption)
                .foregroundStyle(Theme.mutedText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Retry") {
                Task { await appModel.refreshABGroups() }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.brandBlue)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - ABGroup Card

private struct ABGroupCard: View {
    let group: ABGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Row 1: group name + status badge
            HStack(alignment: .top) {
                Text(group.name)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 8)
                statusBadge
            }

            // Row 2: Active and Standby chain names
            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Theme.okGreen)
                        .frame(width: 8, height: 8)
                    Text("Active: \(group.activeName)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.okGreen)
                        .lineLimit(1)
                }
                HStack(spacing: 5) {
                    Circle()
                        .fill(Theme.mutedText)
                        .frame(width: 8, height: 8)
                    Text("Standby: \(group.standbyName)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.mutedText)
                        .lineLimit(1)
                }
            }

            // Row 3: Chain A and Chain B status dots
            HStack(spacing: 14) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(group.a_ok ? Theme.okGreen : Theme.faultRed)
                        .frame(width: 8, height: 8)
                    Text("Chain A: \(group.chain_a_name)")
                        .font(.caption)
                        .foregroundStyle(group.a_ok ? Theme.okGreen : Theme.faultRed)
                        .lineLimit(1)
                }
                HStack(spacing: 5) {
                    Circle()
                        .fill(group.b_ok ? Theme.okGreen : Theme.faultRed)
                        .frame(width: 8, height: 8)
                    Text("Chain B: \(group.chain_b_name)")
                        .font(.caption)
                        .foregroundStyle(group.b_ok ? Theme.okGreen : Theme.faultRed)
                        .lineLimit(1)
                }
            }

            // Row 4: notes (muted, caption) — only if non-empty
            if !group.notes.isEmpty {
                Text(group.notes)
                    .font(.caption)
                    .foregroundStyle(Theme.mutedText)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(group.statusColor.opacity(0.4), lineWidth: 1)
        )
        .shadow(
            color: group.status == "fault" ? Theme.faultRed.opacity(0.12) : .black.opacity(0.08),
            radius: group.status == "fault" ? 8 : 4
        )
    }

    private var statusBadge: some View {
        Text(group.status.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(group.statusColor))
    }
}
