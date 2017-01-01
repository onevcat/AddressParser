# AddressParser

This framework is a component of [Hedwig](https://github.com/onevcat/Hedwig), 
which is a cross platform Swift SMTP email client framework.

When sending an email, you need to specify the receipt address. The address 
field could be one of these forms below:

* Single address: `onev@onevcat.com`
* Formatted address with name: `Wei Wang <onev@onevcat.com>`
* A list of addresses: `onev@onevcat.com, foo@bar.com`
* A group: `My Group: onev@onevcat.com, foo@bar.com;`

and even more and mixed...

If you need a complete solution of sending mails through SMTP by Swift, see 
[Hedwig](https://github.com/onevcat/Hedwig) instead.

## Installation

Add the url of this repo to your `Package.swift`:

```swift
import PackageDescription

let package = Package(
    name: "YourAwesomeSoftware",
    dependencies: [
        .Package(url: "https://github.com/onevcat/AddressParser.git", 
                 majorVersion: 1)
    ]
)
```

Then run `swift build` whenever you get prepared.

You could know more information on how to use Swift Package Manager in Apple's 
[official page](https://swift.org/package-manager/).

## Usage

Use `AddressParser.parse` to parse an email string field to an array of `Address`. 
An `Address` struct contains the name of that address and an entry to indicate 
whether this is a mail address or a group.

```swift
import AddressParser

let _ = AddressParser.parse("onev@onevcat.com")
// [Address(name: "", entry: .mail("onev@onevcat.com"))]

let _ = AddressParser.parse("Wei Wang <onev@onevcat.com>")
// [Address(name: "Wei Wang", entry: .mail("onev@onevcat.com"))]

let _ = AddressParser.parse("onev@onevcat.com, foo@bar.com")
// [
//     Address(name: "", entry: .mail("onev@onevcat.com"))
//     Address(name: "", entry: .mail("foo@bar.com"))
// ]

let _ = AddressParser.parse("My Group: onev@onevcat.com, foo@bar.com;")
// [
//     Address(name: "MyGroup", entry: .group([
//         Address(name: "", entry: .mail("onev@onevcat.com")),
//         Address(name: "", entry: .mail("foo@bar.com")),
//     ]))
// ]
```

## License

MIT. See the LICENSE file.

