import Foundation
import Combine

/// Main asynchronous controller managing background polling threads and service actions.
@MainActor
class HomeViewModel: ObservableObject {
    @Published var services: [ServiceItem] = []
    @Published var errorMessage: String? = nil
    
    private var cancellables = Set<AnyCancellable>()
    private var timer: AnyCancellable?
    
    init() {
        startPolling()
    }
    
    /// Establishes an active Combine background timer firing status queries every 3 seconds.
    func startPolling() {
        timer?.cancel()
        timer = Timer.publish(every: 3.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task {
                    await self?.fetchServicesStatus()
                }
            }
        
        // Immediate query execution on start
        Task {
            await fetchServicesStatus()
        }
    }
    
    /// Queries the backend server for the latest resources and process states.
    func fetchServicesStatus() async {
        guard let serverURL = KeychainHelper.shared.read(service: "smog2hub.server", account: "url"),
              let apiKey = KeychainHelper.shared.read(service: "smog2hub.server", account: "apikey") else {
            self.errorMessage = "Serveur non configuré dans les réglages."
            return
        }
        
        guard let url = URL(string: "\(serverURL)/api/services/status") else {
            self.errorMessage = "URL de serveur invalide."
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "X-Manager-Key")
        request.timeoutInterval = 5.0
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                self.errorMessage = "Erreur d'authentification ou réponse serveur invalide."
                return
            }
            
            let decoder = JSONDecoder()
            let fetchedServices = try decoder.decode([ServiceItem].self, from: data)
            
            // Retain metrics history for chart components while updating states
            for index in 0..<fetchedServices.count {
                var updatedService = fetchedServices[index]
                if let existing = self.services.first(where: { $0.id == updatedService.id }) {
                    // Prepend new metric to history
                    var history = existing.metricsHistory
                    let newMetric = ServiceMetrics(
                        timestamp: Date(),
                        cpuPercent: updatedService.cpuUsage,
                        ramMB: updatedService.ramUsageMB
                    )
                    history.append(newMetric)
                    
                    // Keep history capped to last 15 ticks to conserve memory
                    if history.count > 15 {
                        history.removeFirst()
                    }
                    updatedService.metricsHistory = history
                } else {
                    updatedService.metricsHistory = [
                        ServiceMetrics(timestamp: Date(), cpuPercent: updatedService.cpuUsage, ramMB: updatedService.ramUsageMB)
                    ]
                }
                
                // Maintain local transitioning states to avoid race conditions
                if let existing = self.services.first(where: { $0.id == updatedService.id }),
                   existing.status == .transitioning && updatedService.status != .running {
                    updatedService.status = .transitioning
                }
                
                self.services.updateOrAppend(updatedService)
            }
            
            self.errorMessage = nil
        } catch {
            self.errorMessage = "Erreur de connexion : \(error.localizedDescription)"
        }
    }
    
    /// Triggers a service startup, shutdown, or restart command on the server.
    func performAction(action: String, for serviceId: String) async {
        guard let serverURL = KeychainHelper.shared.read(service: "smog2hub.server", account: "url"),
              let apiKey = KeychainHelper.shared.read(service: "smog2hub.server", account: "apikey") else {
            self.errorMessage = "Configuration absente."
            return
        }
        
        guard let url = URL(string: "\(serverURL)/api/services/action") else { return }
        
        // Optimistic UI state update: display transitioning immediately
        if let index = self.services.firstIndex(where: { $0.id == serviceId }) {
            self.services[index].status = .transitioning
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Manager-Key")
        
        let body: [String: Any] = ["service": serviceId, "action": action]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                // Wait for the next polling sequence to confirm the update
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await fetchServicesStatus()
            } else {
                self.errorMessage = "L'action \(action) a échoué."
                if let index = self.services.firstIndex(where: { $0.id == serviceId }) {
                    self.services[index].status = .error
                }
            }
        } catch {
            self.errorMessage = "Erreur réseau : \(error.localizedDescription)"
            if let index = self.services.firstIndex(where: { $0.id == serviceId }) {
                self.services[index].status = .error
            }
        }
    }
}

extension Array where Element: Identifiable {
    mutating func updateOrAppend(_ element: Element) {
        if let index = firstIndex(where: { $0.id == element.id }) {
            self[index] = element
        } else {
            append(element)
        }
    }
}
