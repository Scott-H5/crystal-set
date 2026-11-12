// asc.swift
//
// TestFlight from the terminal, through the App Store Connect API, so the
// App Store Connect website (which is hard to use with VoiceOver) is only
// needed for the rare thing this doesn't cover.
//
// Run it through asc.sh, which reads the key settings and compiles this file
// the first time:
//
//   ./asc.sh status                      latest builds and their review state
//   ./asc.sh testers                     who is in the external Testers group
//   ./asc.sh add-tester EMAIL [FIRST LAST]
//   ./asc.sh remove-tester EMAIL
//   ./asc.sh link                        show the public link, if it's on
//   ./asc.sh link on [LIMIT]             turn the public link on (LIMIT testers)
//   ./asc.sh link off
//   ./asc.sh submit ios|mac              newest build: add What to Test notes
//                                        (testflight-notes.txt), add it to the
//                                        Testers group, send it to Beta App
//                                        Review. Asks before sending.
//
// How the API works, in brief: every request carries a "token" that proves
// it comes from you. The token is a short JSON note ("this is key B3329MRBHS
// of team 2b44…, valid for 10 minutes"), signed with the private key in the
// .p8 file. Apple checks the signature with its copy of the matching public
// key. The private key never leaves this Mac. The standard for such tokens
// is JWT, and the signature type is ES256 (CryptoKit's P256).
//
// Requests and replies are JSON. Apple's API documentation lists every one:
// https://developer.apple.com/documentation/appstoreconnectapi

import CryptoKit
import Foundation

// MARK: - Settings (from ~/.appstoreconnect/crystal-set.env, via asc.sh)

let env = ProcessInfo.processInfo.environment
func setting(_ name: String) -> String {
    guard let value = env[name], !value.isEmpty else {
        fail("\(name) isn't set. Run this through asc.sh, which reads ~/.appstoreconnect/crystal-set.env.")
    }
    return value
}
let keyID = setting("ASC_KEY_ID")
let issuerID = setting("ASC_ISSUER_ID")
let keyPath = setting("ASC_KEY_PATH")
let appID = setting("ASC_APP_ID")
let groupID = setting("ASC_EXTERNAL_GROUP_ID")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

// MARK: - The token

/// base64url: base64 with - and _ instead of + and /, and no = padding.
func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

/// A token valid for 10 minutes (Apple allows at most 20).
func makeToken() -> String {
    guard let pem = try? String(contentsOfFile: keyPath, encoding: .utf8),
          let key = try? P256.Signing.PrivateKey(pemRepresentation: pem) else {
        fail("Couldn't read the API key at \(keyPath).")
    }
    let now = Int(Date().timeIntervalSince1970)
    let header = ["alg": "ES256", "kid": keyID, "typ": "JWT"]
    let claims: [String: Any] = ["iss": issuerID, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"]
    let part1 = base64URL(try! JSONSerialization.data(withJSONObject: header))
    let part2 = base64URL(try! JSONSerialization.data(withJSONObject: claims))
    let signature = try! key.signature(for: Data("\(part1).\(part2)".utf8))
    return "\(part1).\(part2).\(base64URL(signature.rawRepresentation))"
}
let token = makeToken()

// MARK: - Requests

typealias JSON = [String: Any]

/// Sends one request and returns the reply's JSON (empty for "no content").
/// Stops with Apple's own error message if the request fails.
@discardableResult
func api(_ method: String, _ path: String, _ body: JSON? = nil) -> JSON {
    var request = URLRequest(url: URL(string: "https://api.appstoreconnect.apple.com" + path)!)
    request.httpMethod = method
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    if let body {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try! JSONSerialization.data(withJSONObject: body)
    }
    // Wait for the reply. (A command-line tool has nothing else to do meanwhile.)
    var result: (Data?, URLResponse?, Error?)
    let done = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: request) { result = ($0, $1, $2); done.signal() }.resume()
    done.wait()

    if let error = result.2 { fail("Couldn't reach App Store Connect: \(error.localizedDescription)") }
    let status = (result.1 as? HTTPURLResponse)?.statusCode ?? 0
    let json = result.0.flatMap { try? JSONSerialization.jsonObject(with: $0) as? JSON } ?? [:]
    guard (200..<300).contains(status) else {
        // Apple explains failures in an "errors" list; show each one plainly.
        let errors = (json["errors"] as? [JSON] ?? []).map {
            "\($0["title"] ?? "Error"): \($0["detail"] ?? "")"
        }
        fail("App Store Connect said no (HTTP \(status)).\n" + (errors.isEmpty ? "" : errors.joined(separator: "\n")))
    }
    return json
}

func attributes(_ item: JSON) -> JSON { item["attributes"] as? JSON ?? [:] }

/// Turns Apple's code words into plain words.
func plain(_ state: String) -> String {
    [
        "PROCESSING": "still processing",
        "READY_FOR_BETA_SUBMISSION": "ready to submit for review",
        "WAITING_FOR_BETA_REVIEW": "waiting for review",
        "IN_BETA_REVIEW": "in review",
        "BETA_APPROVED": "approved",
        "BETA_REJECTED": "rejected",
        "IN_BETA_TESTING": "being tested",
        "EXPIRED": "expired",
        "MISSING_EXPORT_COMPLIANCE": "waiting for the encryption question",
        "PROCESSING_EXCEPTION": "processing failed",
    ][state] ?? state.lowercased().replacingOccurrences(of: "_", with: " ")
}

// MARK: - Builds

let platforms = [("ios", "IOS", "iPhone"), ("mac", "MAC_OS", "Mac")]

/// The newest builds for one platform, with their external (beta review) state.
func builds(platform: String, limit: Int) -> [(id: String, number: String, processing: String, external: String)] {
    let reply = api("GET", "/v1/builds?filter[app]=\(appID)&filter[preReleaseVersion.platform]=\(platform)"
                    + "&sort=-uploadedDate&limit=\(limit)&include=buildBetaDetail"
                    + "&fields[builds]=version,processingState,buildBetaDetail"
                    + "&fields[buildBetaDetails]=externalBuildState")
    // The beta details come back in a separate "included" list, matched by ID.
    var external: [String: String] = [:]
    for detail in reply["included"] as? [JSON] ?? [] {
        if let id = detail["id"] as? String { external[id] = attributes(detail)["externalBuildState"] as? String }
    }
    return (reply["data"] as? [JSON] ?? []).map { build in
        let detailID = ((build["relationships"] as? JSON)?["buildBetaDetail"] as? JSON)?["data"] as? JSON
        return (build["id"] as? String ?? "",
                attributes(build)["version"] as? String ?? "?",
                attributes(build)["processingState"] as? String ?? "",
                external[detailID?["id"] as? String ?? ""] ?? "")
    }
}

func status() {
    for (_, code, name) in platforms {
        print("\(name) builds (newest first):")
        let list = builds(platform: code, limit: 3)
        if list.isEmpty { print("  none") }
        for build in list {
            let state = build.processing == "VALID" ? plain(build.external) : plain(build.processing)
            print("  \(build.number): \(state)")
        }
    }
}

// MARK: - Testers

func testerList() -> [JSON] {
    api("GET", "/v1/betaGroups/\(groupID)/betaTesters?limit=200&fields[betaTesters]=email,firstName,lastName,state")["data"] as? [JSON] ?? []
}

func showTesters() {
    let list = testerList()
    print(list.isEmpty ? "No testers in the Testers group yet." : "Testers group (\(list.count)):")
    for tester in list {
        let a = attributes(tester)
        let name = [a["firstName"], a["lastName"]].compactMap { $0 as? String }.filter { !$0.isEmpty }.joined(separator: " ")
        let state = (a["state"] as? String).map { " (\($0.lowercased()))" } ?? ""
        print("  \(a["email"] as? String ?? "?")\(name.isEmpty ? "" : ", \(name)")\(state)")
    }
}

func addTester(email: String, first: String, last: String) {
    var attrs: JSON = ["email": email]
    if !first.isEmpty { attrs["firstName"] = first }
    if !last.isEmpty { attrs["lastName"] = last }
    api("POST", "/v1/betaTesters", ["data": [
        "type": "betaTesters",
        "attributes": attrs,
        "relationships": ["betaGroups": ["data": [["type": "betaGroups", "id": groupID]]]],
    ]])
    print("Added \(email) to the Testers group. TestFlight emails them an invitation once a build is approved.")
}

func removeTester(email: String) {
    guard let tester = testerList().first(where: {
        (attributes($0)["email"] as? String)?.lowercased() == email.lowercased()
    }), let id = tester["id"] as? String else { fail("\(email) isn't in the Testers group.") }
    api("DELETE", "/v1/betaGroups/\(groupID)/relationships/betaTesters",
        ["data": [["type": "betaTesters", "id": id]]])
    print("Removed \(email) from the Testers group.")
}

// MARK: - Public link

func link(_ args: [String]) {
    if args.first == "on" || args.first == "off" {
        var attrs: JSON = ["publicLinkEnabled": args.first == "on"]
        if args.first == "on" {
            // An optional cap on how many people can join through the link.
            if let limit = args.dropFirst().first.flatMap(Int.init) {
                attrs["publicLinkLimitEnabled"] = true
                attrs["publicLinkLimit"] = limit
            } else {
                attrs["publicLinkLimitEnabled"] = false
            }
        }
        api("PATCH", "/v1/betaGroups/\(groupID)",
            ["data": ["type": "betaGroups", "id": groupID, "attributes": attrs]])
    }
    let group = attributes(api("GET", "/v1/betaGroups/\(groupID)?fields[betaGroups]=publicLinkEnabled,publicLink,publicLinkLimit,publicLinkLimitEnabled")["data"] as? JSON ?? [:])
    if group["publicLinkEnabled"] as? Bool == true, let url = group["publicLink"] as? String {
        let limit = group["publicLinkLimitEnabled"] as? Bool == true ? " (up to \(group["publicLinkLimit"] ?? "?") testers)" : ""
        print("Public link is on\(limit): \(url)")
    } else {
        print("Public link is off.")
    }
}

// MARK: - Submitting a build

func submit(_ which: String) {
    guard let (_, code, name) = platforms.first(where: { $0.0 == which }) else {
        fail("Say which build: ./asc.sh submit ios   or   ./asc.sh submit mac")
    }
    // The What to Test notes come from testflight-notes.txt in the project.
    let notesPath = FileManager.default.currentDirectoryPath + "/testflight-notes.txt"
    guard let notes = try? String(contentsOfFile: notesPath, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty else {
        fail("No What to Test notes: put them in \(notesPath).")
    }

    // Apple processes an upload for a few minutes before it can be tested.
    // Check every 30 seconds, for up to 30 minutes.
    var newest = builds(platform: code, limit: 1).first
    var waited = 0
    while let build = newest, build.processing == "PROCESSING", waited < 1800 {
        if waited == 0 { print("\(name) build \(build.number) is still processing; waiting…") }
        Thread.sleep(forTimeInterval: 30)
        waited += 30
        newest = builds(platform: code, limit: 1).first
    }
    guard let build = newest else { fail("No \(name) builds found.") }
    guard build.processing == "VALID" else { fail("\(name) build \(build.number) is \(plain(build.processing)).") }
    guard build.external == "READY_FOR_BETA_SUBMISSION" else {
        fail("\(name) build \(build.number) is \(plain(build.external)), so there's nothing to submit.")
    }

    // Ask first: this sends the build to Apple. (Pass --yes to skip asking,
    // for example when someone has already said yes in another way.)
    if !CommandLine.arguments.contains("--yes") {
        print("Send \(name) build \(build.number) to Beta App Review for the Testers group? Type yes to go ahead: ", terminator: "")
        guard readLine()?.lowercased() == "yes" else { print("Nothing sent."); return }
    }

    // 1. The What to Test notes (one per language; this app has English only).
    let existing = api("GET", "/v1/builds/\(build.id)/betaBuildLocalizations")["data"] as? [JSON] ?? []
    if let english = existing.first(where: { (attributes($0)["locale"] as? String) == "en-US" }),
       let id = english["id"] as? String {
        api("PATCH", "/v1/betaBuildLocalizations/\(id)",
            ["data": ["type": "betaBuildLocalizations", "id": id, "attributes": ["whatsNew": notes]]])
    } else {
        api("POST", "/v1/betaBuildLocalizations", ["data": [
            "type": "betaBuildLocalizations",
            "attributes": ["locale": "en-US", "whatsNew": notes],
            "relationships": ["build": ["data": ["type": "builds", "id": build.id]]],
        ]])
    }
    // 2. Give the Testers group the build.
    api("POST", "/v1/betaGroups/\(groupID)/relationships/builds",
        ["data": [["type": "builds", "id": build.id]]])
    // 3. Send it for review. (Only the first build of each version needs a
    //    full review; Apple often approves later ones within minutes.)
    api("POST", "/v1/betaAppReviewSubmissions", ["data": [
        "type": "betaAppReviewSubmissions",
        "relationships": ["build": ["data": ["type": "builds", "id": build.id]]],
    ]])
    print("Sent \(name) build \(build.number) to Beta App Review. Apple emails you the result.")
}

// MARK: - Main

let args = Array(CommandLine.arguments.dropFirst()).filter { $0 != "--yes" }
switch args.first {
case "status": status()
case "testers": showTesters()
case "add-tester":
    guard args.count >= 2 else { fail("Usage: ./asc.sh add-tester EMAIL [FIRST LAST]") }
    addTester(email: args[1], first: args.count > 2 ? args[2] : "", last: args.count > 3 ? args[3...].joined(separator: " ") : "")
case "remove-tester":
    guard args.count == 2 else { fail("Usage: ./asc.sh remove-tester EMAIL") }
    removeTester(email: args[1])
case "link": link(Array(args.dropFirst()))
case "submit": submit(args.count > 1 ? args[1] : "")
default:
    print("""
    Usage:
      ./asc.sh status
      ./asc.sh testers
      ./asc.sh add-tester EMAIL [FIRST LAST]
      ./asc.sh remove-tester EMAIL
      ./asc.sh link            (or: link on [LIMIT], link off)
      ./asc.sh submit ios|mac
    """)
}
