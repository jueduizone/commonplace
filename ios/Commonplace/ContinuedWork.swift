import BackgroundTasks
import UIKit

/// CPU work only. Admission is controlled by iOS; a refused/expired task cancels safely.
@MainActor
final class ContinuedWork {
    private let identifier = "app.commonplace.ios.research"
    private var shortTask: UIBackgroundTaskIdentifier = .invalid
    private var current: BGTask?
    private var working = false
    var cancel: (() -> Void)?
    var status = "Foreground"

    func register() {
        if #available(iOS 26.0, *) {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { [weak self] task in
                Task { @MainActor in
                    guard let self, self.working else { task.setTaskCompleted(success: true); return }
                    self.current = task
                    self.status = "Continued CPU task admitted"
                    if let continued = task as? BGContinuedProcessingTask {
                        continued.progress.totalUnitCount = 400
                        continued.progress.completedUnitCount = 1
                    }
                    task.expirationHandler = { [weak self] in
                        Task { @MainActor in
                            self?.status = "Background time expired"
                            self?.cancel?()
                            self?.end(success: false)
                        }
                    }
                }
            }
        }
    }

    func begin() {
        working = true
        status = "Foreground"
        shortTask = UIApplication.shared.beginBackgroundTask(withName: "Finish offline answer") { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.current == nil { self.cancel?(); self.status = "Background time expired" }
                self.endShortTask()
            }
        }
        if #available(iOS 26.0, *) {
            let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: "Researching your library", subtitle: "Writing an answer on this iPhone")
            request.strategy = .fail
            do { try BGTaskScheduler.shared.submit(request) }
            catch { status = "Continued task unavailable; short background time only" }
        } else { status = "Short background time only" }
    }

    func progress(characters: Int) {
        if #available(iOS 26.0, *), let task = current as? BGContinuedProcessingTask {
            task.progress.completedUnitCount = min(399, max(task.progress.completedUnitCount, Int64(characters / 4)))
        }
    }

    func end(success: Bool) {
        working = false
        if #available(iOS 26.0, *), let task = current as? BGContinuedProcessingTask {
            task.progress.completedUnitCount = task.progress.totalUnitCount
        }
        current?.setTaskCompleted(success: success)
        current = nil
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        endShortTask()
    }

    private func endShortTask() {
        if shortTask != .invalid { UIApplication.shared.endBackgroundTask(shortTask); shortTask = .invalid }
    }
}
