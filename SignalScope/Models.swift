import Foundation
import SwiftUI

// MARK: - Hub Overview

struct HubOverviewResponse: Codable {
    let ok: Bool
    let generated_at: TimeInterval
    let mode: String
    let summary: HubSummary
    let sites: [HubSite]
}

struct HubSummary: Codable, Hashable {
    let total_sites: Int
    let online_sites: Int
    let offline_sites: Int
    let total_alert: Int
    let total_warn: Int
    let total_ok: Int
    let total_streams: Int
}

struct HubSite: Codable, Identifiable, Hashable {
    static func == (lhs: HubSite, rhs: HubSite) -> Bool { lhs.site == rhs.site }
    func hash(into hasher: inout Hasher) { hasher.combine(site) }

    let site: String
    let online: Bool
    let running: Bool
    let site_status: String   // "alert" | "warn" | "ok" | "offline"
    let age_s: Double?
    let latency_ms: Double?
    let build: String
    let health_pct: Double?
    let alert_count: Int
    let warn_count: Int
    let ok_count: Int
    let stream_count: Int
    let streams: [HubStream]

    var id: String { site }

    var statusColor: Color {
        switch site_status {
        case "alert":   return Theme.faultRed
        case "warn":    return Theme.pendingAmber
        case "offline": return Theme.mutedText
        default:        return Theme.okGreen
        }
    }

    var statusLabel: String {
        switch site_status {
        case "alert":   return "Alert"
        case "warn":    return "Warning"
        case "offline": return "Offline"
        default:        return online ? "Online" : "Offline"
        }
    }

    var lastSeenLabel: String {
        guard let age = age_s else { return "Unknown" }
        if age < 60 { return "\(Int(age))s ago" }
        let mins = Int(age) / 60
        return "\(mins)m ago"
    }

    var latencyLabel: String? {
        guard let ms = latency_ms else { return nil }
        return "\(Int(ms))ms"
    }
}

struct HubStream: Codable, Identifiable, Hashable {
    let name: String
    let format: String
    let level_dbfs: Double?
    let sla_pct: Double?
    let ai_status: String    // "alert" | "warn" | "learning" | "ok"
    let ai_phase: String
    let rtp_loss_pct: Double?
    let rtp_jitter_ms: Double?
    // RDS metadata (FM streams)
    let fm_rds_ps: String?   // Programme Service name, e.g. "COOL FM  "
    let fm_rds_rt: String?   // RadioText / now-playing
    // DAB metadata
    let dab_service: String?   // Service name, e.g. "Cool FM"
    let dab_dls: String?       // Dynamic Label Segment / now-playing
    let dab_ensemble: String?  // Ensemble/multiplex name
    // Live stream URL for quick-listen
    let live_url: String?

    let glitch_count: Int?

    var id: String { name }

    var glitchLabel: String? {
        guard let count = glitch_count, count > 0 else { return nil }
        return "⚡ \(count) glitch\(count == 1 ? "" : "es")"
    }

    /// Non-nil when there is meaningful RTP packet loss (> 0).
    var rtpLossLabel: String? {
        guard let loss = rtp_loss_pct, loss > 0 else { return nil }
        return String(format: "%.1f%% loss", loss)
    }

    /// Non-nil when there is meaningful RTP jitter (> 0).
    var rtpJitterLabel: String? {
        guard let jitter = rtp_jitter_ms, jitter > 0 else { return nil }
        return String(format: "%.0fms jitter", jitter)
    }

    var rtpJitterColor: Color {
        guard let jitter = rtp_jitter_ms else { return Theme.mutedText }
        if jitter >= 50 { return Theme.faultRed }
        if jitter >= 20 { return Theme.pendingAmber }
        return Theme.okGreen
    }

    var rtpLossColor: Color {
        guard let loss = rtp_loss_pct else { return Theme.mutedText }
        if loss >= 5 { return Theme.faultRed }
        if loss >= 1 { return Theme.pendingAmber }
        return Theme.okGreen
    }

    /// Station/service name from RDS PS or DAB service name (trimmed).
    var stationName: String? {
        let rds = (fm_rds_ps ?? "").trimmingCharacters(in: .whitespaces)
        if !rds.isEmpty { return rds }
        let dab = (dab_service ?? "").trimmingCharacters(in: .whitespaces)
        if !dab.isEmpty { return dab }
        return nil
    }

    /// Now-playing text from RDS RadioText or DAB DLS (trimmed).
    var nowPlayingText: String? {
        let rt = (fm_rds_rt ?? "").trimmingCharacters(in: .whitespaces)
        if !rt.isEmpty { return rt }
        let dls = (dab_dls ?? "").trimmingCharacters(in: .whitespaces)
        if !dls.isEmpty { return dls }
        return nil
    }

    var levelFraction: Double {
        guard let level = level_dbfs else { return 0 }
        return max(0, min(1, (level + 60) / 60))
    }

    var levelColor: Color {
        guard let level = level_dbfs else { return Theme.mutedText }
        if level >= -12 { return Theme.pendingAmber }
        if level >= -36 { return Theme.okGreen }
        return Theme.faultRed
    }

    var aiStatusColor: Color {
        switch ai_status {
        case "alert":    return Theme.faultRed
        case "warn":     return Theme.pendingAmber
        case "learning": return Theme.brandBlue
        default:         return Theme.okGreen
        }
    }

    var aiStatusLabel: String {
        switch ai_status {
        case "alert":    return "AI Alert"
        case "warn":     return "AI Warn"
        case "learning": return "Learning"
        default:         return "AI OK"
        }
    }
}

// MARK: - API response wrappers

struct ChainsListResponse: Codable {
    let ok: Bool
    let results: [ChainSummary]
    let generated_at: TimeInterval
}

struct ChainDetailResponse: Codable {
    let ok: Bool
    let chain: ChainSummary
}

struct ActiveFaultsResponse: Codable {
    let ok: Bool
    let results: [ChainSummary]
    let count: Int
    let generated_at: TimeInterval
}

struct ReportsEventsResponse: Codable {
    let ok: Bool
    let results: [ReportEvent]
    let count: Int
    let generated_at: TimeInterval?
}

struct ReportsSummaryResponse: Codable {
    let ok: Bool
    let total: Int
    let with_clips: Int
    let counts: [String: Int]
    let sites: [ReportSiteSummary]
    let generated_at: TimeInterval?
}

struct ReportSiteSummary: Codable, Hashable, Identifiable {
    let site: String
    let count: Int

    var id: String { site }
}

struct ChainSummary: Codable, Identifiable, Hashable {
    static func == (lhs: ChainSummary, rhs: ChainSummary) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    let id: String
    let name: String
    let status: String
    let display_status: String
    let fault_index: Int?
    let fault_at: String?
    let fault_reason: String?
    let pending: Bool
    let adbreak: Bool
    let adbreak_remaining: Double?
    let maintenance: Bool
    let maintenance_nodes: [String]
    let shared_fault_chains: [String]
    let flapping: Bool
    let sla_pct: Double
    let updated_at: TimeInterval
    let age_secs: Double
    let nodes: [ChainNode]
    let fault_since_ts: TimeInterval?
    // Chain health score (0–100). Added in backend 3.2.67; nil for older API responses.
    let health_score: Int?
    let health_label: String?

    var displayStatus: ChainDisplayStatus {
        let normalized = display_status.lowercased()
        switch normalized {
        case "ok", "active", "healthy", "good":
            return .ok
        case "fault", "faulted", "failed", "down":
            return .fault
        case "pending", "starting", "warmup":
            return .pending
        case "adbreak", "ad_break":
            return .adbreak
        case "inactive", "disabled", "idle":
            return .pending
        default:
            if adbreak { return .adbreak }
            if pending { return .pending }
            return .unknown
        }
    }

    var nodeCount: Int {
        nodes.reduce(0) { $0 + $1.deepNodeCount }
    }

    var sortPriority: Int {
        if displayStatus == .fault { return 0 }
        if flapping { return 1 }
        if maintenance { return 2 }
        if pending || adbreak { return 3 }
        return 4
    }

    var healthLabel: String {
        if displayStatus == .fault { return "Fault" }
        if flapping { return "Unstable" }
        if maintenance { return "Maintenance" }
        if pending { return "Pending" }
        if adbreak { return "Adbreak" }
        if sla_pct >= 99.95 { return "Excellent" }
        if sla_pct >= 99.0 { return "Healthy" }
        return "Watch"
    }

    var headlineReason: String {
        if let reason = fault_reason, !reason.isEmpty { return reason }
        if flapping { return "Intermittent state changes detected" }
        if maintenance { return "Maintenance mode active" }
        if pending { return "Awaiting confirmation logic" }
        return displayStatus.label.capitalized
    }

    var activeFlags: [String] {
        var flags: [String] = []
        if pending { flags.append("Pending") }
        if adbreak { flags.append("Adbreak") }
        if maintenance { flags.append("Maintenance") }
        if flapping { flags.append("Flapping") }
        return flags
    }

    var diagramNodes: [ChainNode] { nodes }

    var faultNodeID: String? {
        guard let fault_at, !fault_at.isEmpty else { return nil }
        for node in nodes {
            if let found = node.findNodeID(matchingLabel: fault_at) {
                return found
            }
        }
        return nil
    }

    var isStale: Bool { age_secs >= 30 }

    /// Short label for the health score badge, e.g. "Healthy 94" or nil when not available.
    var healthScoreDisplay: String? {
        guard let score = health_score else { return nil }
        let label = health_label ?? "Score"
        return "\(label) \(score)"
    }

    var healthScoreColor: Color {
        guard let score = health_score else { return Theme.secondaryText }
        if score >= 90 { return Theme.okGreen }
        if score >= 75 { return Theme.pendingAmber }
        if score >= 50 { return Color.orange }
        return Theme.faultRed
    }

    var siteGroups: [String] {
        Array(Set(nodes.flatMap { $0.allSites })).sorted()
    }

    var dominantSite: String? {
        siteGroups.first
    }

    /// Merge top-level status fields from a list-level summary into this (richer) detail object.
    /// Keeps the full node tree from self; updates status/fault/flags from the summary.
    func merging(summary: ChainSummary) -> ChainSummary {
        // If the detail already has fresh data, keep it — only merge if summary is newer
        guard summary.updated_at > self.updated_at else { return self }
        // Preserve the richer node tree from the detail fetch unless the summary also has nodes
        let mergedNodes = summary.nodes.isEmpty ? self.nodes : summary.nodes
        return ChainSummary(
            id: id,
            name: summary.name,
            status: summary.status,
            display_status: summary.display_status,
            fault_index: summary.fault_index,
            fault_at: summary.fault_at,
            fault_reason: summary.fault_reason,
            pending: summary.pending,
            adbreak: summary.adbreak,
            adbreak_remaining: summary.adbreak_remaining,
            maintenance: summary.maintenance,
            maintenance_nodes: summary.maintenance_nodes,
            shared_fault_chains: summary.shared_fault_chains,
            flapping: summary.flapping,
            sla_pct: summary.sla_pct,
            updated_at: summary.updated_at,
            age_secs: summary.age_secs,
            nodes: mergedNodes,
            fault_since_ts: summary.fault_since_ts ?? self.fault_since_ts,
            health_score: summary.health_score ?? self.health_score,
            health_label: summary.health_label ?? self.health_label
        )
    }
}

struct ChainNode: Codable, Identifiable, Hashable {
    let type: String
    let label: String
    let stream: String?
    let site: String?
    let status: String
    let reason: String?
    let machine: String?
    let live_url: String?
    let level_dbfs: Double?
    let ts: TimeInterval?
    let mode: String?
    let rtp_loss_pct: Double?
    let glitch_count: Int?
    let nodes: [ChainNode]?

    var id: String {
        // Stack nodes have no stream/site/machine, so include a fingerprint of their
        // child labels to produce a unique ID even when two stacks share the same label.
        let childKey = childNodes.isEmpty ? "" : childNodes.map { "\($0.label)|\($0.stream ?? "")" }.joined(separator: ",")
        return [type, label, stream ?? "", site ?? "", machine ?? "", childKey].joined(separator: "|")
    }

    var childNodes: [ChainNode] {
        nodes ?? []
    }

    var isStack: Bool {
        type.lowercased() == "stack"
    }

    var deepNodeCount: Int {
        if childNodes.isEmpty { return 1 }
        return childNodes.reduce(isStack ? 0 : 1) { $0 + $1.deepNodeCount }
    }

    var statusLabel: String {
        status.uppercased()
    }

    var normalizedStatus: String {
        status.lowercased()
    }

    var isFaultLike: Bool {
        ["down", "offline"].contains(normalizedStatus)
    }

    var isMaintenance: Bool {
        normalizedStatus == "maintenance"
    }

    var allSites: [String] {
        var values: [String] = []
        if let site, !site.isEmpty { values.append(site) }
        for child in childNodes {
            for site in child.allSites where !values.contains(site) {
                values.append(site)
            }
        }
        return values
    }

    var displayLevelDbfs: Double? {
        if let level_dbfs { return level_dbfs }
        let childLevels = childNodes.compactMap { $0.displayLevelDbfs }
        return childLevels.max()
    }

    var signalLabel: String {
        guard let level = displayLevelDbfs else { return childNodes.isEmpty ? "No level" : "Child level" }
        if level >= -12 { return "Hot" }
        if level >= -24 { return "Healthy" }
        if level >= -42 { return "Low" }
        return "Near silence"
    }

    var freshestTimestamp: TimeInterval? {
        ([ts] + childNodes.map { $0.freshestTimestamp }).compactMap { $0 }.max()
    }

    var isStale: Bool {
        guard let freshestTimestamp else { return false }
        return Date().timeIntervalSince1970 - freshestTimestamp > 30
    }

    var staleLabel: String? {
        guard let freshestTimestamp else { return nil }
        let age = Date().timeIntervalSince1970 - freshestTimestamp
        guard age > 30 else { return nil }
        return "Telemetry age \(age.formattedSeconds())"
    }

    var glitchLabel: String? {
        guard let count = glitch_count, count > 0 else { return nil }
        return "⚡ \(count)"
    }

    var signalFraction: Double? {
        guard let level = displayLevelDbfs else { return nil }
        let clamped = min(max(level, -60), 0)
        return (clamped + 60) / 60
    }

    func resolvedLiveURL(baseURL: URL?) -> URL? {
        guard let live_url else { return nil }

        let trimmed = live_url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let absolute = URL(string: trimmed), absolute.scheme != nil {
            return absolute
        }

        if let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let absolute = URL(string: encoded), absolute.scheme != nil {
            return absolute
        }

        guard let baseURL else { return nil }
        if let relative = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL {
            return relative
        }
        if let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
            return URL(string: encoded, relativeTo: baseURL)?.absoluteURL
        }
        return nil
    }

    func findNodeID(matchingLabel label: String) -> String? {
        if self.label.caseInsensitiveCompare(label) == .orderedSame {
            return id
        }
        for child in childNodes {
            if let found = child.findNodeID(matchingLabel: label) {
                return found
            }
        }
        return nil
    }
}

struct ReportEvent: Codable, Hashable, Identifiable {
    let id: String
    let ts: ReportTimestampValue?
    let site: String
    let chain: String
    let stream: String
    let type: String
    let message: String
    let level_dbfs: Double?
    let rtp_loss_pct: Double?
    let rtp_jitter_ms: Double?
    let ptp_state: String?
    let ptp_offset_us: Double?
    let ptp_drift_us: Double?
    let ptp_jitter_us: Double?
    let ptp_gm: String?
    let clip: Bool
    let clip_name: String?
    let clip_id: String?
    let clip_url: String?
    let online: Bool?
    let source: String?

    var timestampDate: Date? { ts?.date }

    var timestampLabel: String {
        if let date = timestampDate {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return "Unknown time"
    }

    var headlineText: String {
        if !message.isEmpty { return message }
        if !type.isEmpty { return type.replacingOccurrences(of: "_", with: " ") }
        return "Report event"
    }

    var metrics: [MetricChipData] {
        var items: [MetricChipData] = []
        if let level_dbfs { items.append(.init(icon: "waveform", text: level_dbfs.formattedDbfs())) }
        if let rtp_loss_pct { items.append(.init(icon: "antenna.radiowaves.left.and.right", text: String(format: "RTP %.1f%%", rtp_loss_pct))) }
        if let rtp_jitter_ms { items.append(.init(icon: "shuffle", text: String(format: "Jitter %.1fms", rtp_jitter_ms))) }
        if let ptp_state, !ptp_state.isEmpty { items.append(.init(icon: "clock.arrow.circlepath", text: ptp_state)) }
        if let ptp_offset_us { items.append(.init(icon: "clock.badge.exclamationmark", text: String(format: "PTP %.0fµs", ptp_offset_us))) }
        if clip { items.append(.init(icon: "waveform.circle", text: "Clip")) }
        return items
    }

    var clipResolvedURL: URL? {
        guard let clip_url else { return nil }
        return URL(string: clip_url)
    }
}

enum ReportTimestampValue: Codable, Hashable {
    case double(Double)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Double.self) {
            self = .double(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        throw DecodingError.typeMismatch(ReportTimestampValue.self, .init(codingPath: decoder.codingPath, debugDescription: "Unsupported timestamp type"))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .double(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        }
    }

    var date: Date? {
        switch self {
        case .double(let value):
            return Date(timeIntervalSince1970: value)
        case .string(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let iso = ISO8601DateFormatter()
            if let date = iso.date(from: trimmed) { return date }
            let formatters = ["yyyy-MM-dd HH:mm:ss", "yyyyMMdd-HHmmss", "dd MMM yyyy HH:mm:ss"]
            for pattern in formatters {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = .current
                formatter.dateFormat = pattern
                if let date = formatter.date(from: trimmed) { return date }
            }
            if let value = Double(trimmed) {
                return Date(timeIntervalSince1970: value)
            }
            return nil
        }
    }
}

// MARK: - Engineer Notes / Fault Log

struct FaultLogClip: Codable, Hashable, Identifiable {
    let key: String
    let fname: String
    let label: String
    let node_label: String
    let pos: Int?
    let status: String
    /// Relative path appended to baseURL to stream/download the clip
    let url: String

    var id: String { "\(key)/\(fname)" }

    /// Human-readable display name for the clip (e.g. "Studio Feed (fault)")
    var displayName: String {
        let base = node_label.isEmpty ? key : node_label
        let suffix: String
        switch label {
        case "fault":     suffix = "fault"
        case "last_good": suffix = "last good"
        default:          suffix = label.replacingOccurrences(of: "_", with: " ")
        }
        return "\(base) (\(suffix))"
    }

    /// SF Symbol name reflecting the node's status
    var statusIcon: String {
        switch status {
        case "fault":     return "exclamationmark.triangle.fill"
        case "last_good": return "checkmark.circle.fill"
        default:          return "waveform.circle"
        }
    }

    /// Colour key string for the status indicator
    var statusColor: String {
        switch status {
        case "fault":     return "red"
        case "last_good": return "green"
        default:          return "secondary"
        }
    }
}

struct FaultLogEntry: Codable, Identifiable, Hashable {
    let id: String
    let chain_id: String
    let ts_start: TimeInterval
    let ts_recovered: TimeInterval?
    let fault_node_label: String
    let fault_site: String
    let fault_stream: String?
    let rtp_loss_pct: Double?
    /// Audio clips captured at every chain position when the fault fired.
    /// Older fault log entries that pre-date this feature will have an empty array.
    let clips: [FaultLogClip]
    let note: String?
    let note_by: String?
    let note_ts: String?

    // Explicit memberwise init (needed because the custom Codable init below
    // suppresses Swift's synthesised memberwise initialiser).
    init(id: String, chain_id: String, ts_start: TimeInterval,
         ts_recovered: TimeInterval?, fault_node_label: String,
         fault_site: String, fault_stream: String?, rtp_loss_pct: Double?,
         clips: [FaultLogClip] = [], note: String?, note_by: String?,
         note_ts: String?) {
        self.id               = id
        self.chain_id         = chain_id
        self.ts_start         = ts_start
        self.ts_recovered     = ts_recovered
        self.fault_node_label = fault_node_label
        self.fault_site       = fault_site
        self.fault_stream     = fault_stream
        self.rtp_loss_pct     = rtp_loss_pct
        self.clips            = clips
        self.note             = note
        self.note_by          = note_by
        self.note_ts          = note_ts
    }

    // Custom decode so `clips` defaults to [] when absent (older API responses)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id               = try c.decode(String.self,       forKey: .id)
        chain_id         = try c.decode(String.self,       forKey: .chain_id)
        ts_start         = try c.decode(TimeInterval.self, forKey: .ts_start)
        ts_recovered     = try c.decodeIfPresent(TimeInterval.self, forKey: .ts_recovered)
        fault_node_label = try c.decode(String.self,       forKey: .fault_node_label)
        fault_site       = try c.decode(String.self,       forKey: .fault_site)
        fault_stream     = try c.decodeIfPresent(String.self, forKey: .fault_stream)
        rtp_loss_pct     = try c.decodeIfPresent(Double.self, forKey: .rtp_loss_pct)
        clips            = (try? c.decode([FaultLogClip].self, forKey: .clips)) ?? []
        note             = try c.decodeIfPresent(String.self, forKey: .note)
        note_by          = try c.decodeIfPresent(String.self, forKey: .note_by)
        note_ts          = try c.decodeIfPresent(String.self, forKey: .note_ts)
    }

    var startDate: Date { Date(timeIntervalSince1970: ts_start) }
    var recoveredDate: Date? { ts_recovered.map { Date(timeIntervalSince1970: $0) } }
    var isOngoing: Bool { ts_recovered == nil }
    var hasNote: Bool { !(note ?? "").isEmpty }

    var durationLabel: String {
        guard let recovered = recoveredDate else { return "Ongoing" }
        return (recovered.timeIntervalSince1970 - ts_start).formattedSeconds()
    }

    var startLabel: String {
        startDate.formatted(date: .abbreviated, time: .shortened)
    }
}

struct FaultLogResponse: Codable {
    let ok: Bool
    let chain_id: String
    let entries: [FaultLogEntry]
    let count: Int
}

struct ChainNoteRecord: Codable {
    let text: String
    let by: String
    let ts: String
    let edited_at: String?
}

struct ChainNoteSaveResponse: Codable {
    let ok: Bool
    let fault_log_id: String
    let record: ChainNoteRecord
}

struct MobileTokenStatusResponse: Codable {
    let ok: Bool
    let enabled: Bool?
    let token: String?
    let token_masked: String?
    let token_present: Bool?
}

// MARK: - Signal History

struct MetricPoint: Codable, Identifiable {
    let ts: Double
    let value: Double
    var id: Double { ts }
}

struct MetricHistoryResponse: Codable {
    let ok: Bool
    let stream: String
    let site: String
    let metric: String
    let hours: Int
    let points: [MetricPoint]
}

// MARK: - A/B Groups

struct ABGroup: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let active_role: String   // "a" or "b"
    let notes: String
    let chain_a_id: String
    let chain_a_name: String
    let chain_b_id: String
    let chain_b_name: String
    let status: String        // "ok" | "warn" | "fault" | "unknown"
    let a_ok: Bool
    let b_ok: Bool
    let rx_ok: Bool
    let since: Double

    var statusColor: Color {
        switch status {
        case "fault":   return Theme.faultRed
        case "warn":    return Theme.pendingAmber
        case "ok":      return Theme.okGreen
        default:        return Theme.mutedText
        }
    }

    var activeName: String {
        active_role == "b" ? chain_b_name : chain_a_name
    }

    var standbyName: String {
        active_role == "b" ? chain_a_name : chain_b_name
    }
}

struct ABGroupsResponse: Codable {
    let ok: Bool
    let results: [ABGroup]
    let count: Int
}

// MARK: - Hub navigation

/// Pairs a HubStream with its parent site name for use as a NavigationLink value.
struct HubStreamRef: Hashable {
    let siteName: String
    let stream: HubStream
}

// MARK: - FM Scanner Models

struct ScannerSite: Codable, Identifiable, Hashable {
    let site: String
    let serials: [String]
    var id: String { site }
}

struct ScannerSitesResponse: Codable {
    let ok: Bool
    let sites: [ScannerSite]
}

struct ScannerStartResponse: Codable {
    let ok: Bool
    let slot_id: String?
    let stream_url: String?
    let mobile_stream_url: String?
    let freq_mhz: Double?
    let error: String?
}

struct ScannerStatus: Codable {
    let ok: Bool
    let active: Bool
    let freq_mhz: Double?
    let streaming: Bool?
    let ps: String?
    let rt: String?
    let stereo: Bool?
    let pi: String?
    let stream_url: String?
    let mobile_stream_url: String?
}

// MARK: - DAB Scanner Models

struct DABSite: Codable, Identifiable, Hashable {
    let site: String
    let serials: [String]
    var id: String { site }
}

struct DABSitesResponse: Codable {
    let ok: Bool
    let sites: [DABSite]
}

struct DABStartResponse: Codable {
    let ok: Bool
    let slot_id: String?
    let stream_url: String?
    let mobile_stream_url: String?
    let error: String?
}

struct DABStatus: Codable {
    let ok: Bool
    let active: Bool
    let service: String?
    let channel: String?
    let dls: String?
    let streaming: Bool?
    let stream_url: String?
    let mobile_stream_url: String?
}

struct DABService: Codable, Identifiable, Hashable {
    let label: String
    let channel: String
    var id: String { "\(channel)/\(label)" }

    private enum CodingKeys: String, CodingKey {
        case label, name, channel
    }

    // The server stores services with key "name" (welle-cli output).
    // Accept both "label" and "name" so the model works with the server as-is.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        channel = try c.decode(String.self, forKey: .channel)
        if let l = try? c.decodeIfPresent(String.self, forKey: .label), !l.isEmpty {
            label = l
        } else {
            label = try c.decode(String.self, forKey: .name)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(label, forKey: .label)
        try c.encode(channel, forKey: .channel)
    }
}

struct DABServicesResponse: Codable {
    let ok: Bool
    let services: [DABService]
    let scanned_at: String?
}

struct DABScanStatus: Codable {
    let ok: Bool
    let status: String    // "idle" | "scanning" | "done"
    let progress: Int?
    let total: Int?
    let found: Int?
    let channel: String?
}

struct DABRegion: Codable, Identifiable {
    let id: String
    let label: String
    let icon: String
    let channels: [String]
    let children: [DABRegion]

    /// Flattened list of self + all descendants (leaf nodes shown first if they have channels)
    var allDescendants: [DABRegion] {
        var result: [DABRegion] = []
        if !children.isEmpty {
            result.append(self)
            result.append(contentsOf: children.flatMap { $0.allDescendants })
        } else {
            result.append(self)
        }
        return result
    }
}

struct DABRegionsResponse: Codable {
    let ok: Bool
    let regions: DABRegion
}

// MARK: - Maintenance Response

struct MaintenanceResponse: Codable {
    let ok: Bool
    let maintenance: Bool?
    let nodes: Int?
    let error: String?
}

extension Array where Element == ChainNode {
    /// Recursively flattens all nodes and their children into a single array.
    func flattenedAll() -> [ChainNode] {
        flatMap { node -> [ChainNode] in
            [node] + node.childNodes.flattenedAll()
        }
    }
}

extension TimeInterval {
    var asDate: Date { Date(timeIntervalSince1970: self) }
}

extension Double {
    func formattedSeconds() -> String {
        if self < 60 { return String(format: "%.0fs", self) }
        let minutes = Int(self) / 60
        let seconds = Int(self) % 60
        return String(format: "%dm %02ds", minutes, seconds)
    }

    func formattedPercent() -> String {
        String(format: "%.1f%%", self)
    }

    func formattedDbfs() -> String {
        String(format: "%.1f dBFS", self)
    }
}

// MARK: - Logger

struct LoggerStream: Identifiable, Codable, Hashable {
    let name: String
    let slug: String
    var id: String { slug }
}

struct LoggerSegment: Identifiable {
    let filename: String
    let start_s: Double
    let hasSilence: Bool
    let silence_pct: Double?
    var id: String { filename }

    var startLabel: String {
        let totalSeconds = Int(start_s)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        return String(format: "%02d:%02d", h, m)
    }

    var durationLabel: String { "5 min" }
}

extension LoggerSegment: Codable {
    enum CodingKeys: String, CodingKey {
        case filename, start_s, has_silence, silence_pct
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        filename    = try c.decode(String.self, forKey: .filename)
        start_s     = try c.decode(Double.self,  forKey: .start_s)
        silence_pct = try c.decodeIfPresent(Double.self, forKey: .silence_pct)
        // Python SQLite stores has_silence as 0/1 integer; handle both int and bool
        if let b = try? c.decodeIfPresent(Bool.self, forKey: .has_silence) {
            hasSilence = b ?? false
        } else if let i = try? c.decodeIfPresent(Int.self, forKey: .has_silence) {
            hasSilence = (i ?? 0) != 0
        } else {
            hasSilence = false
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(filename,    forKey: .filename)
        try c.encode(start_s,     forKey: .start_s)
        try c.encode(hasSilence,  forKey: .has_silence)
        try c.encodeIfPresent(silence_pct, forKey: .silence_pct)
    }
}

struct LoggerMetaEvent: Identifiable, Codable {
    let ts_s: Double
    let type: String
    let title: String?
    let artist: String?
    let show_name: String?
    let presenter: String?
    var id: String { "\(ts_s)-\(type)-\(title ?? "")" }

    var isShow: Bool { type == "show" }
    var isTrack: Bool { type == "track" }
    var isMicOn: Bool  { type == "mic_on" }
    var isMicOff: Bool { type == "mic_off" }

    var primaryLabel: String {
        if isTrack { return (title ?? "").isEmpty ? "Unknown Track" : title! }
        if isShow  { return (show_name ?? "").isEmpty ? "Show" : show_name! }
        if isMicOn  { return "Mic On" }
        if isMicOff { return "Mic Off" }
        return (title ?? "").isEmpty ? type : title!
    }

    var secondaryLabel: String? {
        if isTrack, let a = artist, !a.isEmpty { return a }
        if isShow,  let p = presenter, !p.isEmpty { return p }
        return nil
    }

    var timeLabel: String {
        let totalSeconds = Int(ts_s)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        return String(format: "%02d:%02d", h, m)
    }
}

struct LoggerStatusResponse: Codable {
    let installed: Bool
}

struct LoggerSitesResponse: Codable {
    let sites: [String]
}

struct LoggerStreamsResponse: Codable {
    let streams: [LoggerStream]
}

struct LoggerDaysResponse: Codable {
    let days: [String]
    let pending: Bool?
}

struct LoggerSegmentsResponse: Codable {
    let segments: [LoggerSegment]
    let pending: Bool?
}

struct LoggerMetadataResponse: Codable {
    let events: [LoggerMetaEvent]
    let pending: Bool?
}

struct LoggerPlayResponse: Codable {
    let ok: Bool?
    let slot_id: String?
    let stream_url: String?
    let error: String?
}
