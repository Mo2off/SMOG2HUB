import SwiftUI
import Combine

/// A model representing a single logged line in the scrolling console stream.
struct LogLine: Identifiable {
    let id = UUID()
    let text: String
    let color: Color
}

/// A fully functional custom native terminal view displaying active logs piped from WebSockets.
struct DetailsView: View {
    let service: ServiceItem
    @Environment(\.presentationMode) var presentationMode
    
    @State private var logLines: [LogLine] = []
    @State private var webSocketTask: URLSessionWebSocketTask?
    @State private var isConnected = false
    @State private var statusMessage = "Connexion..."
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Status bar details
                    HStack {
                        Circle()
                            .fill(isConnected ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(statusMessage)
                            .font(.caption2)
                            .foregroundColor(.gray)
                        Spacer()
                        
                        Button(action: clearLogs) {
                            Text("EFFACER")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.gray)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(hex: "1A1A1A"))
                                .cornerRadius(4)
                        }
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 8)
                    .background(Color(hex: "0D0D0D"))
                    
                    // Main log lines scroller
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(logLines) { line in
                                    Text(line.text)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundColor(line.color)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(15)
                        }
                        .onChange(of: logLines.count) { _ in
                            // Auto-scroll to the bottom of logs on new arrivals
                            if let last = logLines.last {
                                withAnimation {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
            }
            .navigationBarTitle(Text(service.name.uppercased() + " LOGS"), displayMode: .inline)
            .navigationBarItems(
                leading: Button("Fermer") {
                    disconnectWebSocket()
                    presentationMode.wrappedValue.dismiss()
                }
                .foregroundColor(.white)
            )
            .onAppear(perform: connectWebSocket)
            .onDisappear(perform: disconnectWebSocket)
        }
        .preferredColorScheme(.dark)
    }
    
    private func clearLogs() {
        logLines.removeAll()
    }
    
    /// Connects to the WebSockets server of the FastAPI manager API.
    private func connectWebSocket() {
        guard let serverURL = KeychainHelper.shared.read(service: "smog2hub.server", account: "url"),
              let apiKey = KeychainHelper.shared.read(service: "smog2hub.server", account: "apikey") else {
            self.statusMessage = "Erreur: Serveur non configuré."
            appendSystemMessage("Configurez l'URL et le mot de passe dans les Réglages.")
            return
        }
        
        // Convert server http/https endpoint to ws/wss protocols
        var wsString = serverURL
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")
        
        wsString += "/api/services/logs/\(service.id)?key=\(apiKey)"
        
        guard let url = URL(string: wsString) else {
            self.statusMessage = "Erreur: URL invalide."
            return
        }
        
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        
        self.isConnected = true
        self.statusMessage = "Connecté"
        appendSystemMessage("Liaison établie avec le terminal de logs du service \(service.name).")
        
        listenForMessages()
    }
    
    /// Listens for live logs streamed in parallel over the WebSocket buffer.
    private func listenForMessages() {
        webSocketTask?.receive { result in
            switch result {
            case .failure(let error):
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.statusMessage = "Déconnecté"
                    self.appendSystemMessage("Erreur de connexion : \(error.localizedDescription)")
                }
            case .success(let message):
                switch message {
                case .string(let text):
                    DispatchQueue.main.async {
                        self.parseAndAppend(text)
                    }
                default:
                    break
                }
                // Recursively listen for future lines
                self.listenForMessages()
            }
        }
    }
    
    private func disconnectWebSocket() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        isConnected = false
    }
    
    /// Simple ANSI-style code parser for logs (errors show red, successes show green).
    private func parseAndAppend(_ text: String) {
        let cleanText = text.trimmingCharacters(in: .newlines)
        
        var color = Color.white
        if cleanText.localizedCaseInsensitiveContains("error") || cleanText.localizedCaseInsensitiveContains("erreur") || cleanText.localizedCaseInsensitiveContains("failed") || cleanText.localizedCaseInsensitiveContains("exception") || cleanText.localizedCaseInsensitiveContains("[erreure]") {
            color = Color(hex: "E74C3C") // Crimson red
        } else if cleanText.localizedCaseInsensitiveContains("success") || cleanText.localizedCaseInsensitiveContains("ok") || cleanText.localizedCaseInsensitiveContains("chargé") || cleanText.localizedCaseInsensitiveContains("prêt") {
            color = Color(hex: "2ECC71") // Green
        } else if cleanText.localizedCaseInsensitiveContains("warning") || cleanText.localizedCaseInsensitiveContains("attention") {
            color = Color(hex: "F39C12") // Orange
        } else if cleanText.localizedCaseInsensitiveContains("[system]") || cleanText.localizedCaseInsensitiveContains("[init]") {
            color = Color(hex: "3498DB") // Blue
        }
        
        logLines.append(LogLine(text: cleanText, color: color))
        if logLines.count > 500 { logLines.removeFirst() } // cap scroll buffers to conserve memory
    }
    
    private func appendSystemMessage(_ message: String) {
        logLines.append(LogLine(text: "[SYSTEM] \(message)", color: Color(hex: "3498DB")))
    }
}
