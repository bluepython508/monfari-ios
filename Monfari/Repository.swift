//
//  Repository.swift
//  Monfari
//
//  Created by Ben on 03/09/2023.
//

import Foundation
import Network

fileprivate struct Connection {
    fileprivate class MsgFramerImpl: NWProtocolFramerImplementation {
        static let definition = NWProtocolFramer.Definition(implementation: MsgFramerImpl.self)
        static var label: String = "monfari-msg"

        required init(framer: NWProtocolFramer.Instance) {}
        
        func start(framer: NWProtocolFramer.Instance) -> NWProtocolFramer.StartResult {
            .ready
        }

        func wakeup(framer: NWProtocolFramer.Instance) {}
        
        func stop(framer: NWProtocolFramer.Instance) -> Bool {
            true
        }
        
        func cleanup(framer: NWProtocolFramer.Instance) {}
        
        func handleInput(framer: NWProtocolFramer.Instance) -> Int {
            while true {
                var delimiter: Int? = 0
                let parseResult = framer.parseInput(minimumIncompleteLength: 1, maximumLength: 65535) { buf, _ in
                    delimiter = buf?.firstIndex(of: 0)
                    return 0
                }
                guard
                    parseResult,
                    let delimiter = delimiter
                else {
                    return 0
                }
                let didDeliver = framer.deliverInputNoCopy(length: delimiter, message: .init(definition: Self.definition), isComplete: true)
                guard didDeliver else {
                    return 0
                }
                let _ = framer.parseInput(minimumIncompleteLength: 1, maximumLength: 65535) { _, _ in
                    return 1
                }
            }
        }
        
        func handleOutput(framer: NWProtocolFramer.Instance, message: NWProtocolFramer.Message, messageLength: Int, isComplete: Bool) {
            try! framer.writeOutputNoCopy(length: messageLength)
            framer.writeOutput(data: Data([0]))
        }
    }
    var conn: NWConnection
    
    init(endpoint: NWEndpoint) async throws {
        let params = NWParameters(tls: nil, tcp: .init())
        params.defaultProtocolStack.applicationProtocols.insert(NWProtocolFramer.Options(definition: MsgFramerImpl.definition), at: 0)
        
        conn = NWConnection(to: endpoint, using: params)
        conn.start(queue: .main)
        let _ = await withCheckedContinuation { cont in
            conn.stateUpdateHandler = { state in
                if case .ready = state {
                    cont.resume()
                }
            }
        };
    }
    
    private static let encoder = JSONEncoder();
    func send<T: Encodable>(_ val: T) throws {
        let json = try Connection.encoder.encode(val)
        conn.send(content: json, completion: .idempotent)
    }
    
    private static let decoder = JSONDecoder();
    func receive<T: Decodable>() async throws -> T {
        return try await withCheckedThrowingContinuation { cont in
            conn.receiveMessage { data, ctx, isComplete, err in
                assert(isComplete);
                guard let data = data else { cont.resume(throwing: Error.emptyMessage); return }
                cont.resume(with: Result { try Connection.decoder.decode(T.self, from: data) })
            }
        }
    }
    enum Error: Swift.Error {
        case emptyMessage
    }
}


class Repository: ObservableObject {
    private var conn: Connection
    @Published private(set) var accounts: [Account]
    init(endpoint: NWEndpoint) async throws {
        conn = try await Connection(endpoint: endpoint)
        accounts = try await conn.receive()
    }
    
    @MainActor
    func run(command: Command) async throws {
        try conn.send(Message.command(command: command))
        accounts = try await conn.receive()
    }
    
    func transactions(forAccount account: Id<Account>) async throws -> [Transaction] {
        try conn.send(Message.transactions(account: account))
        return try await conn.receive()
    }
    
    func disconnect() {
        conn.conn.cancel()
    }
    
    subscript(_ id: Id<Account>) -> Account? { accounts.first { $0.id == id }}
}
