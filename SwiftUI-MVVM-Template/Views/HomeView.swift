import SwiftUI
import Charts

/// The main dashboard view featuring glowing crimson header elements, services list, and settings triggers.
struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @State private var showingSettings = false
    @State private var selectedTerminalService: ServiceItem? = nil
    
    var body: some View {
        NavigationView {
            ZStack {
                // Base Background Dark tone
                Color(hex: "0D0D0D")
                    .ignoresSafeArea()
                
                // Ambient background glows
                VStack {
                    HStack {
                        Circle()
                            .fill(Color(hex: "FF003C").opacity(0.12))
                            .frame(width: 250, height: 250)
                            .blur(radius: 80)
                        Spacer()
                    }
                    Spacer()
                }
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    headerView
                    
                    if let err = viewModel.errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(err)
                                .font(.caption)
                            Spacer()
                            Button(action: { viewModel.errorMessage = nil }) {
                                Image(systemName: "xmark.circle.fill")
                            }
                        }
                        .padding()
                        .background(Color(hex: "FF003C").opacity(0.15))
                        .foregroundColor(Color(hex: "FF003C"))
                        .cornerRadius(10)
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                    }
                    
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 20) {
                            ForEach(viewModel.services) { service in
                                ServiceCardView(service: service, onStart: {
                                    Task { await viewModel.performAction(action: "start", for: service.id) }
                                }, onStop: {
                                    Task { await viewModel.performAction(action: "stop", for: service.id) }
                                }, onRestart: {
                                    Task { await viewModel.performAction(action: "restart", for: service.id) }
                                }, onOpenTerminal: {
                                    self.selectedTerminalService = service
                                })
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 15)
                        .padding(.bottom, 30)
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(item: $selectedTerminalService) { service in
                if #available(iOS 14.0, *) {
                    DetailsView(service: service) // We use DetailsView.swift which is our live logs terminal!
                } else {
                    Text("La vue des logs requiert iOS 14.0+")
                        .foregroundColor(.white)
                }
            }
        }
    }
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("SMOG2HUB")
                    .font(.system(.title2, design: .monospaced))
                    .bold()
                    .foregroundColor(Color(hex: "FF003C")) // Premium Crimson Glow
                Text("NATIVE IOS CONSOLE MONITOR")
                    .font(.system(size: 10, weight: .bold, design: .default))
                    .foregroundColor(.gray)
                    .tracking(2)
            }
            Spacer()
            
            // Settings Action
            Button(action: { showingSettings.toggle() }) {
                Image(systemName: "slider.horizontal.3")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(width: 42, height: 42)
                    .background(Color(hex: "1A1A1A"))
                    .clipShape(Circle())
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 15)
        .background(Color(hex: "0D0D0D").opacity(0.9))
    }
}

/// Settings management view letting users save endpoint addresses and security tokens in the device secure Keychain.
struct SettingsView: View {
    @Environment(\.presentationMode) var presentationMode
    @State private var serverURL: String = ""
    @State private var apiKey: String = ""
    @State private var successAlert = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(hex: "0D0D0D")
                    .ignoresSafeArea()
                
                VStack(spacing: 25) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("CONFIGURATION SERVEUR")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.gray)
                            .tracking(1)
                        
                        TextField("https://45.95.113.114:5050", text: $serverURL)
                            .padding()
                            .background(Color(hex: "121212"))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("CLÉ SECRÈTE DE SÉCURITÉ")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.gray)
                            .tracking(1)
                        
                        SecureField("Saisir la clé X-Manager-Key", text: $apiKey)
                            .padding()
                            .background(Color(hex: "121212"))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                    .padding(.horizontal, 20)
                    
                    // Native Keychain Persistence
                    Button(action: saveSettings) {
                        HStack {
                            Image(systemName: "lock.shield.fill")
                            Text("SAUVEGARDER DANS LE KEYCHAIN")
                                .bold()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(hex: "FF003C")) // Vibrant brand red
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .shadow(color: Color(hex: "FF003C").opacity(0.3), radius: 8, y: 3)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 15)
                    
                    Spacer()
                }
            }
            .navigationBarTitle("PARAMÈTRES", displayMode: .inline)
            .navigationBarItems(
                leading: Button("Fermer") {
                    presentationMode.wrappedValue.dismiss()
                }
                .foregroundColor(.white)
            )
            .onAppear(perform: loadSettings)
            .alert(isPresented: $successAlert) {
                Alert(
                    title: Text("Sécurité Keychain"),
                    message: Text("Les paramètres ont été chiffrés et sauvegardés localement avec succès."),
                    dismissButton: .default(Text("OK")) {
                        presentationMode.wrappedValue.dismiss()
                    }
                )
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func loadSettings() {
        if let savedURL = KeychainHelper.shared.read(service: "smog2hub.server", account: "url") {
            self.serverURL = savedURL
        }
        if let savedKey = KeychainHelper.shared.read(service: "smog2hub.server", account: "apikey") {
            self.apiKey = savedKey
        }
    }
    
    private func saveSettings() {
        KeychainHelper.shared.save(serverURL.trimmingCharacters(in: .whitespacesAndNewlines), service: "smog2hub.server", account: "url")
        KeychainHelper.shared.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), service: "smog2hub.server", account: "apikey")
        self.successAlert = true
    }
}

/// Helper hex initializer extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 1)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}


struct ServiceCardView: View {
        let service: ServiceItem
        let onStart: () -> Void
        let onStop: () -> Void
        let onRestart: () -> Void
        let onOpenTerminal: () -> Void

        var body: some View {
                    VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                                        VStack(alignment: .leading, spacing: 4) {
                                                                                Text(service.name)
                                                                                    .font(.headline)
                                                                                    .foregroundColor(.primary)
                                                                                Text("Port: \(service.port)")
                                                                                    .font(.caption)
                                                                                    .foregroundColor(.secondary)
                                                        }
                                                        Spacer()

                                                        Text(service.status.displayName)
                                                            .font(.caption)
                                                            .bold()
                                                            .padding(.horizontal, 8)
                                                            .padding(.vertical, 4)
                                                            .background(statusColor.opacity(0.2))
                                                            .foregroundColor(statusColor)
                                                            .cornerRadius(8)
                                    }

                                    Text(service.description)
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)

                                    HStack(spacing: 16) {
                                                        Label("\(String(format: "%.1f", service.cpuUsage))%", systemImage: "cpu")
                                                        Label("\(String(format: "%.1f", service.ramUsageMB)) MB", systemImage: "waveform")
                                                        Label("\(formatUptime(service.uptimeSeconds))", systemImage: "clock")
                                    }
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                    Divider()

                                    HStack {
                                                        Button(action: onOpenTerminal) {
                                                                                Label("Console", systemImage: "terminal")
                                                        }
                Spacer()

                                                        if service.status == .stopped {
                                                                                Button(action: onStart) {
                                                                                                            Label("Demarrer", systemImage: "play.fill")
                                                                                                                .foregroundColor(.green)
                                                                                }
                                                        } else if service.status == .running {
                                                                                Button(action: onRestart) {
                                                                                                            Label("Relancer", systemImage: "arrow.clockwise")
                                                                                                                .foregroundColor(.blue)
                                                                                }

                                                                                Spacer()

                                                                                Button(action: onStop) {
                                                                                                            Label("Arreter", systemImage: "stop.fill")
                                                                                                                .foregroundColor(.red)
                                                                                }
                                                        }
                                    }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
        }

        private var statusColor: Color {
                    switch service.status {
                                case .running: return .green
                                case .stopped: return .red
                                case .transitioning: return .orange
                                case .error: return .red
                    }
        }

        private func formatUptime(_ seconds: Int) -> String {
                    let hours = seconds / 3600
                    let minutes = (seconds % 3600) / 60
                    if hours > 0 {
                                    return "\(hours)h \(minutes)m"
                    } else {
                                    return "\(minutes)m"
                    }
        }
}
