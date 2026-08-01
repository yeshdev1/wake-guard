/// A minimal, deterministic in-memory store of `Identifiable` elements for
/// tests. Insertion order is preserved so `all()` is reproducible.
///
/// This is a generic test utility, not a production repository: the production
/// repository protocols are WG-012 and the alarm repository is WG-014, which can
/// reuse this for their in-memory fakes.
final class InMemoryRepository<Element: Identifiable & Sendable>: Sendable
where Element.ID: Sendable {

    private struct Storage {
        var order: [Element.ID] = []
        var map: [Element.ID: Element] = [:]
    }

    private let storage: Synchronized<Storage>

    init(_ initial: [Element] = []) {
        storage = Synchronized(Storage())
        for element in initial {
            upsert(element)
        }
    }

    /// Insert a new element or replace an existing one with the same id.
    func upsert(_ element: Element) {
        storage.mutate { store in
            if store.map[element.id] == nil {
                store.order.append(element.id)
            }
            store.map[element.id] = element
        }
    }

    func fetch(id: Element.ID) -> Element? {
        storage.get().map[id]
    }

    /// All elements in insertion order.
    func all() -> [Element] {
        let store = storage.get()
        return store.order.compactMap { store.map[$0] }
    }

    func delete(id: Element.ID) {
        storage.mutate { store in
            store.map[id] = nil
            store.order.removeAll { $0 == id }
        }
    }

    var count: Int {
        storage.get().map.count
    }
}
