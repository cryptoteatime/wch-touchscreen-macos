import Foundation
@main struct VerifyBrightness {
    static func main() throws {
        var count = 0
        try exerciseMonitorBrightness { value, reason in precondition(value, reason); count += 1 }
        print("PASS: \(count) monitor brightness checks")
    }
}
