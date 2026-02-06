import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: MainViewModel

    @State private var token: String = ""
    @State private var settings: AppSettings = .init()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("GitHub Token").font(.headline)
            SecureField("ghp_...", text: $token)
            HStack {
                Button("Save + Validate") {
                    Task {
                        await viewModel.saveToken(token)
                        await viewModel.refreshAll(manual: true)
                    }
                }
                Text(viewModel.tokenStatus()).font(.caption).foregroundStyle(.secondary)
            }
            if let err = viewModel.error() {
                Text(err).font(.caption).foregroundStyle(.red)
            }

            Divider()
            Text("Refresh").font(.headline)
            HStack {
                Text("Interval: \(Int(settings.refreshInterval))s")
                Slider(value: $settings.refreshInterval, in: 30...600, step: 10)
            }
            Toggle("Enable auto-refresh", isOn: $settings.autoRefreshEnabled)

            Stepper("PR limit: \(settings.limit)", value: $settings.limit, in: 10...200, step: 10)
            Toggle("Open only", isOn: $settings.openOnly)
            Toggle("Include closed", isOn: $settings.includeClosed)
            Toggle("Include drafts", isOn: $settings.includeDrafts)

            Divider()
            Text("Scope").font(.headline)
            Toggle("Personal", isOn: $settings.scope.personalEnabled)
            Toggle("Organizations", isOn: $settings.scope.organizationsEnabled)

            if settings.scope.organizationsEnabled {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(viewModel.currentOrgs(), id: \.login) { org in
                            Toggle(org.login, isOn: Binding(
                                get: { settings.scope.selectedOrgs.contains(org.login) },
                                set: { on in
                                    if on { settings.scope.selectedOrgs.insert(org.login) }
                                    else { settings.scope.selectedOrgs.remove(org.login) }
                                }
                            ))
                            .toggleStyle(.checkbox)
                        }
                    }
                }
                .frame(height: 120)
            }

            RepoAllowlistTokensView(repos: $settings.scope.repoAllowlist)

            HStack {
                Spacer()
                Button("Apply") {
                    viewModel.updateSettings(settings)
                    Task { await viewModel.requestRefresh() }
                }
            }

            let rate = viewModel.rateLimit()
            Text("Rate limit: \(rate.remaining)/\(rate.limit) remaining")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()
            let metrics = viewModel.apiMetrics()
            VStack(alignment: .leading, spacing: 4) {
                Text("API Metrics").font(.headline)
                Text("Total calls: \(metrics.total)").font(.caption)
                Text("Search: \(metrics.search) | PR detail: \(metrics.prDetails) | Reviews: \(metrics.reviews)").font(.caption2).foregroundStyle(.secondary)
                Text("Actions runs: \(metrics.actionsRuns) | Checks: \(metrics.checks) | Jobs: \(metrics.jobs)").font(.caption2).foregroundStyle(.secondary)
                Text("Identity: \(metrics.identity) | Orgs: \(metrics.orgs) | Other: \(metrics.other)").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 520)
        .onAppear {
            settings = viewModel.currentSettings()
        }
    }
}
