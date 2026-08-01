import Foundation

public enum HookPayload {
    public static func extractSessionID(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["session_id"] as? String
    }
}
