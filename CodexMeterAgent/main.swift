import Foundation
import WidgetKit

let completion = DispatchSemaphore(value: 0)
Task {
    _ = await UsageService.shared.fetch()
    WidgetCenter.shared.reloadAllTimelines()
    completion.signal()
}
completion.wait()
