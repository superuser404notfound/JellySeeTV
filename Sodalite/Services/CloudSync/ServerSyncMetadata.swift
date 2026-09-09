import Foundation

/// Per-server facts a sync payload needs but the server record itself cannot carry.
///
/// A `ServerSyncPayload` has one record-level stamp, and that stamp answers "when did a device last
/// write this record", which is not the question either of these fields is for. `addedAt` is when
/// somebody deliberately put this server on a device, so a removal tombstone knows a genuine re-add
/// from a device that merely has not heard about the removal. `urlsUpdatedAt` is when the URL slots
/// were last actually EDITED, so a device republishing unchanged slots cannot outrank the device
/// that just corrected them.
///
/// Deliberately not fields on `JellyfinServer`: that model is rebuilt from scratch at half a dozen
/// call sites (every login path, the URL editor, the version refresh), and a stamp that has to be
/// carried by hand through each of them is a stamp that quietly stops being carried.
struct ServerSyncMetadataStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Added

    func addedAt(serverID: String) -> Date? {
        date(forKey: addedKey(serverID))
    }

    /// Stamps a deliberate add. Existing stamps stand: re-running a login must not look like a
    /// fresh add, or it would take back a removal the user meant.
    func noteAdded(serverID: String) {
        guard addedAt(serverID: serverID) == nil else { return }
        setDate(nextStamp(), forKey: addedKey(serverID))
    }

    /// A genuine re-add after a removal: the stamp has to move past the tombstone.
    func noteReAdded(serverID: String) {
        setDate(nextStamp(), forKey: addedKey(serverID))
    }

    /// Adopts the stamp that arrived with a server from another device. Existing stamps stand: this
    /// device's own record of when it added the server is first-hand and outranks a copy.
    func setAddedAt(_ date: Date?, serverID: String) {
        guard addedAt(serverID: serverID) == nil else { return }
        guard let date else { return }
        noteRemoteStamp(date)
        setDate(date, forKey: addedKey(serverID))
    }

    func forget(serverID: String) {
        defaults.removeObject(forKey: addedKey(serverID))
        defaults.removeObject(forKey: urlsKey(serverID))
    }

    // MARK: URL slots

    func urlsUpdatedAt(serverID: String) -> Date? {
        date(forKey: urlsKey(serverID))
    }

    func noteURLsChanged(serverID: String) {
        setDate(nextStamp(), forKey: urlsKey(serverID))
    }

    /// Adopting somebody else's slots means adopting the stamp that came with them, or this device
    /// would keep claiming an edit it only received.
    func setURLsUpdatedAt(_ date: Date?, serverID: String) {
        guard let date else {
            defaults.removeObject(forKey: urlsKey(serverID))
            return
        }
        noteRemoteStamp(date)
        setDate(date, forKey: urlsKey(serverID))
    }

    // MARK: Stamps

    /// Monotonic against every stamp this device has issued or seen, so a device whose clock runs
    /// behind cannot mint an edit that loses to the copy it is correcting.
    func nextStamp() -> Date {
        let issued = CloudSyncMerge.monotonicStamp(now: Date(), highestSeen: highestSeen)
        defaults.set(issued.timeIntervalSince1970, forKey: Keys.highestSeen)
        return issued
    }

    func noteRemoteStamp(_ stamp: Date) {
        guard stamp > (highestSeen ?? .distantPast) else { return }
        defaults.set(stamp.timeIntervalSince1970, forKey: Keys.highestSeen)
    }

    private var highestSeen: Date? {
        date(forKey: Keys.highestSeen)
    }

    // MARK: Storage

    private enum Keys {
        static let highestSeen = "serverSyncMeta.highestSeen"
    }

    private func addedKey(_ id: String) -> String { "serverSyncMeta.addedAt.\(id)" }
    private func urlsKey(_ id: String) -> String { "serverSyncMeta.urlsUpdatedAt.\(id)" }

    private func date(forKey key: String) -> Date? {
        (defaults.object(forKey: key) as? Double).map(Date.init(timeIntervalSince1970:))
    }

    private func setDate(_ date: Date, forKey key: String) {
        defaults.set(date.timeIntervalSince1970, forKey: key)
    }
}
