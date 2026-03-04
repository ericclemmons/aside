import Foundation
import AsideCore

/// Wraps CLIDispatcher for dispatching prompts.
final class DispatchService {
    func dispatch(prompt: String, server: DiscoveredServer, sessionID: String?, filePaths: [String], workingDirectory: String?) {
        CLIDispatcher.dispatch(
            prompt: prompt,
            server: server,
            sessionID: sessionID,
            filePaths: filePaths,
            workingDirectory: workingDirectory
        )
    }
}
