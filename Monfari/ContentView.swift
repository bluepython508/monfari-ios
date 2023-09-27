//
//  ContentView.swift
//  Monfari
//
//  Created by Ben on 02/09/2023.
//

import SwiftUI
import Network

struct ContentView: View {
    @State var repo: Repository?
    func connect(to url: URL) {
        Task {
            let repo = try await Repository(baseUrl: url)
            DispatchQueue.main.async {
                self.repo = repo
            }
        }
    }
    func disconnect() {
        repo = nil
    }
    var body: some View {
        if let repo = repo {
            NavigationStack {
                RepoView()
                    .toolbar {
                        ToolbarItem(placement: .destructiveAction) {
                            Button("Disconnect", action: disconnect)
                        }
                    }
                    .navigationTitle("Accounts")
            }.environmentObject(repo)

        } else {
            ConnectingView(connect: connect)
        }
    }
}

struct ConnectingView: View {
    @State var url: String = "http://10.10.2.6:9000"
    @State var connecting: Bool = false
    let connect: (URL) -> Void
    
    var body: some View {
        if connecting {
            ProgressView().progressViewStyle(.circular)
        } else {
            VStack {
                Spacer()
                Form {
                    TextField("Repo", text: $url)
                    Button("Connect") { connecting = true; connect(URL(string: url)!) }
                }
            }
        }
    }
}

struct RepoView: View {
    @EnvironmentObject var repo: Repository
    @State var transactionType: TransactionCreateView.Inner? = nil
    
    func transaction(_ type: TransactionCreateView.Inner) -> () -> Void {
        {
            transactionType = type
        }
    }
    
    var body: some View {
        VStack {
            List(repo.accounts.filter { $0.enabled }.sorted(by: { $0.typ != $1.typ ? $0.typ != .physical : $0.id < $1.id }), id: \.id) { acc in
                NavigationLink(value: acc.id) {
                    VStack {
                        HStack {
                            Text(acc.name)
                            Spacer()
                            Text(acc.typ.rawValue).foregroundColor(.gray).fontWeight(.light)
                        }
                        HStack {
                            ForEach(acc.current.filter { $0.value.amount > 0 }.sorted(on: \.key), id: \.key) {
                                Spacer()
                                Text($0.value.formatted)
                            }
                            Spacer()
                        }
                    }
                }
            }.navigationDestination(for: Id<Account>.self) { id in
                AccountDetailView(account: repo[id]!)
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
                TransactionCreateView(inner: type, dismiss: { transactionType = nil })
            }
        }
    }
}

struct AccountDetailView: View {
    @EnvironmentObject var repo: Repository
    let account: Account
    @State var transactions: [Transaction] = []
    
    var body: some View {
        VStack {
            HStack {
                ForEach(account.current.filter { $0.value.amount > 0 }.sorted(on: \.key), id: \.key) {
                    Spacer()
                    Text($0.value.formatted)
                }
                Spacer()
            }
            List(transactions.sorted(on: \.id).reversed()) { transaction in
                VStack {
                    Text(transaction.description(forAccount: account.id, inRepo: repo))
                    Text(transaction.notes).foregroundColor(.gray).fontWeight(.light)
                }
            }.task {
                let transactions = try! await repo.transactions(forAccount: account.id);
                DispatchQueue.main.async {
                    self.transactions = transactions
                }
            }
        }.navigationTitle(account.name)
    }
}

struct TransactionCreateView: View {
    @EnvironmentObject var repo: Repository

    let id: Id<Transaction> = Id.generate()
    @State var amount: Amount?
    @State var notes: String = ""
    let inner: Inner
    @State var typ: Transaction.Typ? = nil
    @State var adding: Bool = false
    @FocusState var focused: FocusedField?

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
            DispatchQueue.main.async {
                dismiss()
            }
        }
    }
    
    enum FocusedField {
        case amount, source, destination, newAmount, notes
    }

    var body: some View {
        Form {
            AmountField(out: $amount, focused: $focused, focusTag: .amount)
            switch inner {
            case .received: Received(typ: $typ, focused: $focused)
            case .paid: Paid(typ: $typ, focused: $focused)
            case .move: Move(typ: $typ)
            case .convert: Convert(typ: $typ, focused: $focused)
            }
            Section("Notes") {
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...)
                    .focused($focused, equals: .notes)
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
        .task { DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focused = .amount }}
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
        var focused: FocusState<FocusedField?>.Binding

        var body: some View {
            Section {
                TextField("Source", text: $src).focused(focused, equals: .source).onChange(of: src) { _ in updateTyp() }
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
        var focused: FocusState<FocusedField?>.Binding

        var body: some View {
            Section {
                TextField("Destination", text: $dst).focused(focused, equals: .destination).onChange(of: dst) { _ in updateTyp() }
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
            Section {
                AccountPicker(description: "Source", type: type, id: $src).onChange(of: src) { _ in updateTyp() }
                AccountPicker(description: "Destination", type: type, id: $dst).onChange(of: dst) { _ in updateTyp() }
            }
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
        
        var focused: FocusState<FocusedField?>.Binding

        var body: some View {
            Section("Convert Into") {
                AmountField(out: $newAmount, focused: focused, focusTag: .newAmount).onChange(of: newAmount) { _ in updateTyp() }
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
                ForEach(repo.accounts.filter { ($0.typ == type || type == nil) && $0.enabled }, id: \.id) { acc in
                    Text(acc.name).tag(acc.id as Id<Account>?)
                }
            }.pickerStyle(.navigationLink)
        }
    }
    
    struct AmountField: View {
        @Binding var out: Amount?
        func updateAmount() {
            guard amount > 0 else { out = nil; return }
            out = Amount(Int((amount * 100).rounded()), currency)
        }
        @State var amount: Double = 0
        @State var currency: Currency = Currency.EUR
        var focused: FocusState<FocusedField?>.Binding
        let focusTag: FocusedField
        
        let amountFormatter = {
            var fmt = NumberFormatter()
            fmt.maximumFractionDigits = 2
            return fmt
        }()

        var body: some View {
            HStack {
                TextField("", value: $amount, formatter: amountFormatter)
                    .focused(focused, equals: focusTag)
                    .frame(maxWidth: .infinity)
                    .keyboardType(.decimalPad)
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
