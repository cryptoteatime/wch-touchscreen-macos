import Foundation
@main struct VerifyRestoration {
    static func main() throws {
        var count = 0
        try exerciseDesktopRestoration { value, reason in precondition(value, reason); count += 1 }
        exerciseDesktopLayoutReadiness { value, reason in precondition(value, reason); count += 1 }
        print("PASS: \(count) reboot window restoration checks")
    }
}
