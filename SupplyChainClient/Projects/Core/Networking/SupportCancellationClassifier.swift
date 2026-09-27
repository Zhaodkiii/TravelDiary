import Foundation

enum SupportCancellationClassifier {
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let networkError = error as? SupportNetworkError {
            switch networkError {
            case .cancelled:
                return true
            case .transport(let urlError):
                return urlError.code == .cancelled
            default:
                return false
            }
        }
        if let urlError = error as? URLError {
            return urlError.code == .cancelled
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    static func reason(for error: Error) -> String {
        if error is CancellationError { return "taskCancelled" }
        if let networkError = error as? SupportNetworkError {
            switch networkError {
            case .cancelled:
                return "cancelled"
            case .transport(let urlError) where urlError.code == .cancelled:
                return "urlCancelled"
            default:
                break
            }
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return "urlCancelled"
        }
        return "cancelled"
    }
}
