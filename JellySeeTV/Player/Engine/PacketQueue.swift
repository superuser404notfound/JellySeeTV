import Foundation

/// Thread-safe bounded queue for demuxed packets.
nonisolated final class PacketQueue: @unchecked Sendable {
    private var packets: [DemuxedPacket] = []
    private let condition = NSCondition()
    private let capacity: Int
    private var isFlushed = false

    init(capacity: Int = 300) {
        self.capacity = capacity
    }

    func enqueue(_ packet: DemuxedPacket) {
        condition.lock()
        while packets.count >= capacity && !isFlushed {
            condition.unlock()
            Thread.sleep(forTimeInterval: 0.001)
            condition.lock()
        }
        if !isFlushed {
            packets.append(packet)
        }
        condition.signal()
        condition.unlock()
    }

    func dequeue(timeout: TimeInterval = 0.1) -> DemuxedPacket? {
        condition.lock()
        let deadline = Date().addingTimeInterval(timeout)
        while packets.isEmpty && !isFlushed {
            if !condition.wait(until: deadline) {
                condition.unlock()
                return nil
            }
        }
        if packets.isEmpty {
            condition.unlock()
            return nil
        }
        let packet = packets.removeFirst()
        condition.unlock()
        return packet
    }

    var count: Int {
        condition.lock()
        let c = packets.count
        condition.unlock()
        return c
    }

    var isEmpty: Bool {
        count == 0
    }

    func flush() {
        condition.lock()
        isFlushed = true
        packets.removeAll()
        condition.signal()
        condition.unlock()
    }

    func reset() {
        condition.lock()
        isFlushed = false
        packets.removeAll()
        condition.unlock()
    }
}
