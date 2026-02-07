import SwiftUI

struct PopoverView: View {
    @ObservedObject var viewModel: MainViewModel
    @ObservedObject var detailsViewModel: PRDetailsViewModel
    let pinToMonitor: () -> Void
    let openMonitor: () -> Void
    let openSettings: () -> Void
    let quitApp: () -> Void
    private let detailsPanelWidth: CGFloat = 430
    private let detailsTransition: AnyTransition = .move(edge: .trailing).combined(with: .opacity)

    var body: some View {
        let hasSelection = viewModel.selectedPR() != nil

        VStack(spacing: 8) {
            HStack(spacing: 8) {
                VStack(spacing: 8) {
                    HStack {
                        Picker("Scope", selection: Binding(
                            get: { scopeSelectionKey(for: viewModel.currentSettings().quickScope) },
                            set: { viewModel.setQuickScope(quickScope(from: $0)) }
                        )) {
                            Text("All").tag("all")
                            Text("Personal").tag("personal")
                            ForEach(viewModel.currentOrgs(), id: \.login) { org in
                                Text("Org: \(org.login)").tag("org:\(org.login)")
                            }
                        }
                        .pickerStyle(.menu)

                        Spacer()
                        Button {
                            viewModel.toggleAutoRefresh()
                        } label: {
                            Image(systemName: viewModel.isAutoRefreshPaused ? "play.circle" : "pause.circle")
                        }
                        .buttonStyle(.borderless)
                        .help(viewModel.isAutoRefreshPaused ? "Resume auto-refresh" : "Pause auto-refresh")
                        Button {
                            Task { await viewModel.requestRefresh() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                    }

                    TextField("Search PRs", text: $viewModel.query)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Toggle("Open only", isOn: Binding(
                            get: { viewModel.currentSettings().openOnly },
                            set: {
                                var next = viewModel.currentSettings()
                                next.openOnly = $0
                                viewModel.updateSettings(next)
                                Task { await viewModel.requestRefresh() }
                            }
                        ))
                        Toggle("Include drafts", isOn: Binding(
                            get: { viewModel.currentSettings().includeDrafts },
                            set: {
                                var next = viewModel.currentSettings()
                                next.includeDrafts = $0
                                viewModel.updateSettings(next)
                            }
                        ))
                    }
                    .toggleStyle(.checkbox)
                    .font(.caption2)

                    List(viewModel.filteredPRs.filter { viewModel.currentSettings().includeDrafts || !$0.isDraft }, id: \.stableID) { pr in
                        PRRowView(pr: pr, selected: viewModel.selectedPR()?.stableID == pr.stableID)
                            .onTapGesture {
                                let isCurrentSelection = viewModel.selectedPR()?.stableID == pr.stableID
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    viewModel.selectPR(isCurrentSelection ? nil : pr)
                                }
                                detailsViewModel.load(pr: isCurrentSelection ? nil : pr)
                            }
                    }
                    .frame(minWidth: 260, maxWidth: .infinity)
                }
                .frame(maxWidth: hasSelection ? .infinity : nil)

                if hasSelection {
                    Divider()
                        .transition(.opacity)

                    PRDetailsPanelView(viewModel: viewModel, detailsViewModel: detailsViewModel) {
                        pinToMonitor()
                    }
                    .frame(width: detailsPanelWidth)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                    .transition(detailsTransition)
                }
            }
            .animation(.easeInOut(duration: 0.22), value: hasSelection)

            HStack {
                Text(viewModel.tokenStatus()).font(.caption).foregroundStyle(.secondary)
                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                Button("Settings", action: openSettings)
                Button("Open Monitor", action: openMonitor)
                Button("Quit", action: quitApp)
            }

            if let err = viewModel.error() {
                Text(err).font(.caption).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .frame(width: 920, height: 620)
        .task {
            await viewModel.validateTokenAndLoadIdentity()
            await viewModel.requestRefresh()
        }
    }

    private func scopeSelectionKey(for scope: PopoverScopeSelection) -> String {
        switch scope {
        case .all:
            return "all"
        case .personal:
            return "personal"
        case let .organization(org):
            return "org:\(org)"
        }
    }

    private func quickScope(from key: String) -> PopoverScopeSelection {
        if key == "all" { return .all }
        if key == "personal" { return .personal }
        if key.hasPrefix("org:") {
            return .organization(String(key.dropFirst(4)))
        }
        return .all
    }
}
