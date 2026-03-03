import SwiftUI

extension View {
    func cardStyle() -> some View {
        padding(.vertical, 14)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
