import Foundation
import Combine
import MQTTNIO
import NIOCore

/// Owns Burnrate's long-lived MQTT connection. It reconnects after a broker
/// disconnect and subscribes to the configured topic on every new session.
@MainActor
final class MQTTService: ObservableObject {
    static let shared = MQTTService()

    enum Status: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)

        var label: String {
            switch self {
            case .disconnected: return "Disconnected"
            case .connecting: return "Connecting…"
            case .connected: return "Connected and listening"
            case .failed(let message): return message
            }
        }
    }

    @Published private(set) var status: Status = .disconnected

    private struct Configuration: Equatable {
        let host: String
        let username: String
        let password: String
        let topic: String
    }

    private var client: MQTTClient?
    private var activeConfiguration: Configuration?
    private var listenerTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    let clientIdentifier: String = {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "Burnrate-\(version)-\(build)"
    }()

    private init() {}

    func configure(settings: AppSettings) {
        let configuration = Configuration(
            host: settings.mqttHost.trimmingCharacters(in: .whitespacesAndNewlines),
            username: settings.mqttUsername.trimmingCharacters(in: .whitespacesAndNewlines),
            password: settings.mqttPassword,
            topic: settings.mqttTopic.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        guard settings.mqttEnabled, !configuration.host.isEmpty, !configuration.topic.isEmpty else {
            disconnect()
            return
        }
        guard activeConfiguration != configuration || client == nil else { return }

        disconnect()
        activeConfiguration = configuration
        startConnection(using: configuration)
    }

    func reconnect(settings: AppSettings) {
        disconnect()
        configure(settings: settings)
    }

    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        listenerTask?.cancel()
        listenerTask = nil

        let client = client
        self.client = nil
        activeConfiguration = nil
        status = .disconnected

        guard let client else { return }
        Task {
            try? await client.shutdown()
        }
    }

    private func startConnection(using configuration: Configuration) {
        guard activeConfiguration == configuration, client == nil else { return }

        do {
            let endpoint = try parseEndpoint(configuration.host)
            let client = MQTTClient(
                host: endpoint.host,
                port: endpoint.port,
                identifier: clientIdentifier,
                eventLoopGroupProvider: .createNew,
                configuration: .init(
                    userName: configuration.username.nilIfBlank,
                    password: configuration.password.nilIfBlank
                )
            )
            self.client = client
            status = .connecting
            LogService.shared.log(.info, .mqtt, "Connecting to \(configuration.host)")

            client.addCloseListener(named: "burnrate.connection") { [weak self, weak client] result in
                Task { @MainActor in
                    guard let self, let client else { return }
                    self.connectionClosed(client: client, configuration: configuration, result: result)
                }
            }

            Task { [weak self, weak client] in
                guard let self, let client else { return }
                do {
                    try await client.connect()
                    guard self.client === client, self.activeConfiguration == configuration else {
                        try? await client.shutdown()
                        return
                    }
                    let subscription = MQTTSubscribeInfo(topicFilter: configuration.topic, qos: .atLeastOnce)
                    _ = try await client.subscribe(to: [subscription])
                    self.status = .connected
                    LogService.shared.log(.info, .mqtt, "Connected and subscribed to \(configuration.topic)")
                    self.listen(for: client, topic: configuration.topic)
                } catch {
                    self.connectionFailed(client: client, configuration: configuration, error: error)
                }
            }
        } catch {
            status = .failed(error.localizedDescription)
            LogService.shared.log(.error, .mqtt, "Invalid broker host: \(error.localizedDescription)")
        }
    }

    private func listen(for client: MQTTClient, topic: String) {
        listenerTask?.cancel()
        listenerTask = Task { [weak client] in
            guard let client else { return }
            for await result in client.createPublishListener() {
                guard !Task.isCancelled else { return }
                switch result {
                case .success(let message):
                    var payload = message.payload
                    let text = payload.readString(length: payload.readableBytes) ?? "<binary payload>"
                    LogService.shared.log(.info, .mqtt, "Received \(message.topicName): \(text)")
                case .failure(let error):
                    LogService.shared.log(.warning, .mqtt, "Receive error on \(topic): \(error.localizedDescription)")
                }
            }
        }
    }

    private func connectionFailed(client: MQTTClient, configuration: Configuration, error: Error) {
        guard self.client === client, activeConfiguration == configuration else { return }
        self.client = nil
        status = .failed("Connection failed: \(error.localizedDescription)")
        LogService.shared.log(.error, .mqtt, "Connection failed: \(error.localizedDescription)")
        Task {
            try? await client.shutdown()
        }
        scheduleReconnect(configuration: configuration)
    }

    private func connectionClosed(client: MQTTClient, configuration: Configuration, result: Result<Void, Error>) {
        guard self.client === client, activeConfiguration == configuration else { return }
        self.client = nil
        listenerTask?.cancel()
        listenerTask = nil

        let reason: String
        switch result {
        case .success: reason = "Broker disconnected"
        case .failure(let error): reason = "Connection lost: \(error.localizedDescription)"
        }
        status = .failed(reason)
        LogService.shared.log(.warning, .mqtt, "\(reason) — reconnecting")
        scheduleReconnect(configuration: configuration)
    }

    private func scheduleReconnect(configuration: Configuration) {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self, self.activeConfiguration == configuration, self.client == nil else { return }
            self.startConnection(using: configuration)
        }
    }

    private func parseEndpoint(_ value: String) throws -> (host: String, port: Int?) {
        guard !value.isEmpty else { throw ConnectionError.invalidHost }
        let components = URLComponents(string: "mqtt://\(value)")
        guard let hostname = components?.host, !hostname.isEmpty else { throw ConnectionError.invalidHost }
        return (hostname, components?.port)
    }

    enum ConnectionError: LocalizedError {
        case invalidHost
        var errorDescription: String? { "Enter a valid MQTT host" }
    }
}

private extension String {
    var nilIfBlank: String? {
        isEmpty ? nil : self
    }
}
