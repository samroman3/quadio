import SwiftUI

private struct TextScaleKey: EnvironmentKey {
    static let defaultValue: Double = 1.5
}

extension EnvironmentValues {
    var textScale: Double {
        get { self[TextScaleKey.self] }
        set { self[TextScaleKey.self] = newValue }
    }
}
