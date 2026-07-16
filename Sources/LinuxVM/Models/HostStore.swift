import Foundation
import Combine

/// Persists the list of remote libvirt hosts the user can target.
@MainActor
final class HostStore: ObservableObject {
    @Published private(set) var hosts: [RemoteHost] = []

    private static var url: URL {
        CredentialsStore.appRoot.appendingPathComponent("hosts.json")
    }

    init() { load() }

    func load() {
        guard let data = try? Data(contentsOf: Self.url),
              let list = try? JSONDecoder().decode([RemoteHost].self, from: data) else { return }
        hosts = list
    }

    func host(id: String?) -> RemoteHost? {
        guard let id else { return nil }
        return hosts.first { $0.id == id }
    }

    func add(_ host: RemoteHost) {
        if let i = hosts.firstIndex(where: { $0.id == host.id }) { hosts[i] = host }
        else { hosts.append(host) }
        save()
    }

    func remove(_ host: RemoteHost) {
        hosts.removeAll { $0.id == host.id }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(hosts) {
            try? data.write(to: Self.url, options: .atomic)
        }
    }
}
