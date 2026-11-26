import Foundation
import Darwin

/// A Unix-socket server for the hook script. Every connection sends one JSON line; a
/// `PermissionRequest` connection is then held open until Brim replies or the ask goes stale.
final class HookServer {
    /// Called on main for every event. `held` is non-nil for blocking asks; reply on it or close it.
    var onEvent: ((HookEvent, HeldConnection?) -> Void)?
    /// Called when a held ask's hook process goes away (answered elsewhere, or Claude Code killed it).
    var onHeldClosed: ((_ sessionID: String) -> Void)?

    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var clients: [Int32: Client] = [:]

    func start(at url: URL) {
        stop()
        unlink(url.path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = Array(url.path.utf8CString)
        guard path.count <= MemoryLayout.size(ofValue: address.sun_path) else { close(fd); return }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            path.withUnsafeBytes { raw.copyMemory(from: $0) }
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(fd, 16) == 0 else { close(fd); return }
        chmod(url.path, 0o600)
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

        listenFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in self?.acceptClients() }
        source.resume()
        acceptSource = source
    }

    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        for client in clients.values { client.close() }
        clients.removeAll()
        if listenFD >= 0 { close(listenFD); listenFD = -1 }
    }

    private func acceptClients() {
        while true {
            let fd = accept(listenFD, nil, nil)
            guard fd >= 0 else { return }

            var uid: uid_t = 0, gid: gid_t = 0
            guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else { close(fd); continue }
            var on: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

            let client = Client(fd: fd)
            client.onLine = { [weak self, weak client] line in
                guard let self, let client else { return }
                self.handle(line, from: client)
            }
            client.onClose = { [weak self] in self?.clients[fd] = nil }
            clients[fd] = client
            client.start()
        }
    }

    private func handle(_ line: Data, from client: Client) {
        guard let event = HookEvent(line: line) else { client.close(); return }
        if event.isBlocking {
            let fd = client.fd
            client.onClose = { [weak self] in
                self?.clients[fd] = nil
                self?.onHeldClosed?(event.sessionID)
            }
            onEvent?(event, HeldConnection(client: client))
        } else {
            client.close()
            onEvent?(event, nil)
        }
    }

    final class Client {
        let fd: Int32
        var onLine: ((Data) -> Void)?
        var onClose: (() -> Void)?
        private var buffer = Data()
        private var source: DispatchSourceRead?
        private var gotLine = false
        private(set) var isClosed = false

        init(fd: Int32) { self.fd = fd }

        func start() {
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
            source.setEventHandler { [weak self] in self?.read() }
            source.resume()
            self.source = source
        }

        private func read() {
            var chunk = [UInt8](repeating: 0, count: 16_384)
            let count = Darwin.read(fd, &chunk, chunk.count)
            if count <= 0 { close(); return }
            guard !gotLine else { return }
            buffer.append(contentsOf: chunk[0..<count])
            if let newline = buffer.firstIndex(of: 0x0A) {
                gotLine = true
                onLine?(buffer[buffer.startIndex..<newline])
            } else if buffer.count > 1_000_000 {
                close()
            }
        }

        func write(_ line: String) {
            guard !isClosed else { return }
            let bytes = Array((line + "\n").utf8)
            _ = bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
        }

        func close() {
            guard !isClosed else { return }
            isClosed = true
            source?.cancel()
            source = nil
            Darwin.close(fd)
            onClose?()
        }
    }
}

/// A hook process waiting on Brim. Reply once; closing without a reply leaves the terminal's own prompt in charge.
struct HeldConnection {
    fileprivate let client: HookServer.Client

    var isOpen: Bool { !client.isClosed }

    func reply(_ reply: AskReply) {
        client.write(reply.wireLine)
        client.close()
    }

    func release() { client.close() }
}
