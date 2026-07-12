import Foundation
import WidgetKit

let completion = DispatchSemaphore(value: 0)
Task {
    _ = await UsageService.shared.fetch()
    WidgetCenter.shared.reloadTimelines(ofKind: "CodexMeterWidgetV2")
    completion.signal()
}
completion.wait()
