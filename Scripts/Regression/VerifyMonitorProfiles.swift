import Foundation
@main struct VerifyMonitorProfiles {
    static func main() throws {
        var count = 0
        try exerciseMonitorProfiles { value, reason in precondition(value, reason); count += 1 }
        print("PASS: \(count) monitor profile checks")
    }
}
