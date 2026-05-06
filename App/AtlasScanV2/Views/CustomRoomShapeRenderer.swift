/// CustomRoomShapeRenderer — SwiftUI `Shape`/`View` that draws a closed polygon
/// for the actual room perimeter, faithfully representing L-shapes, T-shapes,
/// alcoves, and other non-rectangular geometries.
///
/// Critical fix vs V1: V1 drew all rooms as rectangles (bounding-box approach).
/// V2 uses the actual vertex list from `RoomPolygon` to draw the true outline.

import SwiftUI
import AtlasScanCore

// MARK: - Polygon shape

/// A `Shape` that draws a closed polygon from a `RoomPolygon`.
public struct RoomPolygonShape: Shape {

    public let polygon: RoomPolygon

    public init(polygon: RoomPolygon) {
        self.polygon = polygon
    }

    public func path(in rect: CGRect) -> Path {
        guard polygon.isValid else { return Path() }

        // Compute the polygon bounding box so we can scale into `rect`.
        guard let bb = polygon.boundingBox else { return Path() }
        let polyWidth  = max(bb.widthM,  0.001)
        let polyDepth  = max(bb.depthM,  0.001)

        let scaleX = rect.width  / polyWidth
        let scaleY = rect.height / polyDepth

        // Use uniform scale with padding so the polygon fits inside the rect.
        let scale = min(scaleX, scaleY) * 0.9
        let offsetX = rect.midX - (bb.minX + polyWidth  / 2) * scale
        let offsetY = rect.midY - (bb.minZ + polyDepth / 2) * scale

        return Path { path in
            let first = polygon.vertices[0]
            path.move(to: CGPoint(
                x: first.x * scale + offsetX,
                y: first.z * scale + offsetY
            ))
            for vertex in polygon.vertices.dropFirst() {
                path.addLine(to: CGPoint(
                    x: vertex.x * scale + offsetX,
                    y: vertex.z * scale + offsetY
                ))
            }
            path.closeSubpath()
        }
    }
}

// MARK: - Renderer view

/// A view that fills and strokes the room polygon, with optional wall-fabric colouring.
public struct CustomRoomShapeRenderer: View {

    public let polygon: RoomPolygon
    public var fillColor: Color
    public var strokeColor: Color
    public var strokeLineWidth: CGFloat
    /// When `true`, each wall segment is coloured by its `WallFabric` classification.
    public var showFabricColors: Bool
    public var fabricSegments: [WallSegmentV1]

    public init(
        polygon: RoomPolygon,
        fillColor: Color = Color.blue.opacity(0.1),
        strokeColor: Color = .blue,
        strokeLineWidth: CGFloat = 2,
        showFabricColors: Bool = false,
        fabricSegments: [WallSegmentV1] = []
    ) {
        self.polygon = polygon
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.strokeLineWidth = strokeLineWidth
        self.showFabricColors = showFabricColors
        self.fabricSegments = fabricSegments
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                // Fill
                RoomPolygonShape(polygon: polygon)
                    .fill(fillColor)

                // Stroke — plain or per-segment fabric coloured
                if showFabricColors && !fabricSegments.isEmpty {
                    fabricColoredStroke(in: geo.size)
                } else {
                    RoomPolygonShape(polygon: polygon)
                        .stroke(strokeColor, lineWidth: strokeLineWidth)
                }

                // Vertex count badge
                if polygon.isValid {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text("\(polygon.count) vertices")
                                .font(.caption2)
                                .padding(4)
                                .background(.black.opacity(0.4), in: Capsule())
                                .foregroundStyle(.white)
                                .padding(4)
                        }
                    }
                }
            }
        }
    }

    // MARK: Fabric-coloured wall segments

    @ViewBuilder
    private func fabricColoredStroke(in size: CGSize) -> some View {
        guard let bb = polygon.boundingBox else { EmptyView() }

        let polyWidth = max(bb.widthM,  0.001)
        let polyDepth = max(bb.depthM,  0.001)
        let scale = min(size.width / polyWidth, size.height / polyDepth) * 0.9
        let offsetX = size.width  / 2 - (bb.minX + polyWidth / 2) * scale
        let offsetY = size.height / 2 - (bb.minZ + polyDepth / 2) * scale

        Canvas { ctx, _ in
            for seg in fabricSegments {
                let start = CGPoint(
                    x: seg.startVertex.x * scale + offsetX,
                    y: seg.startVertex.z * scale + offsetY
                )
                let end = CGPoint(
                    x: seg.endVertex.x * scale + offsetX,
                    y: seg.endVertex.z * scale + offsetY
                )
                var path = Path()
                path.move(to: start)
                path.addLine(to: end)
                ctx.stroke(
                    path,
                    with: .color(color(for: seg.fabric)),
                    lineWidth: strokeLineWidth * 1.5
                )
            }
        }
    }

    private func color(for fabric: WallFabric) -> Color {
        switch fabric {
        case .externalWall: return .red
        case .internalWall: return .blue
        case .partyWall:    return .purple
        }
    }
}

// MARK: - Fabric legend

struct FabricLegendView: View {
    var body: some View {
        HStack(spacing: 16) {
            ForEach(WallFabric.allCases, id: \.rawValue) { fabric in
                Label {
                    Text(fabric.displayName)
                        .font(.caption)
                } icon: {
                    Image(systemName: fabric.symbolName)
                        .foregroundStyle(legendColor(for: fabric))
                }
            }
        }
    }

    private func legendColor(for fabric: WallFabric) -> Color {
        switch fabric {
        case .externalWall: return .red
        case .internalWall: return .blue
        case .partyWall:    return .purple
        }
    }
}
