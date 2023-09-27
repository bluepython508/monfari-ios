//
//  Repository.swift
//  Monfari
//
//  Created by Ben on 03/09/2023.
//

import Foundation
import Alamofire

extension DataRequest {
    func decoded<T: Decodable>(as type: T.Type = T.self) async throws -> T {
        return try await withCheckedThrowingContinuation { resume in responseDecodable(of: type, completionHandler: { resume.resume(with: $0.result) })}
    }
}

class Repository: ObservableObject {
    private var sess: Session
    private let baseUrl: URL
    @Published private(set) var accounts: [Account]
    
    private func get<T: Decodable>(at path: String) async throws -> T {
        try await sess.request(baseUrl.appending(path: path), method: .get).decoded()
    }
    
    private func post<T: Decodable, U: Encodable>(at path: String, value: U) async throws -> T {
        try await sess.request(baseUrl.appending(path: path), method: .post, parameters: value, encoder: JSONParameterEncoder.default).decoded()
    }

    init(baseUrl: URL) async throws {
        sess = Session(configuration: {
            let c = URLSessionConfiguration.default
            c.requestCachePolicy = .reloadIgnoringLocalCacheData
            return c
        }())
        self.baseUrl = baseUrl
        accounts = []
        accounts = try await get(at: "")
    }

    @MainActor
    func run(command: Command) async throws {
        accounts = try await post(at: "", value: command)
    }
    
    func transactions(forAccount account: Id<Account>) async throws -> [Transaction] {
        try await get(at: "transactions/\(account.id)")
    }

    subscript(_ id: Id<Account>) -> Account? { accounts.first { $0.id == id }}
}
