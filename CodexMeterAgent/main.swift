import Foundation

let completion = DispatchSemaphore(value: 0)
Task {
    _ = await UsageService.shared.fetch()
    completion.signal()
}
completion.wait()
