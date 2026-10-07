// The Swift Programming Language
// https://docs.swift.org/swift-book
//
//  ActionSocket.swift
//  Action Socket
//
//  Created by Will Robinson on 10/6/26.

import Foundation


public actor ActionSocket {
    public struct Config {
        let url: URL
        let channel: String
        let headers: [Header]
    }
    
    
    public struct Header {
        public let field: String
        public let value: String
        
        public init(field: String, value: String) {
            self.field = field
            self.value = value
        }
    }
    
    
    struct Subscription: Codable {
        let type: Keys
        
        
        enum Keys: String, Codable {
            case welcome
            case confirmed = "confirm_subscription"
        }
    }
    
    
    public enum SocketError: Error {
        case webSocketTaskUnavailable
        case webSocketDisconnected
        case webSocketInvalidFormat
    }
    
    
    public enum StreamEvent: Sendable {
        case connection(Bool)
        case subscription(Bool)
        case data(Data)
        case ping(TimeInterval)
    }
    
    
    struct Ping: Codable, Sendable {
        let type: Key
        let at: TimeInterval
        
        enum Key: String, Codable {
            case ping
        }
        
        enum CodingKeys: String, CodingKey {
            case type
            case at = "message"
        }
    }
    
    
    let config: Config
    let identifier: [String: String]
    
    
    init(config: Config){
        self.config = config
        self.identifier = ["channel": config.channel]
    }
    
    
    public init(_ urlString: String, channel: String, headers: [Header] = []){
        let config = Config(url: URL(string: urlString)!, channel: channel, headers: headers)
        self.init(config: config)
    }
    
    
    public init(_ url: URL, channel: String, headers: [Header] = []){
        let config = Config(url: url, channel: channel, headers: headers)
        self.init(config: config)
    }
    
    
    var isConnected: Bool = false
    var isSubscribed: Bool = false
    var permanentDisconnect: Bool = false
    var webSocketTask: URLSessionWebSocketTask?
    var reconnectAttempts: Int = 0
    
    
    /// STREAM ----------------------------------------------------------------------------------------
    var continuation: AsyncStream<StreamEvent>.Continuation?
    public var stream: AsyncStream<StreamEvent> {
        connect()
        return AsyncStream { continuation in
            self.continuation = continuation
            
            continuation.onTermination = { [weak self] _ in
                continuation.yield(.connection(false))
                continuation.yield(.subscription(false))
                Task { [weak self] in
                    await self?.disconnect()
                }
            }
        }
    }
    /// -------------------------------------------------------
    
    
    func connect() {
        if isConnected { return }
        
        var request = URLRequest(url: config.url)
        
        config.headers.forEach { request.addValue($0.value, forHTTPHeaderField: $0.field) }
        
        let session = URLSession(configuration: .default)
        
        permanentDisconnect = false
        
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()
        
        listenForMessages()
    }
    
    
    public func disconnect() {
        isConnected = false
        isSubscribed = false
        continuation?.yield(.connection(false))
        continuation?.yield(.subscription(false))
        permanentDisconnect = true
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        continuation?.finish()
    }
    
    
    func listenForMessages() {
        Task {
            do {
                if let message = try await webSocketTask?.receive() {
                    handleMessage(message)
                } else {
                    throw SocketError.webSocketTaskUnavailable
                }
            } catch {
                handleDisconnect()
            }
        }
    }
    
    
    func handleDisconnect() {
        isConnected = false
        isSubscribed = false
        
        continuation?.yield(.connection(false))
        continuation?.yield(.subscription(false))
        
        if permanentDisconnect {
            reconnectAttempts = 0
            return
        }
        
        reconnectAttempts += 1
        
        let reconnectDelay = Double(min(3, reconnectAttempts))
        
        Task {
            try? await Task.sleep(for: .seconds(reconnectDelay))
            connect()
        }
    }
    
    
    func subscribe() async throws {
        guard let task = webSocketTask, isConnected else { throw SocketError.webSocketDisconnected }
        
        let identifier = ["channel": config.channel]
        
        let payload: [String: Any] = [
            "command": "subscribe",
            "identifier": identifier.actionSocketToJSON!
        ]
        
        if let payload = payload.actionSocketToJSON {
            try await task.send(.string(payload))
        } else {
            throw SocketError.webSocketInvalidFormat
        }
    }
    
    
    func handleMessage(_ taskMessage: URLSessionWebSocketTask.Message) {
        defer { listenForMessages() }
        
        /// only send connection update if changes from false to true
        if !isConnected {
            continuation?.yield(.connection(true))
        }
        isConnected = true
        
        reconnectAttempts = 0
        
        // SUBSCRIPTION ===========================================================
        if let subscription: Subscription = taskMessage.actionSocketDecode() {
            /// Received Rails Welcom Message
            if subscription.type == .welcome {
                Task { try? await subscribe() }
                return
            }
            
            /// Received Rails Subscription Confirmation
            if subscription.type == .confirmed {
                isSubscribed = true
                continuation?.yield(.subscription(true))
                return
            }
        }
        // ========================================================================
        
        
        // PING ===================================================================
        if let ping: Ping = taskMessage.actionSocketDecode() {
            continuation?.yield(.ping(ping.at))
        }
        // ========================================================================
        
        
        // CHANNEL SUBSCRIPTION MESSAGES ONLY =====================================
        guard
            let taskMessageDictionary = taskMessage.actionSocketToDictionary,
            let identifierString = taskMessageDictionary["identifier"] as? String,
            let identifierDictionary = identifierString.actionSocketToDictionary,
            let channelString = identifierDictionary["channel"] as? String,
            channelString == config.channel,
            let messageDictionary = taskMessageDictionary["message"] as? [String: Any],
            let messageData = messageDictionary.actionSocketToData
        else { return }
        
        continuation?.yield(.data(messageData))
        // ========================================================================
    }
    
    
    public func send(_ data: [String: Any?]) async throws {
        guard let task = webSocketTask, isConnected else { throw SocketError.webSocketDisconnected }
        
        let payload: [String: Any?] = [
            "command": "message",
            "identifier": identifier.actionSocketToJSON!,
            "data": data.actionSocketToJSON!
        ]
        
        if let payload = payload.actionSocketToJSON {
            try await task.send(.string(payload))
        } else {
            throw SocketError.webSocketInvalidFormat
        }
    }
}


fileprivate extension URLSessionWebSocketTask.Message {
    func actionSocketDecode<T: Decodable>() -> T? {
        guard let decodeString: String = self.actionSocketToString else { return nil }
        
        guard let data = decodeString.data(using: .utf8) else { return nil }
        
        let decoder = JSONDecoder()
        
        return try? decoder.decode(T.self, from: data)
    }
    
    
    var actionSocketToString: String? {
        switch self {
        case .string(let text):
            return text
        default:
            return nil
        }
    }
    
    
    var actionSocketToData: Data? {
        return self.actionSocketToString?.data(using: .utf8)
    }
    
    
    var actionSocketToDictionary: [String: Any]? {
        guard let data = self.actionSocketToData else { return nil }
        return (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any]
    }
}


fileprivate extension Dictionary {
    var actionSocketToJSON: String? {
        if let data = self.actionSocketToData {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
    
    
    var actionSocketToData: Data? {
        try? JSONSerialization.data(withJSONObject: self, options: [])
    }
}


fileprivate extension String {
    var actionSocketToDictionary: [String: Any]? {
        return self.data(using: .utf8)?.actionSocketToDictionary
    }
}


fileprivate extension Data {
    var actionSocketToDictionary: [String: Any]? {
        let jsonObject = try? JSONSerialization.jsonObject(with: self, options: [])
        return jsonObject as? [String: Any]
    }
}
