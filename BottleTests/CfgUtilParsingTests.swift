import Foundation
import Testing
@testable import Bottle

/// Fixtures are verbatim cfgutil 2.20 output captured from a real iPhone.
struct CfgUtilParsingTests {
    private func output(_ stdout: String, stderr: String = "", status: Int32 = 0) -> ProcessRunner.Output {
        ProcessRunner.Output(status: status, stdout: stdout, stderr: stderr)
    }

    @Test func listWithOneDevice() throws {
        let json = #"{"Command":"list","Output":{"0x8294E3A41001C":{"locationID":17825792,"UDID":"00008130-0008294E3A41001C","ECID":"0x8294E3A41001C","name":"Logan’s iPhone","deviceType":"iPhone16,1"}},"Type":"CommandOutput","Devices":["0x8294E3A41001C"]}"#
        let result = try CfgUtil.parse(command: "list", output: output(json))
        #expect(result.devices == ["0x8294E3A41001C"])
        #expect(result.errors.isEmpty)
        let props = result.properties(for: "0x8294E3A41001C")
        #expect(props["name"] as? String == "Logan’s iPhone")
        #expect(props["deviceType"] as? String == "iPhone16,1")
    }

    @Test func listWithNoDevices() throws {
        let json = #"{"Command":"list","Output":{},"Type":"CommandOutput","Devices":[]}"#
        let result = try CfgUtil.parse(command: "list", output: output(json))
        #expect(result.devices.isEmpty)
    }

    /// cfgutil 2.20 puts "Errors" inside "Output", keyed by ECID, with an empty dict meaning no error.
    @Test func emptyNestedErrorsAreNotErrors() throws {
        let json = #"{"Command":"get","Output":{"0x1":{"isSupervised":true,"name":"x"},"Errors":{"0x1":{}}},"Type":"CommandOutput","Devices":["0x1"]}"#
        let result = try CfgUtil.parse(command: "get", output: output(json, status: 1))
        #expect(result.errors.isEmpty)
        #expect(result.output["Errors"] == nil, "Errors must not leak through as a device")
        #expect(JSONCoerce.bool(result.properties(for: "0x1")["isSupervised"]) == true)
    }

    @Test func nestedErrorWithMessageIsSurfaced() throws {
        let json = #"{"Command":"get","Output":{"Errors":{"0x1":{"Message":"Device is locked","Code":42}}},"Type":"CommandOutput","Devices":["0x1"]}"#
        let result = try CfgUtil.parse(command: "get", output: output(json))
        #expect(result.errors["0x1"] == "Device is locked")
        #expect(result.properties(for: "0x1").isEmpty)
    }

    @Test func topLevelErrorObjectThrows() {
        let json = #"{"Command":"prepare","Type":"Error","Message":"No devices found","Code":1}"#
        #expect(throws: CfgUtilError.self) {
            try CfgUtil.parse(command: "prepare", output: output(json, status: 1))
        }
    }

    @Test func lastJSONLineWinsOverProgressLines() throws {
        let stdout = """
        {"Type":"Progress","Percent":10}
        {"Type":"Progress","Percent":90}
        {"Command":"backup","Output":{},"Type":"CommandOutput","Devices":["0x1"]}
        """
        let result = try CfgUtil.parse(command: "backup", output: output(stdout))
        #expect(result.devices == ["0x1"])
    }

    /// get-app-icon prints plain text even in JSON mode.
    @Test func plainTextSuccessIsEmptyResult() throws {
        let result = try CfgUtil.parse(command: "get-app-icon", output: output("Saved 42 icons.\n", stderr: "cfgutil: error: no app with bundle ID com.bogus"))
        #expect(result.devices.isEmpty)
        #expect(result.errors.isEmpty)
    }

    @Test func nonZeroExitWithoutJSONThrowsStderr() {
        #expect(throws: CfgUtilError.self) {
            try CfgUtil.parse(command: "erase", output: output("", stderr: "cfgutil: error: Activation Lock is enabled", status: 1))
        }
    }
}

struct JSONCoerceTests {
    @Test func bools() {
        #expect(JSONCoerce.bool(true) == true)
        #expect(JSONCoerce.bool(NSNumber(value: 0)) == false)
        #expect(JSONCoerce.bool("YES") == true)
        #expect(JSONCoerce.bool("no") == false)
        #expect(JSONCoerce.bool("maybe") == nil)
        #expect(JSONCoerce.bool(nil) == nil)
    }

    @Test func numbersAndStrings() {
        #expect(JSONCoerce.int(NSNumber(value: 53)) == 53)
        #expect(JSONCoerce.int("7") == 7)
        #expect(JSONCoerce.string(NSNumber(value: 3)) == "3")
        #expect(JSONCoerce.string(["nope"]) == nil)
    }
}

struct DeviceTests {
    @Test func applyMapsRealGetOutput() throws {
        let json = #"{"activationState":"Activated","serialNumber":"ABC","backupWillBeEncrypted":false,"deviceType":"iPhone16,1","isRestorable":true,"UDID":"00008130-0008294E3A41001C","bootedState":"Booted","isSupervised":true,"humanReadableProductVersion":"26.6.1","organizationName":"Coventry Labs, LLC","isPaired":true,"passcodeProtected":false,"batteryCurrentCapacity":53,"name":"Logan’s iPhone"}"#
        let props = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        var device = Device(ecid: "0x1")
        device.apply(props)
        #expect(device.isSupervised == true)
        #expect(device.organizationName == "Coventry Labs, LLC")
        #expect(device.productVersion == "26.6.1")
        #expect(device.batteryLevel == 53)
        #expect(device.backupWillBeEncrypted == false)
        #expect(device.family == "iPhone")
        #expect(device.subtitle == "iOS 26.6.1 · Supervised")
    }

    @Test func displayNameFallsBackToFamily() {
        var device = Device(ecid: "0x1")
        device.deviceType = "iPad14,1"
        #expect(device.displayName == "iPad")
    }
}
