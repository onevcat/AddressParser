//
//  AddressParser.swift
//  AddressParser
//
//  Created by Wei Wang on 2017/01/01.
//
//  Copyright (c) 2017 Wei Wang <onevcat@gmail.com>
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

import Foundation

#if os(Linux)
  #if swift(>=3.1)
  typealias Regex = NSRegularExpression
  #else
  typealias Regex = RegularExpression
  #endif
#else
typealias Regex = NSRegularExpression
#endif

public struct Address {
    public let name: String
    public let entry: Entry
    
    public init(name: String, entry: Entry) {
        self.name = name
        self.entry = entry
    }
}

extension Address: Equatable {
    public static func ==(lhs: Address, rhs: Address) -> Bool {
        return lhs.name == rhs.name && lhs.entry == rhs.entry
    }
}

public indirect enum Entry {
    case mail(String)
    case group([Address])
}

extension Entry: Equatable {
    public static func ==(lhs: Entry, rhs: Entry) -> Bool {
        switch (lhs, rhs) {
        case (.mail(let address1), .mail(let address2)): return address1 == address2
        case (.group(let addresses1), .group(let addresses2)): return addresses1 == addresses2
        default: return false
        }
    }
}

public struct AddressParser {
    
    enum Node {
        case op(String)
        case text(String)
    }
    
    private enum ParsingState: Int {
        case address
        case comment
        case group
        case text
    }

    public static func parse(_ text: String) -> [Address] {

        var address = [Node]()
        var addresses = [[Node]]()
        
        let nodes = Tokenizer(text: text).tokenize()
        nodes.forEach { (node) in
            if case .op(let value) = node, value == "," || value == ";" {
                if !address.isEmpty {
                    addresses.append(address)
                }
                address = []
            } else {
                address.append(node)
            }
        }
        
        if !address.isEmpty {
            addresses.append(address)
        }
        
        return addresses.flatMap(parseAddress)
    }
    
    static func parseAddress(address: [Node]) -> Address? {
        
        var parsing: [ParsingState: [String]] = [
            .address: [],
            .comment: [],
            .group: [],
            .text: []
        ]
        
        func parsingIsEmpty(_ state: ParsingState) -> Bool {
            return parsing[state]!.isEmpty
        }
        
        var state: ParsingState = .text
        var isGroup = false
        
        for node in address {
            if case .op(let op) = node {
                switch op {
                case "<":
                    state = .address
                case "(":
                    state = .comment
                case ":":
                    state = .group
                    isGroup = true
                default:
                    state = .text
                }
            } else if case .text(var value) = node {
                if state == .address {
                    value = value.truncateUnexpectedLessThanOp()
                }
                parsing[state]!.append(value)
            }
        }
        
        // If there is no text but a comment, use comment for text instead.
        if parsingIsEmpty(.text) && !parsingIsEmpty(.comment) {
            parsing[.text] = parsing[.comment]
            parsing[.comment] = []
        }
        
        if isGroup {
            // http://tools.ietf.org/html/rfc2822#appendix-A.1.3
            let name = parsing[.text]!.joined(separator: " ")
            let group = parsingIsEmpty(.group) ? [] : parse(parsing[.group]!.joined(separator: ","))
            return Address(name: name, entry: .group(group))
        } else {
            // No address found but there is text. Try to find an address from text.
            if parsingIsEmpty(.address) && !parsingIsEmpty(.text) {
                for text in parsing[.text]!.reversed() {
                    if text.isEmail {
                        let found = parsing[.text]!.removeLastMatch(text)!
                        parsing[.address]!.append(found)
                        break
                    }
                }
            }
            
            // Did not find an address in text. Try again with a looser condition.
            if parsingIsEmpty(.address) {
                var textHolder = [String]()
                for text in parsing[.text]!.reversed() {
                    if parsingIsEmpty(.address) {
                        let result = text.replacingMatch(regex: .looserMailRegex, with: "")
                        textHolder.append(result.afterReplacing)
                        if let matched = result.matched {
                            parsing[.address] = [matched.trimmingCharacters(in: .whitespaces)]
                        }
                    } else {
                        textHolder.append(text)
                    }
                }
                parsing[.text] = textHolder.reversed()
            }
            
            // If there is still no text but a comment, use comment for text instead.
            if parsingIsEmpty(.text) && !parsingIsEmpty(.comment) {
                parsing[.text] = parsing[.comment]
                parsing[.comment] = []
            }
            
            if parsing[.address]!.count > 1 {
                let keepAddress = parsing[.address]!.removeFirst()
                parsing[.text]?.append(contentsOf: parsing[.address]!)
                parsing[.address] = [keepAddress]
            }
            
            let tempText = parsing[.text]!.joined(separator: " ").nilOnEmpty
            
            // Remove single/douch quote mark in addresses
            let tempAddress = parsing[.address]!.joined(separator: " ").trimmingQuote.nilOnEmpty
            
            if address.isEmpty && isGroup {
                return nil
            } else {
                
                var address = tempAddress ?? tempText ?? ""
                var name = tempText ?? tempAddress ?? ""
                if address == name {
                    if address.contains("@") {
                        name = ""
                    } else {
                        address = ""
                    }
                }
            
                return Address(name: name, entry: .mail(address))
            }
        }
    }
    
    class Tokenizer {
        
        let operators: [Character: Character?] =
            ["\"": "\"", "(": ")", "<": ">",
             ",": nil, ":": ";", ";": nil]
        
        let text: String
        var currentOp: Character?
        var expectingOp: Character?
        var escaped = false
        
        var currentNode: Node?
        var list = [Node]()
        
        init(text: String) {
            self.text = text
        }
        
        func tokenize() -> [Node] {
            text.characters.forEach(check)
            appendCurrentNode()
            
            return list.filter { (node) -> Bool in
                let value: String
                switch node {
                case .op(let op): value = op
                case .text(let text): value = text
                }
                return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
        
        func check(char: Character) {
            if (operators.keys.contains(char) || char == "\\") && escaped {
                escaped = false
            } else if char == expectingOp {
                appendCurrentNode()
                list.append(.op(String(char)))
                expectingOp = nil
                escaped = false
                return
            } else if expectingOp == nil && operators.keys.contains(char) {
                appendCurrentNode()
                list.append(.op(String(char)))
                expectingOp = operators[char]!
                escaped = false
                return
            }
            
            
            
            if !escaped && char == "\\" {
                escaped = true
                return
            }
            
            if currentNode == nil {
                currentNode = .text("")
            }
            
            if case .text(var currentText) = currentNode! {
                if escaped && char != "\\" {
                    currentText.append("\\")
                }
                currentText.append(char)
                currentNode = .text(currentText)
                escaped = false
            }
        }
        
        func appendCurrentNode() {
            if let currentNode = currentNode {
                switch currentNode {
                case .op(let value):
                    list.append(.op(value.trimmingCharacters(in: .whitespacesAndNewlines)))
                case .text(let value):
                    list.append(.text(value.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }
            currentNode = nil
        }
    }
}

extension Regex {
    static let lessThanOpRegex = try! Regex(pattern: "^[^<]*<\\s*", options: [])
    static let emailRegex = try! Regex(pattern: "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}", options: [])
    static let quoteRegex = try! Regex(pattern: "^(\"|\'){1}.+@.+(\"|\'){1}$", options: [])
    static let looserMailRegex = try! Regex(pattern: "\\s*\\b[^@\\s]+@[^\\s]+\\b\\s*", options: [])
}

extension String {
    
    func truncateUnexpectedLessThanOp() -> String {
        let range = NSMakeRange(0, utf16.count)
        return Regex.lessThanOpRegex.stringByReplacingMatches(in: self, options: [], range: range, withTemplate: "")
    }
    
    var isEmail: Bool {
        let range = NSMakeRange(0, utf16.count)
        return !Regex.emailRegex.matches(in: self, options: [], range: range).isEmpty
    }
    
    var trimmingQuote: String {
        let range = NSMakeRange(0, utf16.count)
        let result = Regex.quoteRegex.matches(in: self, options: [], range: range)
        
        if !result.isEmpty {
            let r = NSMakeRange(1, utf16.count - 2)
            return NSString(string: self).substring(with: r)
        } else {
            return self
        }
    }
    
    func replacingMatch(regex: Regex, with replace: String) -> (afterReplacing: String, matched: String?) {
        let range = NSMakeRange(0, utf16.count)
        let matches = regex.matches(in: self, options: [], range: range)
        
        guard let firstMatch = matches.first else {
            return (self, nil)
        }
        
        let matched = NSString(string: self).substring(with: firstMatch.range)
        let afterReplacing = NSString(string: self).replacingCharacters(in: firstMatch.range, with: replace)
        
        return (afterReplacing, matched)
    }
    
    var nilOnEmpty: String? {
        return isEmpty ? nil : self
    }
}

extension Array where Element: Equatable {
    mutating func removeLastMatch(_ item: Element) -> Element? {
        guard let index = Array(reversed()).index(of: item) else {
            return nil
        }
        return remove(at: count - 1 - index)
    }
}
