import Foundation

public struct EnvLoader {
    public static func load() {
        guard let envPath = findEnvFile() else {
            print("[EnvLoader] No .env file found.")
            return
        }
        
        do {
            let contents = try String(contentsOfFile: envPath, encoding: .utf8)
            let lines = contents.split(whereSeparator: \.isNewline)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
                
                let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    let key = parts[0].trimmingCharacters(in: .whitespaces)
                    let value = parts[1].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"\'"))
                    setenv(key, value, 1)
                }
            }
            print("[EnvLoader] Successfully loaded .env file.")
        } catch {
            print("[EnvLoader] Error reading .env file: \(error)")
        }
        
        // Seed SettingsManager from env vars (one-time migration)
        SettingsManager.shared.seedFromEnvIfNeeded()
    }
    
    private static func findEnvFile() -> String? {
        let fileManager = FileManager.default
        
        // 1. Check inside the app bundle (Resources/) — used by --install DMG
        if let resourcePath = Bundle.main.resourcePath {
            let bundleEnv = (resourcePath as NSString).appendingPathComponent(".env")
            if fileManager.fileExists(atPath: bundleEnv) {
                return bundleEnv
            }
        }
        
        // 2. Traverse up from current directory — works when running from source/DerivedData
        let currentPath = fileManager.currentDirectoryPath
        var url = URL(fileURLWithPath: currentPath)
        while url.path.count > 1 {
            let tryPath = url.appendingPathComponent(".env").path
            if fileManager.fileExists(atPath: tryPath) {
                return tryPath
            }
            url.deleteLastPathComponent()
        }
        
        // 3. Fallback: known workspace root
        let knownRoots = [
            NSString("~/workspace/MarsinDictation/.env").expandingTildeInPath
        ]
        for root in knownRoots {
            if fileManager.fileExists(atPath: root) {
                return root
            }
        }
        
        return nil
    }
}
