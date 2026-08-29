import Foundation
import Testing

@testable import CODENAMEKit

@Suite struct SPSCRingBufferTests {
  @Test func roundTripsSamplesInOrder() {
    let ring = SPSCRingBuffer(capacity: 16)
    let written = ring.write([1, 2, 3, 4, 5])
    #expect(written == 5)

    var out = [Int16](repeating: 0, count: 5)
    let read = out.withUnsafeMutableBufferPointer { ring.read(into: $0) }
    #expect(read == 5)
    #expect(out == [1, 2, 3, 4, 5])
  }

  @Test func preservesOrderAcrossWraparound() {
    let ring = SPSCRingBuffer(capacity: 8)
    #expect(ring.write([1, 2, 3, 4, 5, 6]) == 6)

    var out = [Int16](repeating: 0, count: 4)
    _ = out.withUnsafeMutableBufferPointer { ring.read(into: $0) }
    #expect(out == [1, 2, 3, 4])

    #expect(ring.write([7, 8, 9, 10, 11]) == 5)

    var rest = [Int16](repeating: 0, count: 7)
    let read = rest.withUnsafeMutableBufferPointer { ring.read(into: $0) }
    #expect(read == 7)
    #expect(rest == [5, 6, 7, 8, 9, 10, 11])
  }

  @Test func overrunWritesPartially() {
    let ring = SPSCRingBuffer(capacity: 4)
    let written = ring.write([1, 2, 3, 4, 5, 6])
    #expect(written == 4)
    #expect(ring.availableToWrite == 0)

    var out = [Int16](repeating: 0, count: 4)
    _ = out.withUnsafeMutableBufferPointer { ring.read(into: $0) }
    #expect(out == [1, 2, 3, 4])
  }

  @Test func underrunReadsNothing() {
    let ring = SPSCRingBuffer(capacity: 8)
    var out = [Int16](repeating: 99, count: 4)
    let read = out.withUnsafeMutableBufferPointer { ring.read(into: $0) }
    #expect(read == 0)
    #expect(out == [99, 99, 99, 99])
  }

  @Test func reportsOccupancy() {
    let ring = SPSCRingBuffer(capacity: 8)
    #expect(ring.occupancy == 0)
    _ = ring.write([1, 2, 3, 4])
    #expect(ring.occupancy == 0.5)
    #expect(ring.availableToRead == 4)
    #expect(ring.availableToWrite == 4)
  }

  @Test func roundsCapacityUpToPowerOfTwo() {
    let ring = SPSCRingBuffer(capacity: 6)
    #expect(ring.write([1, 2, 3, 4, 5, 6, 7]) == 7)
  }

  @Test func survivesConcurrentProducerConsumer() {
    let total = 1 << 18
    let ring = SPSCRingBuffer(capacity: 1024)
    let expected = (0..<total).map { Int16(truncatingIfNeeded: $0) }
    nonisolated(unsafe) var received: [Int16] = []
    received.reserveCapacity(total)

    let producerDone = DispatchSemaphore(value: 0)
    Thread.detachNewThread {
      var index = 0
      while index < total {
        let wrote = expected[index...].prefix(256).withUnsafeBufferPointer {
          ring.write(UnsafeBufferPointer(rebasing: $0.prefix(min(256, total - index))))
        }
        index += wrote
        if wrote == 0 { usleep(50) }
      }
      producerDone.signal()
    }

    var scratch = [Int16](repeating: 0, count: 512)
    while received.count < total {
      let read = scratch.withUnsafeMutableBufferPointer { ring.read(into: $0) }
      if read > 0 {
        received.append(contentsOf: scratch[0..<read])
      } else {
        usleep(50)
      }
    }
    producerDone.wait()

    #expect(received.count == total)
    #expect(received == expected)
  }
}
