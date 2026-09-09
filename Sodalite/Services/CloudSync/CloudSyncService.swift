import CloudKit
import Foundation
import Observation

enum CloudSyncStatus: Equatable {
    case disabled
    /// Sync is off because a different iCloud account signed in on this device.
    case accountChanged
    case noAccount
    case syncing
    case active(lastSyncAt: Date?)
    case error(String)
}

/// What a manual "load from iCloud" attempt amounted to. Distinguishing these is
/// the point: reporting every outcome as "nothing in iCloud" hides broken fetches.
enum CloudSyncLoadOutcome: Equatable {
    case loaded
    case empty
    case noAccount
    /// Carries CloudKit's message when there was one; nil when the engine never
    /// got far enough to produce one (sync still disabled).
    case failed(String?)

    static func resolve(status: CloudSyncStatus, hasServers: Bool) -> CloudSyncLoadOutcome {
        if hasServers { return .loaded }
        switch status {
        case .noAccount: return .noAccount
        case .error(let message): return .failed(message)
        case .disabled, .accountChanged: return .failed(nil)
        case .active, .syncing: return .empty
        }
    }
}

protocol CloudSyncServiceProtocol: AnyObject {
    var status: CloudSyncStatus { get }
    var isEnabled: Bool { get }
    func start()
    func setEnabled(_ enabled: Bool)
    func fetchNow() async
    func loadFromCloud() async -> CloudSyncLoadOutcome
    func waitForInitialSync(timeout: TimeInterval) async
    func markServerDirty(serverID: String)
    func markServerDeleted(serverID: String)
    func markSettingsDirty(_ key: CloudSyncStoreKey)
    func markSecurityDirty()
    func markSecurityDeleted()
    func pushLocalSettingsToAllDevices()
    func deleteCloudDataAndDisable() async
    func handleFullLogout()
}

/// Owns the CKSyncEngine on the private database. All state and delegate work is
/// MainActor (project default isolation); the async delegate requirements hop here.
@Observable
final class CloudSyncService: CloudSyncServiceProtocol {
    static let containerID = "iCloud.de.superuser404.Sodalite"
    static let zoneName = "SodaliteSync"
    static let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    private static let payloadKey = "payload"

    private(set) var status: CloudSyncStatus = .disabled
    var isEnabled: Bool { preferences.isEnabled }

    private unowned let dependencies: DependencyContainer
    let preferences: CloudSyncPreferences
    private var engine: CKSyncEngine?
    private var startInFlight = false
    /// The in-flight (or last) engine start, so callers that need a live engine can
    /// await it instead of no-opping while it is still coming up.
    private var startTask: Task<Void, Never>?
    private var debounceTasks: [CloudSyncStoreKey: Task<Void, Never>] = [:]
    /// Last snapshot uploaded or applied per store, to skip observation echoes.
    private var lastSettingsSnapshot: [CloudSyncStoreKey: SettingsSyncPayload] = [:]
    private var observers: [NSObjectProtocol] = []
    /// Bumped on every teardown/start so stale withObservationTracking re-arm loops die.
    private var observationGeneration = 0
    /// Records queued for local deletion but not yet confirmed sent, so a remote
    /// fetch racing the delete cannot resurrect them via applyRemoteRecord.
    private var recentLocalDeletes: Set<String> = []
    /// In-flight zone resync, so the several records that report the same divergence in one
    /// batch trigger one recovery rather than one each.
    private var resyncTask: Task<Void, Never>?
    /// Bounded per session: a resync that does not fix the divergence must surface as an error
    /// instead of spinning fetch/send forever.
    private var resyncCount = 0
    private static let maxResyncsPerSession = 2
    /// Holds an upload failure the server will keep rejecting, so the next fetch (which succeeds
    /// against a zone this device has never written to) cannot report the row back to healthy.
    private var statusLatch = CloudSyncStatusLatch()

    init(dependencies: DependencyContainer, preferences: CloudSyncPreferences = CloudSyncPreferences()) {
        self.dependencies = dependencies
        self.preferences = preferences
    }

    // MARK: Lifecycle

    func start() {
        guard preferences.isEnabled else {
            status = preferences.accountChangeLocked ? .accountChanged : .disabled
            return
        }
        guard engine == nil, !startInFlight else { return }
        startInFlight = true
        removeObservers()
        observationGeneration += 1
        observeAccountChanges()
        observeSettingsStores()
        observeHomeConfigChanges()
        startTask = Task { await startEngine() }
    }

    /// Every settled "healthy" status goes through here so a latched upload failure survives it.
    private func settleActive() {
        status = statusLatch.resolve(.active(lastSyncAt: preferences.lastSyncAt))
    }

    /// An upload failure the server will repeat for the same record: show it, and keep showing it
    /// until an upload actually lands.
    private func latchFailure(_ message: String) {
        statusLatch.latch(message)
        status = .error(message)
    }

    func setEnabled(_ enabled: Bool) {
        preferences.isEnabled = enabled
        // Either direction is the user's own hand on the switch, so the account-change
        // explanation has done its job and must not outlive it.
        preferences.accountChangeLocked = false
        statusLatch.clear()
        if enabled {
            start()
        } else {
            teardownEngine()
            status = .disabled
        }
    }

    /// A different iCloud account than the one this device adopted against.
    ///
    /// Adopting again here is not a merge, it is an upload: `completeAdoption` marks every known
    /// server dirty unconditionally, and a server record carries its remembered profiles, their
    /// Jellyfin tokens, the stored password and the Seerr sessions. On a device that changed hands
    /// that lands the previous account's credentials in the new account's private database, without
    /// anyone asking for it. So sync stops here and stays stopped until someone turns it back on.
    ///
    /// Clearing the stored account is what makes that switch clean: the next enable reads as a
    /// first adoption for whoever is signed in now, rather than tripping this guard forever.
    private func lockOutForAccountChange() {
        preferences.resetForAccountChange()
        preferences.isEnabled = false
        preferences.accountChangeLocked = true
        statusLatch.clear()
        status = .accountChanged
        LogTap.shared.note("[CloudSync] iCloud account changed, sync paused until re-enabled")
    }

    private func teardownEngine() {
        observationGeneration += 1
        removeObservers()
        // An engine start that is still mid-flight would otherwise install its engine after this
        // teardown, and the next start() would bail at its `engine == nil` guard without ever
        // re-arming the observers: sync would look enabled and be deaf until the next launch.
        startTask?.cancel()
        startTask = nil
        engine = nil
        startInFlight = false
        for task in debounceTasks.values { task.cancel() }
        debounceTasks = [:]
        // A delete queued under one account must not block adoption of the same
        // record name under the next account.
        recentLocalDeletes = []
    }

    private func removeObservers() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
    }

    private func startEngine() async {
        // Teardown bumps this, so a start that was superseded while awaiting CloudKit can tell
        // and stop touching shared state.
        let generation = observationGeneration
        defer { if observationGeneration == generation { startInFlight = false } }
        var stash: (saves: [String], deletes: [String]) = ([], [])
        do {
            let container = CKContainer(identifier: Self.containerID)
            let accountStatus = try await container.accountStatus()
            guard observationGeneration == generation else { return }
            guard accountStatus == .available else {
                status = .noAccount
                return
            }
            let accountID = try await container.userRecordID().recordName
            guard observationGeneration == generation else { return }
            let transition = CloudSyncAccountTransition.resolve(stored: preferences.accountID, current: accountID)
            // One line on every start, deliberately. Without it the absence of an account-change
            // line is indistinguishable from CloudSync never logging anything on a healthy device,
            // which is exactly the reading that cannot be made from a silent log.
            LogTap.shared.note(
                "[CloudSync] engine start, account \(CloudSyncAccountTransition.fingerprint(accountID)), \(transition.logDescription)"
            )
            switch transition {
            case .firstAdoption, .unchanged:
                break
            case .changed:
                lockOutForAccountChange()
                return
            }
            preferences.accountID = accountID

            var config = CKSyncEngine.Configuration(
                database: container.privateCloudDatabase,
                stateSerialization: decodeEngineState(),
                delegate: self
            )
            config.automaticallySync = true
            let engine = CKSyncEngine(config)
            self.engine = engine
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
            settleActive()

            // Replay anything queued while the engine was unavailable (signed out,
            // failed start, or before this start() completed) so it isn't lost.
            stash = preferences.drainPendingChanges()
            recentLocalDeletes.formUnion(stash.deletes)
            for name in stash.deletes {
                engine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID(name))])
            }
            for name in stash.saves {
                engine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID(name))])
            }

            if !preferences.adoptionCompleted {
                try await engine.fetchChanges()
                completeAdoption()
            }
        } catch {
            status = .error(CloudSyncRecovery.describe(error))
            LogTap.shared.note("[CloudSync] start failed: \(error)")
            handleFetchFailure(error)
            // A failed adoption fetch must not lose the drained stash: put it back
            // (both stash methods are idempotent) so a relaunch still replays it.
            stash.saves.forEach(preferences.stashPendingSave)
            stash.deletes.forEach(preferences.stashPendingDelete)
            recentLocalDeletes.subtract(stash.deletes)
            // A failed adoption fetch must not leave a half-started engine syncing
            // in cloud-wins posture forever; drop it so the next start() retries cleanly.
            if !preferences.adoptionCompleted { engine = nil }
        }
    }

    /// Uploads everything local that adoption's fetch did not already reconcile,
    /// then latches the adoption flag.
    private func completeAdoption() {
        for server in dependencies.listKnownServers() {
            markServerDirty(serverID: server.id)
        }
        for key in CloudSyncStoreKey.allCases {
            // Only upload stores the cloud did not already win at adoption.
            if preferences.localStamp(for: CloudSyncRecordName.settings(key)) == nil {
                markSettingsDirty(key)
            }
        }
        if preferences.localStamp(for: CloudSyncRecordName.securitySingleton) == nil,
           dependencies.isGuardianPINSet() {
            markSecurityDirty()
        }
        preferences.adoptionCompleted = true
        LogTap.shared.note("[CloudSync] adoption complete")
    }

    /// Blocks (yielding) until the first adoption fetch has completed, a terminal
    /// state makes waiting pointless, or the timeout expires. Used to gate the
    /// fresh-install launch so synced servers surface before the discovery screen.
    func waitForInitialSync(timeout: TimeInterval) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            // Cancelled callers must exit immediately: a cancelled Task.sleep throws
            // right away (swallowed by try?), so continuing would busy-spin the
            // MainActor until the deadline.
            if Task.isCancelled { return }
            if preferences.adoptionCompleted { return }
            switch status {
            case .noAccount, .disabled, .accountChanged, .error: return
            case .active, .syncing: break
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    func fetchNow() async {
        if engine == nil {
            // A failed or skipped start (offline launch, signed-out account) must be
            // retryable in-session; foregrounding is the natural retry point.
            guard preferences.isEnabled else { return }
            if !startInFlight { start() }
            // The engine only exists after two CloudKit round trips (account status,
            // user record), so a cold-launch foreground always arrives before it.
            // Awaiting the start is what makes that first fetch happen at all:
            // startEngine itself only fetches while adoption is still pending, and
            // without a fetch here a device that finished adoption would receive
            // remote changes solely from silent pushes.
            await startTask?.value
        }
        guard let engine else { return }
        do {
            try await engine.fetchChanges()
        } catch {
            LogTap.shared.note("[CloudSync] fetch failed: \(error)")
            handleFetchFailure(error)
        }
    }

    private func handleFetchFailure(_ error: Error) {
        guard let ckError = error as? CKError else { return }
        switch CloudSyncRecovery.fetchAction(for: ckError) {
        case .resyncZone:
            resyncZoneFromScratch(reason: "change token expired")
        case .report:
            break
        }
    }

    /// Local knowledge of the zone is provably out of step with the server: either the change
    /// token no longer matches its history, or a save came back rejected as an insert of a record
    /// that already exists. Both mean the cached record identities are worthless, and nothing in
    /// the engine ever relearns them, so the zone has to be fetched from scratch.
    ///
    /// Deliberately NOT an adoption reset. The LWW stamps survive, so the fetch applies normally
    /// and `applyRemoteRecord` re-queues everything that is locally newer, with the identities it
    /// just learned. A manual push therefore still wins against the cloud copy it was meant to
    /// overwrite instead of being silently reverted by its own recovery.
    private func resyncZoneFromScratch(reason: String) {
        guard preferences.isEnabled, resyncTask == nil else { return }
        guard resyncCount < Self.maxResyncsPerSession else {
            LogTap.shared.note("[CloudSync] resync limit reached, leaving the error up: \(reason)")
            return
        }
        resyncCount += 1
        LogTap.shared.note("[CloudSync] resyncing zone from scratch (\(reason))")

        // Queued changes live in the engine's in-memory state, which the restart below drops.
        // Stash them so startEngine's drain replays them onto the fresh engine.
        if let engine {
            for change in engine.state.pendingRecordZoneChanges {
                switch change {
                case .saveRecord(let recordID): preferences.stashPendingSave(recordID.recordName)
                case .deleteRecord(let recordID): preferences.stashPendingDelete(recordID.recordName)
                @unknown default: break
                }
            }
        }
        preferences.forgetAllSystemFields()
        preferences.engineState = nil
        status = .syncing

        resyncTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.resyncTask = nil }
            self.teardownEngine()
            self.start()
            await self.startTask?.value
            await self.fetchNow()
            guard let engine = self.engine else { return }
            // The fetch relearned the identities and re-queued whatever is locally newer; flush
            // it now rather than leaving the user's push to the automatic scheduler.
            try? await engine.sendChanges()
            if case .syncing = self.status {
                self.settleActive()
            }
        }
    }

    /// Manual load from the discovery screen. A full logout leaves sync disabled,
    /// so this has to re-enable it (the tap is the explicit user consent) before any
    /// fetch can land, then report what actually happened rather than assuming an
    /// empty zone. Deliberately unbounded: CloudKit's own timeouts surface as a real
    /// error, which beats calling a slow network "no data in iCloud".
    func loadFromCloud() async -> CloudSyncLoadOutcome {
        if !preferences.isEnabled { setEnabled(true) }
        // Same in-flight signal the manual push uses, so the settings status row shows
        // the tap did something. Only over a healthy state: a real error or a missing
        // account must stay visible.
        if case .active = status { status = .syncing }
        await fetchNow()
        // A fetch that changed nothing never posts .fetchedRecordZoneChanges, so settle
        // the transient state here instead of leaving it stuck on "Syncing…".
        if case .syncing = status { settleActive() }
        return CloudSyncLoadOutcome.resolve(
            status: status,
            hasServers: !dependencies.listKnownServers().isEmpty
        )
    }

    // MARK: Dirty marking (called from DependencyContainer mutation hooks)

    func markServerDirty(serverID: String) {
        guard preferences.isEnabled else { return }
        let name = CloudSyncRecordName.server(id: serverID)
        preferences.setLocalStamp(preferences.nextStamp(), for: name)
        addPendingSave(recordName: name)
    }

    func markServerDeleted(serverID: String) {
        guard preferences.isEnabled else { return }
        let name = CloudSyncRecordName.server(id: serverID)
        preferences.removeRecordCaches(for: name)
        // Also with a live engine, not just on the stashed path: a fetch landing between the
        // queued delete and its confirmation would otherwise re-adopt the record we just removed.
        recentLocalDeletes.insert(name)
        guard let engine else {
            preferences.stashPendingDelete(name)
            return
        }
        engine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID(name))])
    }

    func markSettingsDirty(_ key: CloudSyncStoreKey) {
        guard preferences.isEnabled else { return }
        let name = CloudSyncRecordName.settings(key)
        preferences.setLocalStamp(preferences.nextStamp(), for: name)
        addPendingSave(recordName: name)
    }

    func markSecurityDirty() {
        guard preferences.isEnabled else { return }
        preferences.setLocalStamp(preferences.nextStamp(), for: CloudSyncRecordName.securitySingleton)
        addPendingSave(recordName: CloudSyncRecordName.securitySingleton)
    }

    func markSecurityDeleted() {
        guard preferences.isEnabled else { return }
        let name = CloudSyncRecordName.securitySingleton
        preferences.removeRecordCaches(for: name)
        recentLocalDeletes.insert(name)
        guard let engine else {
            preferences.stashPendingDelete(name)
            return
        }
        engine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID(name))])
    }

    /// Manual push: re-stamp every settings store so THIS device wins LWW
    /// everywhere until the next change on any device. Settings only, never
    /// server records (those would clobber newer remote credential changes).
    func pushLocalSettingsToAllDevices() {
        for key in CloudSyncStoreKey.allCases {
            lastSettingsSnapshot[key] = dependencies.collectSettingsPayload(key, stamp: .distantPast)
            markSettingsDirty(key)
        }
        LogTap.shared.note("[CloudSync] manual settings push queued")
        guard let engine else { return }
        // Force the upload now instead of waiting for the automatic scheduler, so a
        // manual push lands immediately and the status timestamp reflects it promptly.
        status = .syncing
        Task { @MainActor [weak self] in
            do {
                try await engine.sendChanges()
            } catch {
                guard let self else { return }
                LogTap.shared.note("[CloudSync] manual push send failed: \(error)")
                self.status = .error(CloudSyncRecovery.describe(error))
                self.handlePartialSendFailure(error, syncEngine: engine)
                return
            }
            // The .sentRecordZoneChanges event already advanced status to .active when
            // records were saved; only settle a push that sent nothing back itself.
            guard let self else { return }
            if case .syncing = self.status {
                self.settleActive()
            }
        }
    }

    func deleteCloudDataAndDisable() async {
        var failure: Error?
        if let engine {
            engine.state.add(pendingDatabaseChanges: [.deleteZone(Self.zoneID)])
            do {
                try await engine.sendChanges()
            } catch {
                failure = error
            }
        }
        preferences.isEnabled = false
        if let failure {
            // The zone survived. Wiping the local bookkeeping now is precisely how the identities
            // and the server drift apart, so keep it and say the deletion did not happen instead
            // of reporting success and leaving an unsaveable zone behind.
            teardownEngine()
            status = .error(CloudSyncRecovery.describe(failure))
            LogTap.shared.note("[CloudSync] cloud data delete failed, local state kept: \(failure)")
            return
        }
        preferences.resetForCloudDataDeletion()
        preferences.accountChangeLocked = false
        teardownEngine()
        statusLatch.clear()
        status = .disabled
        LogTap.shared.note("[CloudSync] cloud data deleted, sync disabled")
    }

    /// Full local logout: stop syncing, keep cloud data intact (no multi-device
    /// wipe from one logout). Re-enabling later re-adopts from the cloud.
    func handleFullLogout() {
        preferences.isEnabled = false
        preferences.accountChangeLocked = false
        preferences.resetForCloudDataDeletion()
        teardownEngine()
        statusLatch.clear()
        status = .disabled
    }

    // MARK: Observation of local changes

    private func observeAccountChanges() {
        let observer = NotificationCenter.default.addObserver(
            forName: .CKAccountChanged, object: nil, queue: .main
        ) { _ in
            Task { @MainActor [weak self] in
                guard let self, self.preferences.isEnabled else { return }
                LogTap.shared.note("[CloudSync] iCloud account changed, restarting engine")
                self.teardownEngine()
                self.start()
            }
        }
        observers.append(observer)
    }

    private func observeHomeConfigChanges() {
        for name in [Notification.Name.homeConfigDidChange, .librarySortDidChange] {
            observeServerRecordTrigger(name)
        }
    }

    /// Marks the active server dirty when a per-server preference changed locally.
    private func observeServerRecordTrigger(_ name: Notification.Name) {
        let observer = NotificationCenter.default.addObserver(
            forName: name, object: nil, queue: .main
        ) { [weak self] _ in
            // Synchronous check: the apply paths post this while isApplyingCloudChanges
            // is still true; deferring into a Task would read the flag after its
            // defer-reset and echo every cloud-applied change back as an upload.
            MainActor.assumeIsolated {
                guard let self, !self.dependencies.isApplyingCloudChanges else { return }
                if let serverID = self.dependencies.activeServer?.id {
                    self.markServerDirty(serverID: serverID)
                }
            }
        }
        observers.append(observer)
    }

    private func observeSettingsStores() {
        for key in CloudSyncStoreKey.allCases { armObservation(for: key) }
    }

    private func armObservation(for key: CloudSyncStoreKey) {
        let generation = observationGeneration
        withObservationTracking {
            // Touch every synced property so any change re-arms us.
            _ = dependencies.collectSettingsPayload(key, stamp: .distantPast)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.observationGeneration == generation else { return }
                self.scheduleSettingsUpload(key)
                self.armObservation(for: key)
            }
        }
    }

    private func scheduleSettingsUpload(_ key: CloudSyncStoreKey) {
        debounceTasks[key]?.cancel()
        debounceTasks[key] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.uploadSettingsIfChanged(key)
        }
    }

    private func uploadSettingsIfChanged(_ key: CloudSyncStoreKey) {
        guard preferences.isEnabled, !dependencies.isApplyingCloudChanges else { return }
        let snapshot = dependencies.collectSettingsPayload(key, stamp: .distantPast)
        if lastSettingsSnapshot[key] == snapshot { return }
        lastSettingsSnapshot[key] = snapshot
        markSettingsDirty(key)
    }

    // MARK: Record building / applying

    private func recordID(_ name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: name, zoneID: Self.zoneID)
    }

    private func recordType(forRecordName name: String) -> CKRecord.RecordType {
        if CloudSyncRecordName.serverID(fromRecordName: name) != nil { return CloudSyncRecordType.server }
        if CloudSyncRecordName.storeKey(fromRecordName: name) != nil { return CloudSyncRecordType.settings }
        return CloudSyncRecordType.security
    }

    private func addPendingSave(recordName: String) {
        guard let engine else {
            preferences.stashPendingSave(recordName)
            return
        }
        engine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID(recordName))])
    }

    private func collectPayloadData(recordName: String) -> Data? {
        let stamp = preferences.localStamp(for: recordName) ?? preferences.nextStamp()
        guard let encoded = encodeLocalPayload(recordName: recordName, stamp: stamp) else { return nil }
        // Uploads stay additive across app versions: whatever a newer build wrote into this record
        // and this one cannot decode rides along instead of being dropped, which last-writer-wins
        // would otherwise hand to every newer device as an authoritative reset.
        return CloudSyncForwardCompat.merged(local: encoded, carrying: preferences.carriedFields(for: recordName))
    }

    private func encodeLocalPayload(recordName: String, stamp: Date) -> Data? {
        if let serverID = CloudSyncRecordName.serverID(fromRecordName: recordName) {
            guard let payload = dependencies.collectServerPayload(serverID: serverID, stamp: stamp) else { return nil }
            return try? JSONEncoder().encode(payload)
        }
        if let key = CloudSyncRecordName.storeKey(fromRecordName: recordName) {
            return try? dependencies.collectSettingsPayload(key, stamp: stamp).encoded()
        }
        guard let payload = dependencies.collectSecurityPayload(stamp: stamp) else { return nil }
        return try? JSONEncoder().encode(payload)
    }

    /// Remember the fields of a remote payload this build cannot write, so the next upload from
    /// here carries them instead of resetting them for every device that does understand them.
    private func noteCarriedFields(remote: Data, recordName: String) {
        guard let known = knownFields(forRecordName: recordName) else { return }
        preferences.setCarriedFields(
            CloudSyncForwardCompat.unknownFields(remote: remote, known: known),
            for: recordName
        )
    }

    private func knownFields(forRecordName recordName: String) -> Set<String>? {
        if let serverID = CloudSyncRecordName.serverID(fromRecordName: recordName) {
            return dependencies.collectServerPayload(serverID: serverID, stamp: .distantPast)
                .map(CloudSyncForwardCompat.storedPropertyNames(of:))
        }
        if let key = CloudSyncRecordName.storeKey(fromRecordName: recordName) {
            return dependencies.collectSettingsPayload(key, stamp: .distantPast).knownFields
        }
        return dependencies.collectSecurityPayload(stamp: .distantPast)
            .map(CloudSyncForwardCompat.storedPropertyNames(of:))
    }

    private func buildRecord(recordName: String) -> CKRecord? {
        guard let payloadData = collectPayloadData(recordName: recordName) else {
            // Nothing local anymore (e.g. server removed while queued): drop the save.
            engine?.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID(recordName))])
            return nil
        }
        let record: CKRecord
        if let archived = preferences.systemFields(for: recordName),
           let restored = Self.decodeSystemFields(archived) {
            record = restored
        } else {
            record = CKRecord(recordType: recordType(forRecordName: recordName), recordID: recordID(recordName))
        }
        record.encryptedValues[Self.payloadKey] = payloadData
        return record
    }

    private func applyRemoteRecord(_ record: CKRecord) {
        // A record we are about to delete (or have queued a delete for while the
        // engine was unavailable) must not resurrect locally via the adoption fetch.
        guard !recentLocalDeletes.contains(record.recordID.recordName) else { return }
        let name = record.recordID.recordName
        guard let data = record.encryptedValues[Self.payloadKey] as? Data else {
            // Reachable when CloudKit cannot decrypt the field for this device (no
            // iCloud Keychain, so no zone key). Silence here looks exactly like an
            // empty zone from the outside, so say it.
            LogTap.shared.note("[CloudSync] no readable payload on \(name), record skipped")
            return
        }
        preferences.setSystemFields(Self.encodeSystemFields(record), for: name)
        // Deferred: a server record adopted for the first time is not in the local store until the
        // branches below have applied it, and there is no known-field set to diff against before
        // that. The union branches return early, so this cannot be a straight-line call.
        defer { noteCarriedFields(remote: data, recordName: name) }
        let adopting = !preferences.adoptionCompleted

        if let serverID = CloudSyncRecordName.serverID(fromRecordName: name) {
            guard let cloud = try? JSONDecoder().decode(ServerSyncPayload.self, from: data) else { return }
            preferences.noteRemoteStamp(cloud.updatedAt)
            if adopting, let local = dependencies.collectServerPayload(serverID: serverID, stamp: .distantPast) {
                let merged = CloudSyncMerge.adoptServerPayload(local: local, cloud: cloud, stamp: preferences.nextStamp())
                dependencies.applyServerPayload(merged)
                preferences.setLocalStamp(merged.updatedAt, for: name)
                if merged != cloud { addPendingSave(recordName: name) }
            } else {
                let localStamp = preferences.localStamp(for: name) ?? .distantPast
                if CloudSyncMerge.remoteWins(localUpdatedAt: localStamp, remoteUpdatedAt: cloud.updatedAt) || adopting {
                    dependencies.applyServerPayload(cloud)
                    // A server record can move the default-server pin, which lives in the auth store,
                    // so re-baseline that snapshot or the debounced observer reads its own apply as a
                    // local edit two seconds later and uploads it back.
                    lastSettingsSnapshot[.auth] = dependencies.collectSettingsPayload(.auth, stamp: .distantPast)
                    preferences.setLocalStamp(cloud.updatedAt, for: name)
                } else {
                    addPendingSave(recordName: name)
                }
            }
        } else if let key = CloudSyncRecordName.storeKey(fromRecordName: name) {
            guard let cloud = try? SettingsSyncPayload.decode(data, key: key) else { return }
            preferences.noteRemoteStamp(cloud.updatedAt)
            // Sodalite#46: track memory is per entry, not one blob. Last-writer-wins would
            // drop every title the other device recorded, so union instead, adoption
            // included, and re-upload when the merge produced more than the cloud had.
            if case .trackMemory(let cloudMemory) = cloud {
                guard case .trackMemory(let localMemory) = dependencies.collectSettingsPayload(
                    key, stamp: preferences.localStamp(for: name) ?? .distantPast
                ) else { return }
                let merged = CloudSyncMerge.unionTrackMemory(local: localMemory, cloud: cloudMemory)
                dependencies.applySettingsPayload(.trackMemory(merged))
                lastSettingsSnapshot[key] = dependencies.collectSettingsPayload(key, stamp: .distantPast)
                preferences.setLocalStamp(merged.updatedAt, for: name)
                if merged.entries != cloudMemory.entries { addPendingSave(recordName: name) }
                return
            }
            // Sodalite#50: reveals are per entry like track memory, so union instead of
            // last-writer-wins, adoption included.
            if case .spoilerReveals(let cloudReveals) = cloud {
                guard case .spoilerReveals(let localReveals) = dependencies.collectSettingsPayload(
                    key, stamp: preferences.localStamp(for: name) ?? .distantPast
                ) else { return }
                let merged = CloudSyncMerge.unionSpoilerReveals(local: localReveals, cloud: cloudReveals)
                dependencies.applySettingsPayload(.spoilerReveals(merged))
                lastSettingsSnapshot[key] = dependencies.collectSettingsPayload(key, stamp: .distantPast)
                preferences.setLocalStamp(merged.updatedAt, for: name)
                if merged.entries != cloudReveals.entries { addPendingSave(recordName: name) }
                return
            }
            // Sodalite#50 follow-up: series rules are per entry as well, and "never veil this show"
            // cannot be expressed by a union, so merge per key with the tombstone in the running.
            if case .spoilerSeriesRules(let cloudRules) = cloud {
                guard case .spoilerSeriesRules(let localRules) = dependencies.collectSettingsPayload(
                    key, stamp: preferences.localStamp(for: name) ?? .distantPast
                ) else { return }
                let merged = CloudSyncMerge.mergeSpoilerSeriesRules(local: localRules, cloud: cloudRules)
                dependencies.applySettingsPayload(.spoilerSeriesRules(merged))
                lastSettingsSnapshot[key] = dependencies.collectSettingsPayload(key, stamp: .distantPast)
                preferences.setLocalStamp(merged.updatedAt, for: name)
                if merged.entries != cloudRules.entries { addPendingSave(recordName: name) }
                return
            }
            // Server removals union like the maps above, so they are taken even when the record as a
            // whole loses last-writer-wins. Without this a device that happened to write some other
            // auth setting more recently would discard the payload entire and never learn that a
            // server was removed, leaving it standing there for good. The rest of the auth payload
            // still obeys LWW below; applying the map twice is idempotent.
            if case .auth(let auth) = cloud, let removals = auth.forgottenServers {
                dependencies.applyForgottenServers(removals)
                lastSettingsSnapshot[key] = dependencies.collectSettingsPayload(key, stamp: .distantPast)
            }
            let localStamp = preferences.localStamp(for: name) ?? .distantPast
            if adopting || CloudSyncMerge.remoteWins(localUpdatedAt: localStamp, remoteUpdatedAt: cloud.updatedAt) {
                dependencies.applySettingsPayload(cloud)
                lastSettingsSnapshot[key] = dependencies.collectSettingsPayload(key, stamp: .distantPast)
                preferences.setLocalStamp(cloud.updatedAt, for: name)
            } else {
                addPendingSave(recordName: name)
            }
        } else if name == CloudSyncRecordName.securitySingleton {
            guard let cloud = try? JSONDecoder().decode(SecuritySyncPayload.self, from: data) else { return }
            preferences.noteRemoteStamp(cloud.updatedAt)
            let localStamp = preferences.localStamp(for: name) ?? .distantPast
            if adopting || CloudSyncMerge.remoteWins(localUpdatedAt: localStamp, remoteUpdatedAt: cloud.updatedAt) {
                dependencies.applySecurityPayload(cloud)
                preferences.setLocalStamp(cloud.updatedAt, for: name)
            } else {
                addPendingSave(recordName: name)
            }
        }
    }

    private func applyRemoteDeletion(recordName: String) {
        preferences.removeRecordCaches(for: recordName)
        if let serverID = CloudSyncRecordName.serverID(fromRecordName: recordName) {
            dependencies.applyRemoteServerDeletion(serverID: serverID)
        } else if recordName == CloudSyncRecordName.securitySingleton {
            dependencies.applyRemoteSecurityDeletion()
        }
        // Settings records are never deleted remotely; ignore anything else.
    }

    // MARK: System field + engine state codecs

    private static func encodeSystemFields(_ record: CKRecord) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        return archiver.encodedData
    }

    private static func decodeSystemFields(_ data: Data) -> CKRecord? {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = true
        return CKRecord(coder: unarchiver)
    }

    private func decodeEngineState() -> CKSyncEngine.State.Serialization? {
        guard let data = preferences.engineState else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    #if DEBUG
    /// Test-only seam: lets unit tests drive waitForInitialSync's polling branch
    /// without spinning up a real CKSyncEngine (start() touches CloudKit).
    func setStatusForTesting(_ status: CloudSyncStatus) { self.status = status }
    #endif
}

// MARK: - CKSyncEngineDelegate

extension CloudSyncService: CKSyncEngineDelegate {
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            preferences.engineState = try? JSONEncoder().encode(update.stateSerialization)

        case .accountChange(let change):
            switch change.changeType {
            case .signOut, .switchAccounts:
                preferences.resetForAccountChange()
                teardownEngine()
                statusLatch.clear()
                status = .noAccount
            default:
                break
            }

        case .fetchedDatabaseChanges(let changes):
            for deletion in changes.deletions where deletion.zoneID.zoneName == Self.zoneName {
                // Zone deleted externally (user cleared iCloud data in Settings):
                // recreate and re-upload the local state.
                LogTap.shared.note("[CloudSync] zone deleted remotely, re-uploading")
                preferences.resetForZoneRecreation()
                preferences.isEnabled = true
                syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
                completeAdoption()
            }

        case .fetchedRecordZoneChanges(let changes):
            for modification in changes.modifications {
                applyRemoteRecord(modification.record)
            }
            for deletion in changes.deletions {
                applyRemoteDeletion(recordName: deletion.recordID.recordName)
            }
            preferences.lastSyncAt = Date()
            settleActive()
            NotificationCenter.default.post(name: .cloudSyncDidApplyChanges, object: nil)

        case .sentRecordZoneChanges(let sent):
            for saved in sent.savedRecords {
                preferences.setSystemFields(Self.encodeSystemFields(saved), for: saved.recordID.recordName)
            }
            // An upload that lands is the only evidence that clears a latched rejection, and it
            // has to clear before this batch's own failures are handled: a batch that saved some
            // records and had others permanently rejected must come out latched, not healthy.
            if !sent.savedRecords.isEmpty { statusLatch.clear() }
            for failure in sent.failedRecordSaves {
                handleSaveFailure(failure, syncEngine: syncEngine)
            }
            for (recordID, error) in sent.failedRecordDeletes {
                handleDeleteFailure(recordName: recordID.recordName, error: error, syncEngine: syncEngine)
            }
            // Deletes actually confirmed sent no longer need resurrection protection.
            recentLocalDeletes.subtract(sent.deletedRecordIDs.map(\.recordName))
            if !sent.savedRecords.isEmpty {
                preferences.lastSyncAt = Date()
                settleActive()
            }

        default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        // Materialize records on the MainActor up front: the recordProvider closure
        // below is @Sendable (CKSyncEngine may invoke it off-actor), so it cannot
        // call the MainActor-isolated buildRecord itself.
        let built: [CKRecord.ID: CKRecord] = pending.reduce(into: [:]) { result, change in
            if case .saveRecord(let recordID) = change, let record = buildRecord(recordName: recordID.recordName) {
                result[recordID] = record
            }
        }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            built[recordID]
        }
    }

    private func handleSaveFailure(
        _ failure: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave,
        syncEngine: CKSyncEngine
    ) {
        handleSaveFailure(
            recordName: failure.record.recordID.recordName,
            error: failure.error,
            syncEngine: syncEngine
        )
    }

    /// A send that fails as a whole reports its per-record errors only inside the thrown partial
    /// error. Without routing those here they never reach the recovery below, and a record the
    /// server permanently rejects keeps being rejected on every future attempt.
    private func handlePartialSendFailure(_ error: Error, syncEngine: CKSyncEngine) {
        for (recordID, itemError) in CloudSyncRecovery.partialSaveErrors(in: error) {
            handleSaveFailure(recordName: recordID.recordName, error: itemError, syncEngine: syncEngine)
        }
    }

    /// Nothing handled these before, so a delete that failed once was simply forgotten: the record
    /// stayed in the cloud and came back on the next device's adoption, and its name stayed in the
    /// resurrection guard for the rest of the session.
    private func handleDeleteFailure(recordName: String, error: CKError, syncEngine: CKSyncEngine) {
        switch CloudSyncRecovery.deleteAction(for: error) {
        case .alreadyGone:
            recentLocalDeletes.remove(recordName)
            preferences.removeRecordCaches(for: recordName)
        case .retry:
            syncEngine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID(recordName))])
        case .report:
            LogTap.shared.note("[CloudSync] delete failed \(recordName): \(error.code.rawValue)")
        }
    }

    private func handleSaveFailure(recordName: String, error: CKError, syncEngine: CKSyncEngine) {
        switch CloudSyncRecovery.saveAction(for: error) {
        case .adoptServerRecord:
            guard let serverRecord = error.serverRecord else { return }
            // Adopt the server's system fields, then LWW: apply theirs if newer,
            // else re-queue ours (now based on their record, so the save sticks).
            preferences.setSystemFields(Self.encodeSystemFields(serverRecord), for: recordName)
            applyRemoteRecord(serverRecord)
            // applyRemoteRecord gives up on a record whose payload it cannot read, which would
            // drop our save with it. The identity is learned either way, so re-queue.
            if serverRecord.encryptedValues[Self.payloadKey] as? Data == nil {
                addPendingSave(recordName: recordName)
            }
        case .resyncZone:
            resyncZoneFromScratch(reason: "save rejected as an insert of an existing record (\(recordName))")
        case .reinsert:
            preferences.removeSystemFields(for: recordName)
            addPendingSave(recordName: recordName)
        case .recreateZone:
            syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
            addPendingSave(recordName: recordName)
        case .retry:
            addPendingSave(recordName: recordName)
        case .surfaceQuota:
            latchFailure(ErrorText.user(for: error))
            LogTap.shared.note("[CloudSync] iCloud quota exceeded, save deferred: \(recordName)")
        case .surfaceRejection:
            // CloudKit's own text here is "Invalid Arguments", which tells a user nothing; the
            // part worth reading ("Cannot create new type … in production schema") is a server
            // message and goes to the diagnostic log, where a bug report can carry it.
            latchFailure(String(
                localized: "cloudSync.error.rejected",
                defaultValue: "iCloud rejected this device's data. This is a fault in Sodalite, not on your device."
            ))
            LogTap.shared.note("[CloudSync] save rejected as invalid \(recordName): \(error)")
        case .report:
            LogTap.shared.note("[CloudSync] save failed \(recordName): \(error.code.rawValue)")
        }
    }
}
