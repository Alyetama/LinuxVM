import SwiftUI

struct ContentView: View {
    @EnvironmentObject var library: VMLibrary
    @EnvironmentObject var creds: CredentialsStore
    @EnvironmentObject var theme: ThemeManager
    @State private var showingNew = false
    @State private var consoleVMID: UUID?
    @State private var pendingDelete: VMRecord?

    private let columns = [GridItem(.adaptive(minimum: 360, maximum: 520), spacing: 18)]

    var body: some View {
        ScrollView {
            if library.vms.isEmpty {
                emptyState.frame(minHeight: 460)
            } else {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(library.vms) { record in
                        VMCard(record: record,
                               instance: library.instance(for: record),
                               onOpenConsole: { consoleVMID = record.id },
                               onDelete: { pendingDelete = record })
                    }
                }
                .padding(20)
            }
        }
        .background(theme.current.background.ignoresSafeArea())
        .appTheme(theme.current)
        .navigationTitle("Linux VM")
        .toolbar {
            ToolbarItemGroup {
                SettingsLink { Label("Settings", systemImage: "gearshape") }
                Button { showingNew = true } label: { Label("New VM", systemImage: "plus") }
                    .keyboardShortcut("n")
                    .disabled(!creds.isConfigured)
            }
        }
        .sheet(isPresented: $showingNew) {
            NewVMSheet()
                .environmentObject(library).environmentObject(creds).environmentObject(theme)
                .background(theme.current.background).appTheme(theme.current)
        }
        .sheet(isPresented: Binding(get: { !creds.isConfigured }, set: { _ in })) {
            FirstRunSetup().environmentObject(creds)
                .background(theme.current.background).appTheme(theme.current)
        }
        .sheet(item: consoleBinding) { rec in
            ConsoleView(record: rec, instance: library.instance(for: rec))
                .appTheme(theme.current)
        }
        .confirmationDialog(
            "Delete “\(pendingDelete?.name ?? "")”? This erases its disk and all data.",
            isPresented: deleteBinding, titleVisibility: .visible
        ) {
            Button("Delete VM", role: .destructive) {
                if let r = pendingDelete { library.delete(r) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
    }

    private var consoleBinding: Binding<VMRecord?> {
        Binding(
            get: { consoleVMID.flatMap { id in library.vms.first { $0.id == id } } },
            set: { consoleVMID = $0?.id }
        )
    }
    private var deleteBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Color.indigo.gradient).frame(width: 88, height: 88)
                Image(systemName: "shippingbox.fill").font(.system(size: 38)).foregroundStyle(.white)
            }
            Text("No virtual machines yet").font(.title2.bold())
            Text("Create one and it installs and configures itself automatically —\nno setup steps, ready to use in under a minute.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button { showingNew = true } label: {
                Label("Create your first VM", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
