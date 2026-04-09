import Foundation

/// Thread-safe bounded queue for demuxed packets.
/// Blocks on enqueue when full, blocks on dequeue when empty.
final class PacketQueue: @unchecked Sendable {
    private var packets: [DemuxedPacket] = []
    private let lock = NSLock()
    private let notEmpty = NSCondition()
    private let capacity: Int
    private var isFlushed = false

    init(capacity: Int = 300) {
        self.capacity = capacity
    }

    /// Enqueue a packet. Blocks if queue is at capacity.
    func enqueue(_ packet: DemuxedPacket) {
        lock.lock()
        // Wait if full (but don't block indefinitely)
        while packets.count >= capacity && !isFlushed {
            lock.unlock()
            Thread.sleep(forTimeInterval: 0.001) // 1ms backpressure
            lock.lock()
        }
        guard !isFlushed else {
            lock.unlock()
            return
        }
        packets.append(packet)
        lock.unlock()
        notEmpty.signal()
    }

    /// Dequeue the next packet. Returns nil if flushed or timeout.
    func dequeue(timeout: TimeInterval = 0.1) -> DemuxedPacket? {
        notEmpty.lock()
        while packets.isEmpty && !isFlushed {
            if !notEmpty.wait(until: Date().addingTimeInterval(timeout)) {
                notEmpty.unlock()
                return nil // Timeout
            }
        }
        guard !packets.isEmpty else {
            notEmpty.unlock()
            return nil
        }
        let packet = packets.removeFirst()
        notEmpty.unlock()
        return packet
    }

    /// Number of packets currently queued
    var count: Int {
        lock.lock()
        let c = packets.count
        lock.unlock()
        return c
    }

    var isEmpty: Bool {
        count == 0
    }

    /// Flush all packets (called on seek or stop)
    func flush() {
        lock.lock()
        isFlushed = true
        packets.removeAll()
        lock.unlock()
        notEmpty.broadcast() // Wake any waiting dequeue
    }

    /// Reset after flush (ready to receive new packets)
    func reset() {
        lock.lock()
        isFlushed = false
        packets.removeAll()
        lock.unlock()
    }
}
