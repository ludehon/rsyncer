import Foundation
import IOKit.ps

enum PowerSource {
    static var isUsingExternalPower: Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let value = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() else { return true }
        return (value as String) == (kIOPSACPowerValue as String)
    }
}
