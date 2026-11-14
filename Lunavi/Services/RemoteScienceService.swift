import Foundation

/// Typed errors for the optional LUNAVI science service.
enum RemoteScienceError: LocalizedError, Equatable, Sendable {
    case offline
    case timeout
    case server(status: Int, code: String, message: String)
    case invalidResponse
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .offline:
            return "The science service is unreachable."
        case .timeout:
            return "The science service did not respond in time."
        case .server(let status, let code, let message):
            return "Science service error \(status) (\(code)): \(message)"
        case .invalidResponse:
            return "The science service returned an invalid response."
        case .decoding(let detail):
            return "Could not decode the science service response: \(detail)"
        }
    }
}

// MARK: - API v1 models (see docs/API_CONTRACT.md). ISO 8601 UTC timestamps throughout.

struct HealthResponse: Codable, Sendable {
    var status: String
    var version: String
    var scenarioId: String?
    var kernelsLoaded: Bool?
}

struct VisibilityRequest: Codable, Sendable {
    var siteId: String
    var observerLatitudeDeg: Double?
    var observerLongitudeDeg: Double?
    var observerHeightM: Double
    var utcStart: Date
    var utcEnd: Date
    var timeStepS: Double
    var minimumClearanceDeg: Double
    var model: String
    var datasetIds: [String]
}

struct APIFailure: Codable, Sendable {
    var condition: VisibilityCondition
    var time: Date
}

struct VisibilityResponse: Codable, Sendable {
    var scenarioId: String
    var siteId: String
    var utcStart: Date
    var utcEnd: Date
    var coverage: [UTCRange]
    var sunlight: [UTCRange]
    var earthLineOfSight: [UTCRange]
    var combined: [UTCRange]
    var firstFailure: APIFailure?
    var events: [ExplanationEvent]
    var provenance: [ProvenanceRecord]
    var assumptions: [String]
    var validation: [ValidationRecord]
    var warnings: [String]
    var dataQuality: String
}

private struct APIErrorEnvelope: Codable {
    struct Body: Codable {
        var code: String
        var message: String
    }
    var error: Body
}

/// Client for the optional FastAPI science service. No API key; never embed secrets.
struct RemoteScienceService: MissionAnalysisService {
    let baseURL: URL
    var timeout: TimeInterval = 8

    func loadScenario() async throws -> ScenarioBundle {
        let data = try await send(path: "api/v1/scenario", method: "GET", body: nil)
        do {
            return try DatasetRepository.scenario(fromComputedJSON: data, resourceName: "science service scenario", overridingSource: .computedLive)
        } catch let error as DatasetError {
            throw RemoteScienceError.decoding(error.localizedDescription)
        }
    }

    func health() async throws -> HealthResponse {
        let data = try await send(path: "api/v1/health", method: "GET", body: nil)
        return try decode(HealthResponse.self, from: data)
    }

    func visibility(_ request: VisibilityRequest) async throws -> VisibilityResponse {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let body = try encoder.encode(request)
        let data = try await send(path: "api/v1/analysis/visibility", method: "POST", body: body)
        return try decode(VisibilityResponse.self, from: data)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try DatasetRepository.makeDecoder().decode(type, from: data)
        } catch {
            throw RemoteScienceError.decoding(String(describing: error))
        }
    }

    private func send(path: String, method: String, body: Data?) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path), timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                throw RemoteScienceError.timeout
            default:
                throw RemoteScienceError.offline
            }
        }

        guard let http = response as? HTTPURLResponse else {
            throw RemoteScienceError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
                throw RemoteScienceError.server(status: http.statusCode, code: envelope.error.code, message: envelope.error.message)
            }
            throw RemoteScienceError.server(status: http.statusCode, code: "HTTP_\(http.statusCode)", message: HTTPURLResponse.localizedString(forStatusCode: http.statusCode))
        }
        return data
    }
}
