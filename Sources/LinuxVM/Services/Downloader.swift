import Foundation
import Combine

/// Streams an ISO to disk with progress, supporting cancellation. UI-bound, so
/// all published mutations happen on the main queue (the delegate queue is main).
final class ISODownloader: NSObject, ObservableObject, URLSessionDownloadDelegate {
    enum State: Equatable {
        case idle
        case downloading
        case finished
        case failed(String)
        case cancelled
    }

    @Published var state: State = .idle
    @Published var fractionCompleted: Double = 0
    @Published var receivedBytes: Int64 = 0
    @Published var totalBytes: Int64 = 0

    private var session: URLSession!
    private var task: URLSessionDownloadTask?
    private var destination: URL?
    private var continuation: CheckedContinuation<Void, Error>?

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }

    /// Downloads `url` to `destination`. Resolves when the file is in place.
    func download(from url: URL, to destination: URL) async throws {
        self.destination = destination
        state = .downloading
        fractionCompleted = 0
        receivedBytes = 0
        totalBytes = 0
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.continuation = cont
            let task = session.downloadTask(with: url)
            self.task = task
            task.resume()
        }
    }

    func cancel() {
        task?.cancel()
    }

    // MARK: URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        receivedBytes = totalBytesWritten
        totalBytes = totalBytesExpectedToWrite
        if totalBytesExpectedToWrite > 0 {
            fractionCompleted = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let destination else { return }
        do {
            // The temp file vanishes once this delegate returns, so move it now.
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            // Surface via the completion delegate below by stashing the error.
            failPending(error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // If a move failure already resolved us, don't overwrite that outcome.
        guard continuation != nil else { return }
        if let error = error as NSError? {
            if error.code == NSURLErrorCancelled {
                state = .cancelled
                resumePending(throwing: CancellationError())
            } else {
                failPending(error)
            }
            return
        }
        // Validate the response code; treat 4xx/5xx (saved as an HTML error
        // page) as a failure rather than a "successful" tiny download.
        if let http = task.response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            failPending(NSError(domain: "ISODownloader", code: http.statusCode,
                                userInfo: [NSLocalizedDescriptionKey: "Server returned HTTP \(http.statusCode). The link may be outdated."]))
            return
        }
        state = .finished
        fractionCompleted = 1
        resumePending(throwing: nil)
    }

    private func failPending(_ error: Error) {
        state = .failed(error.localizedDescription)
        if let dest = destination { try? FileManager.default.removeItem(at: dest) }
        resumePending(throwing: error)
    }

    private func resumePending(throwing error: Error?) {
        guard let cont = continuation else { return }
        continuation = nil
        if let error { cont.resume(throwing: error) } else { cont.resume() }
    }
}
