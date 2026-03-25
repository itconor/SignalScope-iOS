import Foundation
import Combine

final class APIClient: ObservableObject {
    @Published var baseURL: URL?
    @Published var token: String = ""

    enum AuthHeaderStyle { case bearer, xApiKey }
    var authStyle: AuthHeaderStyle = .bearer

    init(baseURL: URL? = nil, token: String = "") {
        self.baseURL = baseURL
        self.token = token
    }

    var authHeaders: [String: String] {
        guard !token.isEmpty else { return [:] }
        switch authStyle {
        case .bearer:
            return ["Authorization": "Bearer \(token)"]
        case .xApiKey:
            return ["X-API-Key": token]
        }
    }

    private func makeRequest(path: String) throws -> URLRequest {
        guard let baseURL = baseURL else { throw URLError(.badURL) }
        let url = baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        if !token.isEmpty {
            switch authStyle {
            case .bearer:
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            case .xApiKey:
                req.setValue(token, forHTTPHeaderField: "X-API-Key")
            }
        }
        return req
    }

    func downloadAuthorizedFile(from url: URL, suggestedFilename: String? = nil) async throws -> URL {
        var request = URLRequest(url: authorizedPlaybackURL(for: url))
        if !token.isEmpty {
            switch authStyle {
            case .bearer:
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            case .xApiKey:
                request.setValue(token, forHTTPHeaderField: "X-API-Key")
            }
        }

        let (temporaryURL, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let filename = suggestedFilename?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = filename?.isEmpty == false ? filename! : url.lastPathComponent
        let ext = URL(string: fallbackName)?.pathExtension.isEmpty == false ? URL(string: fallbackName)!.pathExtension : url.pathExtension
        let finalExtension = ext.isEmpty ? "m4a" : ext
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(finalExtension)

        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    func fetchHubOverview() async throws -> HubOverviewResponse {
        var req = try makeRequest(path: "/api/mobile/hub/overview")
        req.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(HubOverviewResponse.self, from: data)
    }

    func fetchChains() async throws -> [ChainSummary] {
        var req = try makeRequest(path: "/api/mobile/chains")
        req.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(ChainsListResponse.self, from: data)
        return decoded.results
    }

    func fetchChainDetail(id: String) async throws -> ChainSummary {
        var req = try makeRequest(path: "/api/mobile/chains/\(id)")
        req.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(ChainDetailResponse.self, from: data)
        return decoded.chain
    }



    func authorizedPlaybackURL(for url: URL) -> URL {
        guard !token.isEmpty, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items = components.queryItems ?? []
        if !items.contains(where: { $0.name == "token" }) {
            items.append(URLQueryItem(name: "token", value: token))
        }
        components.queryItems = items
        return components.url ?? url
    }



    func fetchReportEvents(site: String? = nil, stream: String? = nil, type: String? = nil, chain: String? = nil, limit: Int = 100, before: TimeInterval? = nil) async throws -> [ReportEvent] {
        guard var components = URLComponents(url: try makeRequest(path: "/api/mobile/reports/events").url!, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        var queryItems: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let site, !site.isEmpty { queryItems.append(URLQueryItem(name: "site", value: site)) }
        if let stream, !stream.isEmpty { queryItems.append(URLQueryItem(name: "stream", value: stream)) }
        if let type, !type.isEmpty { queryItems.append(URLQueryItem(name: "type", value: type)) }
        if let chain, !chain.isEmpty { queryItems.append(URLQueryItem(name: "chain", value: chain)) }
        if let before { queryItems.append(URLQueryItem(name: "before", value: String(before))) }
        components.queryItems = queryItems
        guard let url = components.url else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        if !token.isEmpty {
            switch authStyle {
            case .bearer: req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            case .xApiKey: req.setValue(token, forHTTPHeaderField: "X-API-Key")
            }
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(ReportsEventsResponse.self, from: data).results
    }

    func fetchReportsSummary(site: String? = nil, stream: String? = nil, type: String? = nil, chain: String? = nil) async throws -> ReportsSummaryResponse {
        guard var components = URLComponents(url: try makeRequest(path: "/api/mobile/reports/summary").url!, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        var queryItems: [URLQueryItem] = []
        if let site, !site.isEmpty { queryItems.append(URLQueryItem(name: "site", value: site)) }
        if let stream, !stream.isEmpty { queryItems.append(URLQueryItem(name: "stream", value: stream)) }
        if let type, !type.isEmpty { queryItems.append(URLQueryItem(name: "type", value: type)) }
        if let chain, !chain.isEmpty { queryItems.append(URLQueryItem(name: "chain", value: chain)) }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        if !token.isEmpty {
            switch authStyle {
            case .bearer: req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            case .xApiKey: req.setValue(token, forHTTPHeaderField: "X-API-Key")
            }
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(ReportsSummaryResponse.self, from: data)
    }

    func registerDeviceToken(_ token: String) async throws {
        var req = try makeRequest(path: "/api/mobile/device_token")
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Always register as production (sandbox: false). The server auto-detects the
        // real environment on the first push: if it gets BadEnvironmentKeyInToken it
        // flips to sandbox, delivers, and permanently corrects the stored flag.
        // This is simpler and more reliable than reading the provisioning profile.
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "token": token, "action": "register", "sandbox": false
        ])
        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    func unregisterDeviceToken(_ token: String) async throws {
        var req = try makeRequest(path: "/api/mobile/device_token")
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["token": token, "action": "unregister"])
        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    // MARK: - Engineer Notes

    func fetchChainFaultLog(chainId: String) async throws -> [FaultLogEntry] {
        var req = try makeRequest(path: "/api/mobile/chains/\(chainId)/fault_log")
        req.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(FaultLogResponse.self, from: data).entries
    }

    func saveChainNote(faultLogId: String, text: String, site: String? = nil) async throws -> ChainNoteRecord {
        var req = try makeRequest(path: "/api/mobile/chain_notes/\(faultLogId)")
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["text": text]
        if let site { body["site"] = site }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(ChainNoteSaveResponse.self, from: data).record
    }

    func fetchMetricHistory(stream: String, site: String? = nil, metric: String = "level_dbfs", hours: Int = 6) async throws -> MetricHistoryResponse {
        guard var components = URLComponents(url: try makeRequest(path: "/api/mobile/metrics/history").url!, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "stream", value: stream),
            URLQueryItem(name: "metric", value: metric),
            URLQueryItem(name: "hours",  value: String(hours))
        ]
        if let site, !site.isEmpty { queryItems.append(URLQueryItem(name: "site", value: site)) }
        components.queryItems = queryItems
        guard let url = components.url else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        if !token.isEmpty {
            switch authStyle {
            case .bearer:  req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            case .xApiKey: req.setValue(token, forHTTPHeaderField: "X-API-Key")
            }
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(MetricHistoryResponse.self, from: data)
    }

    func fetchActiveFaults() async throws -> [ChainSummary] {
        var req = try makeRequest(path: "/api/mobile/active_faults")
        req.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(ActiveFaultsResponse.self, from: data)
        return decoded.results
    }


    // MARK: - FM Scanner

    func fetchScannerSites() async throws -> [ScannerSite] {
        var req = try makeRequest(path: "/api/mobile/scanner/sites")
        req.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(ScannerSitesResponse.self, from: data).sites
    }

    func startScanner(site: String, freqMHz: Double, sdrSerial: String) async throws -> ScannerStartResponse {
        var req = try makeRequest(path: "/api/mobile/scanner/start")
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "site": site, "freq_mhz": freqMHz, "sdr_serial": sdrSerial
        ])
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(ScannerStartResponse.self, from: data)
    }

    func tuneScanner(site: String, freqMHz: Double) async throws -> ScannerStartResponse {
        var req = try makeRequest(path: "/api/mobile/scanner/tune")
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["site": site, "freq_mhz": freqMHz])
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(ScannerStartResponse.self, from: data)
    }

    func stopScanner(site: String) async throws {
        var req = try makeRequest(path: "/api/mobile/scanner/stop")
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["site": site])
        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    func fetchScannerStatus(site: String) async throws -> ScannerStatus {
        guard var components = URLComponents(url: try makeRequest(path: "/api/mobile/scanner/status/\(site)").url!, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        _ = components  // path already includes site
        var req = try makeRequest(path: "/api/mobile/scanner/status/\(site)")
        req.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(ScannerStatus.self, from: data)
    }

    // MARK: - DAB Scanner

    func fetchDABSites() async throws -> [DABSite] {
        var req = try makeRequest(path: "/api/mobile/dab/sites")
        req.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(DABSitesResponse.self, from: data).sites
    }

    func startDAB(site: String, service: String, channel: String, sdrSerial: String) async throws -> DABStartResponse {
        var req = try makeRequest(path: "/api/mobile/dab/start")
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "site": site, "service": service, "channel": channel, "sdr_serial": sdrSerial
        ])
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(DABStartResponse.self, from: data)
    }

    func stopDAB(site: String) async throws {
        var req = try makeRequest(path: "/api/mobile/dab/stop")
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["site": site])
        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    func fetchDABStatus(site: String) async throws -> DABStatus {
        var req = try makeRequest(path: "/api/mobile/dab/status/\(site)")
        req.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(DABStatus.self, from: data)
    }

    func fetchDABServices(site: String) async throws -> DABServicesResponse {
        var req = try makeRequest(path: "/api/mobile/dab/services/\(site)")
        req.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(DABServicesResponse.self, from: data)
    }

    func scanDAB(site: String, sdrSerial: String) async throws {
        var req = try makeRequest(path: "/api/mobile/dab/scan")
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["site": site, "sdr_serial": sdrSerial])
        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    func fetchDABScanStatus(site: String) async throws -> DABScanStatus {
        let encodedSite = site.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? site
        let req = try makeRequest(path: "/api/mobile/dab/scan_status/\(encodedSite)")
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(DABScanStatus.self, from: data)
    }

    // MARK: - Chain Maintenance

    func toggleMaintenance(chainID: String, enable: Bool) async throws -> MaintenanceResponse {
        var req = try makeRequest(path: "/api/mobile/chains/\(chainID)/maintenance")
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["duration": enable ? 3600 : 0])
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(MaintenanceResponse.self, from: data)
    }

    /// Polls the specified path until the provided condition closure returns true or the timeout is reached.
    /// - Parameters:
    ///   - path: The API endpoint path to poll.
    ///   - interval: The delay between polls in seconds.
    ///   - timeout: The maximum time to keep polling in seconds.
    ///   - condition: A closure that takes the decoded data and returns true if polling should stop.
    /// - Returns: The decoded response when the condition is met.
    func poll<T: Decodable>(
        path: String,
        interval: TimeInterval = 5,
        timeout: TimeInterval = 60,
        decodeTo type: T.Type,
        condition: @escaping (T) -> Bool
    ) async throws -> T {
        let startTime = Date()
        while true {
            var req = try makeRequest(path: path)
            req.httpMethod = "GET"
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let decoded = try JSONDecoder().decode(T.self, from: data)
            if condition(decoded) {
                return decoded
            }
            if Date().timeIntervalSince(startTime) > timeout {
                throw URLError(.timedOut)
            }
            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }
}

