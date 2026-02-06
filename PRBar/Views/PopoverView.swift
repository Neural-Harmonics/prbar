import SwiftUI

struct PopoverView: View {
    @ObservedObject var viewModel: MainViewModel
    @ObservedObject var detailsViewModel: PRDetailsViewModel
    let pinToMonitor: () -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                VStack(spacing: 8) {
                    HStack {
                        Picker("Scope", selection: Binding(
                            get: { viewModel.currentSettings().quickScope },
                            set: { viewModel.setQuickScope($0) }
                        )) {
                            Text("All").tag(PopoverScopeSelection.all)
                            Text("Personal").tag(PopoverScopeSelection.personal)
                            ForEach(viewModel.currentOrgs(), id: \.login) { org in
                                Text("Org: \(org.login)").tag(PopoverScopeSelection.organization(org.login))
                            }
                        }
                        .pickerStyle(.menu)

                        Spacer()
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
                                viewModel.selectPR(pr)
                                detailsViewModel.load(pr: pr)
                            }
                    }
                    .frame(minWidth: 260)
                }

                Divider()

                PRDetailsPanelView(viewModel: viewModel, detailsViewModel: detailsViewModel) {
                    pinToMonitor()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            HStack {
                Text(viewModel.tokenStatus()).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Settings", action: openSettings)
                Button("Open Monitor") { pinToMonitor() }
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
}
