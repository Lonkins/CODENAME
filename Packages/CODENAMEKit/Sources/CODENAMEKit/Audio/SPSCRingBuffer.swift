import Synchronization

/// Lock-free single-producer single-consumer ring of Int16 samples.
/// Producer: the core thread (audio callback capture). Consumer: the audio
/// render callback — `read` never allocates or locks (ADR 0003 constraint).
///
/// Safety contract: exactly one producer thread calls `write`, exactly one
/// consumer thread calls `read`. Indices are monotonically increasing;
/// acquire/release orderings pair each publication with its observation.
public final class SPSCRingBuffer: @unchecked Sendable {
  private let storage: UnsafeMutableBufferPointer<Int16>
  private let capacity: Int
  private let head = Atomic<Int>(0)  // next write position, owned by producer
  private let tail = Atomic<Int>(0)  // next read position, owned by consumer

  public init(capacity requested: Int) {
    var power = 1
    while power < requested { power <<= 1 }
    capacity = power
    storage = .allocate(capacity: power)
    storage.initialize(repeating: 0)
  }

  deinit {
    storage.deallocate()
  }

  public var availableToRead: Int {
    head.load(ordering: .acquiring) - tail.load(ordering: .acquiring)
  }

  public var availableToWrite: Int {
    capacity - availableToRead
  }

  /// Fill fraction in 0...1; drives dynamic rate control (ADR 0003).
  public var occupancy: Double {
    Double(availableToRead) / Double(capacity)
  }

  /// Writes as many samples as fit; returns the count actually written.
  public func write(_ samples: UnsafeBufferPointer<Int16>) -> Int {
    let writeIndex = head.load(ordering: .relaxed)
    let readIndex = tail.load(ordering: .acquiring)
    let space = capacity - (writeIndex - readIndex)
    let count = min(space, samples.count)
    guard count > 0 else { return 0 }

    for offset in 0..<count {
      storage[(writeIndex + offset) & (capacity - 1)] = samples[offset]
    }
    head.store(writeIndex + count, ordering: .releasing)
    return count
  }

  public func write(_ samples: [Int16]) -> Int {
    samples.withUnsafeBufferPointer { write($0) }
  }

  /// Reads up to `destination.count` samples; returns the count actually read.
  public func read(into destination: UnsafeMutableBufferPointer<Int16>) -> Int {
    let readIndex = tail.load(ordering: .relaxed)
    let writeIndex = head.load(ordering: .acquiring)
    let count = min(writeIndex - readIndex, destination.count)
    guard count > 0 else { return 0 }

    for offset in 0..<count {
      destination[offset] = storage[(readIndex + offset) & (capacity - 1)]
    }
    tail.store(readIndex + count, ordering: .releasing)
    return count
  }
}
