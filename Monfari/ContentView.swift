//
//  ContentView.swift
//  Monfari
//
//  Created by Ben on 02/09/2023.
//

import SwiftUI

struct ContentView: View {
    @State var repo: Repository?
    @State var connecting: Bool = false
    func connect() {
        Task {
            connecting = true;
            repo = try await Repository(endpoint: .hostPort(host: "nomos.local", port: 9000))
            connecting = false;
        }
    }
    func disconnect() {
        Task {
            repo?.disconnect()
            repo = nil
        }
    }
    var body: some View {
        if let repo = repo {
            NavigationView {
                RepoView()
                    .environmentObject(repo)
                    .toolbar {
                        ToolbarItem(placement: .destructiveAction) {
                            Button("Disconnect", action: disconnect)
                        }
                    }
                    .navigationTitle("Accounts")
            }
        } else if !connecting {
            Button("Connect", action: connect)
        } else {
            ProgressView().progressViewStyle(.circular)
        }
    }
}

struct RepoView: View {
    @EnvironmentObject var repo: Repository
    @State var transactionType: TransactionView.Inner? = nil
    
    func transaction(_ type: TransactionView.Inner) -> () -> Void {
        {
            transactionType = type
        }
    }
    
    var body: some View {
        VStack {
            List(repo.accounts, id: \.id) { acc in
                VStack {
                    HStack {
                        Text(acc.name)
                        Spacer()
                        Text(acc.typ.rawValue).foregroundColor(.gray).fontWeight(.light)
                    }
                    HStack {
                        ForEach(acc.current.sorted(on: \.key), id: \.key) {
                            Text($0.value.description)
                        }
                    }
                }
            }
            Spacer()
            HStack {
                Button(action: transaction(.received)) {
                    Label("Received", systemImage: "arrow.down")
                }
                Button(action: transaction(.paid)) {
                    Label("Paid", systemImage: "arrow.up")
                }
            }.buttonStyle(.bordered)
            HStack {
                Button(action: transaction(.move)) {
                    Label("Move", systemImage: "arrow.up.arrow.down")
                }
                Button(action: transaction(.convert)) {
                    Label("Convert", systemImage: "arrow.counterclockwise")
                }
            }.buttonStyle(.bordered)
        }.popover(item: $transactionType) { type in
            NavigationView {
                TransactionView(inner: type, dismiss: { transactionType = nil })
            }
        }
    }
}

struct TransactionView: View {
    @EnvironmentObject var repo: Repository

    let id: Id<Transaction> = Id.generate()
    @State var amount: Amount?
    @State var notes: String = ""
    let inner: Inner
    @State var typ: Transaction.Typ? = nil
    @State var adding: Bool = false

    let dismiss: () -> Void

    enum Inner: Hashable, Identifiable {
        case received
        case paid
        case move
        case convert

        var id: Self { self }
    }
    
    var isValid: Bool { typ != nil && amount != nil }
    func addTransaction() {
        guard
            let amount = amount,
            let typ = typ
        else { return }
        Task {
            adding = true
            try await repo.run(command: .addTransaction(Transaction(id: id, notes: notes, amount: amount, type: typ)))
            dismiss()
        }
    }

    var body: some View {
        Form {
            AmountField(out: $amount)
            switch inner {
            case .received: Received(typ: $typ)
            case .paid: Paid(typ: $typ)
            case .move: Move(typ: $typ)
            case .convert: Convert(typ: $typ)
            }
            Section("Notes") {
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...)
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add", action: addTransaction).disabled(!isValid || adding)
            }
        }
        .disabled(adding)
        .overlay {
            if adding { ProgressView() }
        }
        Button("Add", action: addTransaction).disabled(!isValid || adding).buttonStyle(.bordered)
    }
    
    struct Received: View {
        @Binding var typ: Transaction.Typ?
        func updateTyp() {
            guard
                src != "",
                let dst = dst,
                let dstVirt = dstVirt
            else { typ = nil; return }
            typ = .received(src: src, dst: dst, dstVirt: dstVirt)
        }
        @State var src: String = ""
        @State var dst: Id<Account>? = nil
        @State var dstVirt: Id<Account>? = nil

        var body: some View {
            Section {
                TextField("Source", text: $src).onChange(of: src) { _ in updateTyp() }
                AccountPicker(description: "Destination", type: .physical, id: $dst).onChange(of: dst) { _ in updateTyp() }
                AccountPicker(description: "Destination", type: .virtual, id: $dstVirt).onChange(of: dstVirt) { _ in updateTyp() }
            }
        }
    }
    
    struct Paid: View {
        @Binding var typ: Transaction.Typ?
        func updateTyp() {
            guard
                dst != "",
                let src = src,
                let srcVirt = srcVirt
            else { typ = nil; return }
            typ = .paid(dst: dst, src: src, srcVirt: srcVirt)
        }
        @State var dst: String = ""
        @State var src: Id<Account>? = nil
        @State var srcVirt: Id<Account>? = nil

        var body: some View {
            Section {
                TextField("Destination", text: $dst).onChange(of: dst) { _ in updateTyp() }
                AccountPicker(description: "Source", type: .physical, id: $src).onChange(of: src) { _ in updateTyp() }
                AccountPicker(description: "Source", type: .virtual, id: $srcVirt).onChange(of: srcVirt) { _ in updateTyp() }
            }
        }
    }
    
    struct Move: View {
        @EnvironmentObject var repo: Repository
        @Binding var typ: Transaction.Typ?
        func updateTyp() {
            guard
                let src = src,
                let dst = dst,
                let src = repo[src],
                let dst = repo[dst],
                src.typ == dst.typ
            else { typ = nil; return }
            switch src.typ {
            case .physical: typ = .movePhys(src: src.id, dst: dst.id)
            case .virtual: typ = .moveVirt(src: src.id, dst: dst.id)
            }
        }
        
        @State var src: Id<Account>?
        @State var dst: Id<Account>?
        var type: Account.Typ? {
            if let src = src, let src = repo[src] { return src.typ }
            if let dst = dst, let dst = repo[dst] { return dst.typ }
            return nil
        }

        var body: some View {
            AccountPicker(description: "Source", type: type, id: $src).onChange(of: src) { _ in updateTyp() }
            AccountPicker(description: "Destination", type: type, id: $dst).onChange(of: dst) { _ in updateTyp() }
        }
    }
    
    struct Convert: View {
        @Binding var typ: Transaction.Typ?
        func updateTyp() {
            guard
                let acc = acc,
                let accVirt = accVirt,
                let newAmount = newAmount
            else { typ = nil; return }
            typ = .convert(newAmount: newAmount, acc: acc, accVirt: accVirt)
        }
    
        @State var newAmount: Amount?
        @State var acc: Id<Account>?
        @State var accVirt: Id<Account>?
        
        var body: some View {
            Section("Convert Into") {
                AmountField(out: $newAmount).onChange(of: newAmount) { _ in updateTyp() }
            }
            Section {
                AccountPicker(description: "Account", type: .physical, id: $acc).onChange(of: acc) { _ in updateTyp() }
                AccountPicker(description: "Account", type: .virtual, id: $accVirt).onChange(of: acc) { _ in updateTyp() }
            }
        }
    }
    
    struct AccountPicker: View {
        @EnvironmentObject var repo: Repository
        let description: String
        let type: Account.Typ?
        @Binding var id: Id<Account>?
        
        var body: some View {
            Picker(description, selection: $id) {
                Text("").foregroundColor(.gray).tag(nil as Id<Account>?).disabled(true)
                ForEach(repo.accounts.filter { $0.typ == type || type == nil }, id: \.id) { acc in
                    Text(acc.name).tag(acc.id as Id<Account>?)
                }
            }.pickerStyle(.navigationLink)
        }
    }
    
    struct AmountField: View {
        @Binding var out: Amount?
        func updateAmount() {
            guard amount > 0 else { out = nil; return }
            out = Amount(amount, currency)!
        }
        @State var amount: Double = 0
        @State var currency: Currency = Currency.EUR
        
        let amountFormatter = {
            var formatter = NumberFormatter()
            formatter.maximumFractionDigits = 2
            return formatter
        }()
        
        var body: some View {
            HStack {
                TextField("", value: $amount, formatter: amountFormatter)
                    .frame(maxWidth: .infinity)
                    .keyboardType(.numberPad)
                    .onChange(of: amount) { _ in updateAmount() }
                Divider()
                Picker("", selection: $currency) {
                    Text("EUR").tag(Currency.EUR)
                    Text("GBP").tag(Currency.GBP)
                    Text("USD").tag(Currency.USD)
                }.frame(maxWidth: 80).onChange(of: currency) { _ in updateAmount() }
            }
        }
    }
}

extension Collection {
    func sorted<T: Comparable>(on key: (Element) -> T) -> [Element] {
        sorted(by: { key($0) < key($1) })
    }
    
    func sorted<T: Comparable>(on key: KeyPath<Element, T>) -> [Element] {
        sorted(on: { $0[keyPath: key] })
    }
}
