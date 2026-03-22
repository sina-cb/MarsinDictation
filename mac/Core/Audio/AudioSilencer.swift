import Foundation
import CoreAudio

/// Ducks (lowers to 30%) system audio output while the dictation hotkey is held.
/// Uses CoreAudio C API — no additional permissions or entitlements required.
///
/// Strategy:
///   1. Try volume ducking via `kAudioDevicePropertyVolumeScalar` (preserves partial audio)
///   2. Fallback: `kAudioDevicePropertyMute` if device has no volume controls
///   3. On restore: restore saved volumes / unmute
public class AudioSilencer {
    
    public static let shared = AudioSilencer()
    
    /// Volume level during ducking — reads from SettingsManager (0.0 = silent, 1.0 = full)
    private var duckLevel: Float32 {
        Float32(SettingsManager.shared.duckLevel)
    }
    
    // MARK: - Saved State
    
    private var savedMuteState: UInt32?
    private var savedVolumes: [(channel: UInt32, volume: Float32)] = []
    private var savedDeviceID: AudioDeviceID?
    private var isCurrentlySilenced = false
    
    /// Whether we used mute (true) or volume ducking (false)
    private var usedMuteStrategy = false
    
    private init() {}
    
    deinit {
        // Safety net: restore audio if this object is deallocated while silenced
        if isCurrentlySilenced {
            restore()
        }
    }
    
    // MARK: - Public API
    
    /// Duck system audio. Returns true if successful, false if ducking failed
    /// (recording should proceed regardless).
    @discardableResult
    public func silence() -> Bool {
        guard !isCurrentlySilenced else {
            print("[AudioSilencer] Already silenced — no-op")
            return true
        }
        
        guard let deviceID = getDefaultOutputDevice() else {
            print("[AudioSilencer] ⚠️ No default output device found")
            return false
        }
        
        savedDeviceID = deviceID
        
        // Strategy 1: Volume ducking (preferred — preserves partial audio at duckLevel)
        let channelCount = getChannelCount(device: deviceID)
        if channelCount > 0 {
            savedVolumes.removeAll()
            
            // Try master channel (0) first, then individual channels
            let channelsToTry: [UInt32] = [0] + Array(1...channelCount)
            
            for channel in channelsToTry {
                if let currentVol = getVolume(device: deviceID, channel: channel) {
                    savedVolumes.append((channel: channel, volume: currentVol))
                    // Duck: set to duckLevel fraction of current volume
                    let duckedVol = currentVol * duckLevel
                    setVolume(device: deviceID, channel: channel, volume: duckedVol)
                }
            }
            
            if !savedVolumes.isEmpty {
                usedMuteStrategy = false
                isCurrentlySilenced = true
                print("[AudioSilencer] 🔉 Ducked to \(Int(duckLevel * 100))% via volume (\(savedVolumes.count) channels)")
                return true
            }
        }
        
        // Strategy 2: Fallback to mute (only if device has no volume controls)
        if let currentMute = getMuteState(device: deviceID) {
            savedMuteState = currentMute
            if setMuteState(device: deviceID, muted: true) {
                usedMuteStrategy = true
                isCurrentlySilenced = true
                print("[AudioSilencer] 🔇 Muted via kAudioDevicePropertyMute (no volume control available)")
                return true
            }
        }
        
        print("[AudioSilencer] ⚠️ Failed to duck — no controllable channels or mute")
        return false
    }
    
    /// Restore system audio to its state before `silence()` was called.
    /// Safe to call even if `silence()` was never called (no-op).
    @discardableResult
    public func restore() -> Bool {
        guard isCurrentlySilenced else {
            return true  // Nothing to restore
        }
        
        guard let savedDevice = savedDeviceID else {
            isCurrentlySilenced = false
            return false
        }
        
        // Check if the output device changed (e.g., headphones plugged in)
        if let currentDevice = getDefaultOutputDevice(), currentDevice != savedDevice {
            print("[AudioSilencer] ⚠️ Output device changed — skipping restore (new device has its own volume)")
            isCurrentlySilenced = false
            clearSavedState()
            return false
        }
        
        var success = false
        
        if usedMuteStrategy {
            // Restore mute state
            if let originalMute = savedMuteState {
                success = setMuteState(device: savedDevice, muted: originalMute == 1)
                print("[AudioSilencer] 🔊 Restored mute state to \(originalMute == 1 ? "muted" : "unmuted")")
            }
        } else {
            // Restore per-channel volumes
            for saved in savedVolumes {
                setVolume(device: savedDevice, channel: saved.channel, volume: saved.volume)
            }
            success = !savedVolumes.isEmpty
            print("[AudioSilencer] 🔊 Restored \(savedVolumes.count) channel volumes")
        }
        
        isCurrentlySilenced = false
        clearSavedState()
        return success
    }
    
    // MARK: - Private Helpers
    
    private func clearSavedState() {
        savedMuteState = nil
        savedVolumes.removeAll()
        savedDeviceID = nil
        usedMuteStrategy = false
    }
    
    private func getDefaultOutputDevice() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )
        
        guard status == noErr, deviceID != kAudioObjectUnknown else {
            return nil
        }
        return deviceID
    }
    
    private func getMuteState(device: AudioDeviceID) -> UInt32? {
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        // Check if device supports mute
        guard AudioObjectHasProperty(device, &address) else {
            return nil
        }
        
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted)
        return status == noErr ? muted : nil
    }
    
    private func setMuteState(device: AudioDeviceID, muted: Bool) -> Bool {
        var muteValue: UInt32 = muted ? 1 : 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectSetPropertyData(
            device, &address, 0, nil,
            UInt32(MemoryLayout<UInt32>.size), &muteValue
        )
        return status == noErr
    }
    
    private func getVolume(device: AudioDeviceID, channel: UInt32) -> Float32? {
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: channel
        )
        
        guard AudioObjectHasProperty(device, &address) else {
            return nil
        }
        
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume)
        return status == noErr ? volume : nil
    }
    
    @discardableResult
    private func setVolume(device: AudioDeviceID, channel: UInt32, volume: Float32) -> Bool {
        var vol = volume
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: channel
        )
        
        let status = AudioObjectSetPropertyData(
            device, &address, 0, nil,
            UInt32(MemoryLayout<Float32>.size), &vol
        )
        return status == noErr
    }
    
    private func getChannelCount(device: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr else {
            return 0
        }
        
        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(size))
        defer { bufferList.deallocate() }
        
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, bufferList) == noErr else {
            return 0
        }
        
        var totalChannels: UInt32 = 0
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        for buffer in buffers {
            totalChannels += buffer.mNumberChannels
        }
        return totalChannels
    }
}
