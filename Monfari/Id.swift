//
//  Proquints.swift
//  Monfari
//
//  Created by Ben on 02/09/2023.
//

import Foundation
import ULID

extension Data {
    fileprivate func toUint16Array() -> [UInt16] {
        self.withUnsafeBytes {
            Array<UInt16>($0.assumingMemoryBound(to: UInt16.self)).map { $0.byteSwapped }
        }
    }
}

fileprivate func proquintEncode(_ bytes: Data) -> String {
    bytes.toUint16Array().map(proquintEncode).joined(separator: "-")
}

fileprivate let vowels = ["a", "i", "o", "u"];
fileprivate let consonants = ["b", "d", "f", "g", "h", "j", "k", "l", "m", "n", "p", "r", "s", "t", "v", "z"];

fileprivate func proquintEncode(_ quint: UInt16) -> String {
    [
        consonant(quint >> 12),
        vowel(quint >> 10),
        consonant(quint >> 6),
        vowel(quint >> 4),
        consonant(quint >> 0)
    ].joined(separator: "")
}


fileprivate func vowel(_ src: UInt16) -> String {
    vowels[Int(src & 0b11)]
}
fileprivate func consonant(_ src: UInt16) -> String {
    consonants[Int(src & 0b1111)]
}

struct Id<T>: Codable, Equatable, Hashable, Comparable {
    static func < (lhs: Id<T>, rhs: Id<T>) -> Bool {
        lhs.id < rhs.id
    }
    
    let id: String;
    
    init(_ id: String) {
        self.id = id
    }
    
    static func generate() -> Id<T> {
        Id(proquintEncode(ULID().ulidData))
    }

    func encode(to encoder: Encoder) throws {
        try id.encode(to: encoder)
    }

    init(from decoder: Decoder) throws {
        id = try String(from: decoder)
    }
}
