//
//  Types.swift
//  Monfari
//
//  Created by Ben on 02/09/2023.
//

import Foundation

struct Currency: Codable, Hashable, Comparable {
    static func < (lhs: Currency, rhs: Currency) -> Bool {
        lhs.name < rhs.name
    }
    
    let name: String
    init?(stringValue name: String) {
        // wholeMatch can only error if given an invalid transformation?
        if try! /[A-Z]{3}/.wholeMatch(in: name) == nil { return nil };
        self.name = name
    }
    
    func encode(to encoder: Encoder) throws {
        try name.encode(to: encoder)
    }

    init(from decoder: Decoder) throws {
        guard let initialized = Self(stringValue: try String(from: decoder)) else {
            throw Error.invalidName
        }
        self = initialized
    }
    
    enum Error: Swift.Error {
        case invalidName
    }
    
    static let EUR = Self(stringValue: "EUR")!
    static let GBP = Self(stringValue: "GBP")!
    static let USD = Self(stringValue: "USD")!
}

struct Amount: Codable, CustomStringConvertible, Equatable {
    let currency: Currency
    let amount: Int
    
    init?(_ text: String) {
        guard let match = try! /(?'whole'\d+)(.(?'decimal'\d{2}))? (?'currency'[A-Z]{3})/.wholeMatch(in: text) else { return nil }
        currency = Currency(stringValue: String(match.output.currency))!
        amount = (Int(match.output.whole)! * 100) + Int(match.output.decimal ?? "0")!
    }
    
    init(_ amount: Int, _ currency: Currency) {
        self.currency = currency
        self.amount = amount
    }

    var description: String {
        let (whole, decimal) = amount.quotientAndRemainder(dividingBy: 100)
        return "\(whole).\(String(format: "%02d", decimal)) \(currency.name)"
    }
    
    var formatted: String {
        let (whole, decimal) = amount.quotientAndRemainder(dividingBy: 100)
        let formatter = NumberFormatter()
        formatter.usesGroupingSeparator = true
        formatter.groupingSize = 3
        formatter.groupingSeparator = " "
        return "\(formatter.string(from: NSNumber(value: whole))!).\(String(format: "%02d", decimal)) \(currency.name)"
    }
    
    func encode(to encoder: Encoder) throws {
        try self.description.encode(to: encoder)
    }

    init(from decoder: Decoder) throws {
        guard let initialized = Self(try String(from: decoder)) else {
            throw Error.invalidFormat
        }
        self = initialized
    }
    
    enum Error: Swift.Error {
        case invalidFormat
    }
}

struct Account: Codable {
    enum Typ: String, Codable {
        case physical = "Physical", virtual = "Virtual"
    }
    let id: Id<Self>
    let name: String
    let notes: String
    let typ: Typ
    let enabled: Bool
    let current: [Currency: Amount]
    
    enum CodingKeys: CodingKey {
        case id
        case name
        case notes
        case typ
        case enabled
        case current
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Account.CodingKeys.self)
        try container.encode(self.id, forKey: Account.CodingKeys.id)
        try container.encode(self.name, forKey: Account.CodingKeys.name)
        try container.encode(self.notes, forKey: Account.CodingKeys.notes)
        try container.encode(self.typ, forKey: Account.CodingKeys.typ)
        try container.encode(self.enabled, forKey: Account.CodingKeys.enabled)
        try container.encode(self.current, forKey: Account.CodingKeys.current)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Id<Account>.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.notes = try container.decode(String.self, forKey: .notes)
        self.typ = try container.decode(Account.Typ.self, forKey: .typ)
        self.enabled = try container.decode(Bool.self, forKey: .enabled)
        let current = try container.decode([String: Amount].self, forKey: .current)
        self.current = try Dictionary(uniqueKeysWithValues: current.map { k, v in
            guard let currency = Currency(stringValue: k) else { throw Error.invalidCurrency }
            return (key: currency, value: v)
        });
    }

    enum Error: Swift.Error {
        case invalidCurrency
    }
}

struct Transaction: Codable, Identifiable {
    let id: Id<Self>
    let notes: String
    let amount: Amount
    let type: Typ
    
    enum Typ {
        case received(src: String, dst: Id<Account>, dstVirt: Id<Account>)
        case paid(dst: String, src: Id<Account>, srcVirt: Id<Account>)
        case movePhys(src: Id<Account>, dst: Id<Account>)
        case moveVirt(src: Id<Account>, dst: Id<Account>)
        case convert(newAmount: Amount, acc: Id<Account>, accVirt: Id<Account>)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self);
        try container.encode(id, forKey: .id)
        try container.encode(notes, forKey: .notes)
        try container.encode(amount, forKey: .amount)
        switch type {
        case .received(let src, let dst, let dstVirt):
            try container.encode("Received", forKey: .type)
            try container.encode(src, forKey: .src)
            try container.encode(dst, forKey: .dst)
            try container.encode(dstVirt, forKey: .dstVirt)
        case .paid(let dst, let src, let srcVirt):
            try container.encode("Paid", forKey: .type)
            try container.encode(dst, forKey: .dst)
            try container.encode(src, forKey: .src)
            try container.encode(srcVirt, forKey: .srcVirt)
        case .movePhys(let src, let dst):
            try container.encode("MovePhys", forKey: .type)
            try container.encode(src, forKey: .src)
            try container.encode(dst, forKey: .dst)
        case .moveVirt(let src, let dst):
            try container.encode("MoveVirt", forKey: .type)
            try container.encode(src, forKey: .src)
            try container.encode(dst, forKey: .dst)
        case .convert(let newAmount, let acc, let accVirt):
            try container.encode("Convert", forKey: .type)
            try container.encode(newAmount, forKey: .newAmount)
            try container.encode(acc, forKey: .acc)
            try container.encode(accVirt, forKey: .accVirt)
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Id<Self>.self, forKey: .id)
        notes = try container.decode(String.self, forKey: .notes)
        amount = try container.decode(Amount.self, forKey: .amount)
        switch try container.decode(String.self, forKey: .type) {
        case "Received":
            type = .received(src: try container.decode(String.self, forKey: .src), dst: try container.decode(Id<Account>.self, forKey: .dst), dstVirt: try container.decode(Id<Account>.self, forKey: .dstVirt))
        case "Paid":
            type = .paid(dst: try container.decode(String.self, forKey: .dst), src: try container.decode(Id<Account>.self, forKey: .src), srcVirt: try container.decode(Id<Account>.self, forKey: .srcVirt))
        case "MovePhys":
            type = .movePhys(src: try container.decode(Id<Account>.self, forKey: .src), dst: try container.decode(Id<Account>.self, forKey: .dst))
        case "MoveVirt":
            type = .moveVirt(src: try container.decode(Id<Account>.self, forKey: .src), dst: try container.decode(Id<Account>.self, forKey: .dst))
        case "Convert":
            type = .convert(newAmount: try container.decode(Amount.self, forKey: .newAmount), acc: try container.decode(Id<Account>.self, forKey: .acc), accVirt: try container.decode(Id<Account>.self, forKey: .accVirt))
        default: throw Error.unknownType
        }
    }

    init(id: Id<Self>, notes: String, amount: Amount, type: Typ) {
        self.id = id
        self.notes = notes
        self.amount = amount
        self.type = type
    }
    
    enum Error: Swift.Error {
        case unknownType
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case notes
        case amount
        case type
        case src
        case dst
        case srcVirt = "src_virt"
        case dstVirt = "dst_virt"
        case newAmount = "new_amount"
        case acc
        case accVirt = "acc_virt"
    }
    
    func description(forAccount acc: Id<Account>, inRepo repo: Repository) -> String {
        let desc: String;
        switch type {
        case .received(let src, dst: _, dstVirt: _): desc = "received from \(src)"
        case .paid(let dst, src: _, srcVirt: _): desc = "paid to \(dst)"
        case .movePhys(let src, let dst), .moveVirt(let src, let dst):
            let (dir, other) = src == acc ? ("to", dst) : ("from", src)
            desc = "moved \(dir) \(repo[other]?.name ?? "<Unknown Account>")"
        case .convert(let newAmount, acc: _, accVirt: _):
            desc = "converted to \(newAmount.formatted)"
        }
        return "\(amount.formatted) \(desc)"
    }
}

enum Command: Encodable {
    case addTransaction(Transaction)
    case createAccount(Account)
    
    enum CodingKeys: String, CodingKey {
        case addTransaction = "AddTransaction"
        case createAccount = "CreateAccount"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .addTransaction(let transaction):
            try container.encode(transaction, forKey: .addTransaction)
        case .createAccount(let account):
            try container.encode(account, forKey: .createAccount)
        }
    }
}

enum Message: Encodable {
    case command(command: Command)
    case transactions(account: Id<Account>)
    
    enum CodingKeys: String, CodingKey {
        case command = "Command";
        case transactions = "Transactions";
    }
}
