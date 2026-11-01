import Foundation
@main struct VerifyBrightness {
    static func main() throws {
        var count = 0
        func check(_ value: Bool, _ reason: String) {
            guard value else {
                FileHandle.standardError.write(Data("Brightness regression failed: \(reason)\n".utf8))
                exit(1)
            }
            count += 1
        }
        try exerciseMonitorBrightness(check)
        exerciseBrightnessWork(check)
        exerciseBrightnessNotifications(check)
        print("PASS: \(count) monitor brightness checks")
    }
}
