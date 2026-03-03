import SwiftUI

/// Floating action button that opens the app switcher overlay.
/// Draggable and snaps to nearest edge when released, just like the Flutter version.
struct AppSwitcherFAB: View {
    @StateObject private var runtimeManager = AppRuntimeManager.shared
    @State private var showingSwitcher = false
    @State private var position = CGPoint(x: 1.0, y: 0.5) // Start at mid-right (normalized: x: right edge, y: center)
    @State private var dragOffset = CGSize.zero

    private let fabSize: CGFloat = 60
    private let padding: CGFloat = 16

    var body: some View {
        // Only show FAB if there are running apps
        if runtimeManager.runningApps.isEmpty {
            EmptyView()
        } else {
            GeometryReader { geometry in
                ZStack {
                    fabButton
                        .position(calculatePosition(in: geometry.size))
                        .gesture(
                            DragGesture()
                                .onChanged { gesture in
                                    dragOffset = gesture.translation
                                }
                                .onEnded { gesture in
                                    // Calculate new position
                                    let currentPos = calculatePosition(in: geometry.size)
                                    let newX = currentPos.x + gesture.translation.width
                                    let newY = currentPos.y + gesture.translation.height

                                    // Convert to normalized position (0.0 to 1.0)
                                    let normalizedX = newX / geometry.size.width
                                    let normalizedY = newY / geometry.size.height

                                    // Snap to nearest edge
                                    position = snapToEdge(CGPoint(x: normalizedX, y: normalizedY))
                                    dragOffset = .zero
                                }
                        )
                }
            }
        }
    }

    private var fabButton: some View {
        Button {
            showingSwitcher = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: fabSize, height: fabSize)
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)

                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .frame(width: fabSize, height: fabSize)

                // Badge showing number of running apps
                if runtimeManager.runningApps.count > 0 {
                    Text("\(runtimeManager.runningApps.count)")
                        .font(.caption2.bold())
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)
                        .background(Color.red)
                        .clipShape(Circle())
                        .offset(x: 8, y: -8)
                }
            }
        }
        .buttonStyle(.plain)
        .offset(dragOffset)
        .sheet(isPresented: $showingSwitcher) {
            AppSwitcherOverlay()
                .presentationDetents([.medium, .large])
        }
    }

    /// Calculate actual screen position from normalized position (0.0-1.0)
    private func calculatePosition(in size: CGSize) -> CGPoint {
        let isOnLeftEdge = position.x == 0.0
        let isOnRightEdge = position.x == 1.0
        let isOnTopEdge = position.y == 0.0
        let isOnBottomEdge = position.y == 1.0

        var x: CGFloat = 0
        var y: CGFloat = 0

        if isOnLeftEdge {
            x = padding + fabSize / 2
            y = position.y * (size.height - fabSize - 2 * padding) + padding + fabSize / 2
        } else if isOnRightEdge {
            x = size.width - padding - fabSize / 2
            y = position.y * (size.height - fabSize - 2 * padding) + padding + fabSize / 2
        } else if isOnTopEdge {
            x = position.x * (size.width - fabSize - 2 * padding) + padding + fabSize / 2
            y = padding + fabSize / 2
        } else if isOnBottomEdge {
            x = position.x * (size.width - fabSize - 2 * padding) + padding + fabSize / 2
            y = size.height - padding - fabSize / 2
        }

        return CGPoint(x: x, y: y)
    }

    /// Snaps the normalized position to the nearest edge
    private func snapToEdge(_ pos: CGPoint) -> CGPoint {
        // Calculate distance to each edge
        let distanceToLeft = pos.x
        let distanceToRight = 1.0 - pos.x
        let distanceToTop = pos.y
        let distanceToBottom = 1.0 - pos.y

        // Find minimum distance
        let minDistance = min(distanceToLeft, distanceToRight, distanceToTop, distanceToBottom)

        // Snap to the closest edge, keeping position along that edge
        if minDistance == distanceToLeft {
            return CGPoint(x: 0.0, y: pos.y)
        } else if minDistance == distanceToRight {
            return CGPoint(x: 1.0, y: pos.y)
        } else if minDistance == distanceToTop {
            return CGPoint(x: pos.x, y: 0.0)
        } else {
            return CGPoint(x: pos.x, y: 1.0)
        }
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.1)
        AppSwitcherFAB()
    }
}
