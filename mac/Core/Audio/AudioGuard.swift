import Foundation

public protocol AudioGuardDelegate: AnyObject {
    func audioLimitReached()
}

public class AudioGuard {
    // 25 MB limit
    private let limitBytes: Int = 25 * 1024 * 1024
    private let safeMarginBytes: Int = 1 * 1024 * 1024
    
    // Using a safe max bound
    private var maxBytes: Int {
        return limitBytes - safeMarginBytes
    }
    
    public weak var delegate: AudioGuardDelegate?
    private var currentBytes: Int = 0
    
    public init() {}
    
    public func reset() {
        currentBytes = 0
    }
    
    public func addBytes(_ count: Int) {
        currentBytes += count
        if currentBytes >= maxBytes {
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.audioLimitReached()
            }
        }
    }
}
