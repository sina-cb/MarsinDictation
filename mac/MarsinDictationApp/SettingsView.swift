import SwiftUI

struct SettingsView: View {
    var body: some View {
        VStack {
            Text("MarsinDictation")
                .font(.title)
                .bold()
                .padding(.bottom, 16)
            
            Text("Settings will be implemented in Phase 5.")
                .font(.body)
                .foregroundColor(.gray)
                .padding(.bottom, 8)
                
            Text("Dictation: ⌃⌥Space")
                .font(.body)
                .padding(.bottom, 4)
                
            Text("Recovery: ⌥⇧Z")
                .font(.body)
        }
        .padding(40)
        .frame(width: 400, height: 300)
    }
}
