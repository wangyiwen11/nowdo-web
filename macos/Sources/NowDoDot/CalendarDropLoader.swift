import AppKit

/// Receives only a file promise explicitly dropped by the user. No general
/// clipboard, Calendar database, or network access is involved.
@MainActor
enum CalendarDropLoader {
    static var promiseTypes: [NSPasteboard.PasteboardType] {
        NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
    }

    private static var transfers: [UUID: Transfer] = [:]

    static func canLoadPromise(_ board: NSPasteboard) -> Bool {
        board.availableType(from: promiseTypes) != nil
    }

    static func loadPromise(_ board: NSPasteboard, completion: @escaping (Result<Data, Error>) -> Void) {
        guard let receivers = board.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver],
              !receivers.isEmpty else {
            completion(.failure(CalendarDropLoaderError.unsupported))
            return
        }
        guard receivers.count == 1, (board.pasteboardItems?.count ?? 0) <= 1 else {
            completion(.failure(CalendarDropLoaderError.multipleFiles))
            return
        }
        do {
            let transfer = try Transfer(receiver: receivers[0], completion: completion)
            transfers[transfer.id] = transfer
            transfer.begin()
        } catch {
            completion(.failure(error))
        }
    }

    @MainActor private final class Transfer {
        let id = UUID()
        let receiver: NSFilePromiseReceiver
        let destination: URL
        let queue = OperationQueue()
        var completion: ((Result<Data, Error>) -> Void)?
        var timeout: DispatchWorkItem?
        var finished = false

        init(receiver: NSFilePromiseReceiver, completion: @escaping (Result<Data, Error>) -> Void) throws {
            self.receiver = receiver
            self.completion = completion
            destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("nowdo-calendar-drop-\(id.uuidString)", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false,
                                                       attributes: [.posixPermissions: 0o700])
            } catch {
                throw CalendarDropLoaderError.cannotReceive
            }
            queue.name = "NowDo calendar file promise"
            queue.maxConcurrentOperationCount = 1
            queue.qualityOfService = .userInitiated
        }

        func begin() {
            let expiry = DispatchWorkItem { [weak self] in
                self?.finish(.failure(CalendarDropLoaderError.timedOut))
            }
            timeout = expiry
            DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: expiry)
            let directory = destination
            receiver.receivePromisedFiles(atDestination: directory, options: [:], operationQueue: queue) { [weak self] url, error in
                // AppKit coordinates this callback with the source's write. Read
                // here, before the coordinated read scope ends, not in a later Task.
                let result: Result<Data, Error>
                if error != nil {
                    result = .failure(CalendarDropLoaderError.cannotReceive)
                } else {
                    result = Result { try CalendarDropLoader.readFile(url, inside: directory) }
                }
                Task { @MainActor [weak self] in self?.delivered(result, fileName: url.lastPathComponent) }
            }
            // fileNames can still be empty here; it is not proof of zero files.
            // Never use fileTypes.count: legacy providers list each type only once.
            if receiver.fileNames.count > 1 { finish(.failure(CalendarDropLoaderError.multipleFiles)) }
        }

        func delivered(_ result: Result<Data, Error>, fileName: String) {
            guard !finished else { return }
            if case .failure = result { finish(result); return }
            let names = receiver.fileNames
            guard names.count == 1 else {
                finish(.failure(names.isEmpty ? CalendarDropLoaderError.unknownFileCount : .multipleFiles))
                return
            }
            // Only the complete, single-file promise set may start a timer.
            guard names[0] == fileName else {
                finish(.failure(CalendarDropLoaderError.cannotReceive))
                return
            }
            finish(result)
        }

        func finish(_ result: Result<Data, Error>) {
            guard !finished else { return }
            finished = true
            timeout?.cancel()
            timeout = nil
            queue.cancelAllOperations()
            try? FileManager.default.removeItem(at: destination)
            let callback = completion
            completion = nil
            CalendarDropLoader.transfers.removeValue(forKey: id)
            callback?(result)
        }
    }

    /// Internal so the file boundary can be checked without reading any real drag.
    nonisolated static func readFile(_ url: URL, inside directory: URL) throws -> Data {
        guard url.isFileURL, url.pathExtension.lowercased() == "ics" else {
            throw CalendarDropLoaderError.unsupported
        }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              url.resolvingSymlinksInPath().deletingLastPathComponent() == directory.resolvingSymlinksInPath() else {
            throw CalendarDropLoaderError.unsupported
        }
        guard let size = values.fileSize, size >= 0, size <= 1_048_576 else {
            throw CalendarDropLoaderError.tooLarge
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 1_048_577) ?? Data()
        guard data.count <= 1_048_576 else { throw CalendarDropLoaderError.tooLarge }
        return data
    }
}

private enum CalendarDropLoaderError: LocalizedError {
    case unsupported, multipleFiles, unknownFileCount, cannotReceive, timedOut, tooLarge
    var errorDescription: String? {
        switch self {
        case .unsupported: return "这次拖入没有可读取的日程文件，请拖入一条日历事项。"
        case .multipleFiles: return "请一次只拖入一条日程，当前计时保持不变。"
        case .unknownFileCount: return "日历没有确认传入的是一条事项，请重新拖入。"
        case .cannotReceive: return "日历暂未交付日程内容，请保持日历打开后重试。"
        case .timedOut: return "等待日历传入超时，请重新拖入；当前计时保持不变。"
        case .tooLarge: return "这条日历内容过大，请只拖入一条事项。"
        }
    }
}
