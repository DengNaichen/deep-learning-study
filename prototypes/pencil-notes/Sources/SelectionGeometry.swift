import CoreGraphics

/// All positions use the fixed page's points, never screen pixels.
enum SelectionGeometry {
    static func rectangle(from start: CGPoint, to end: CGPoint,
                          within bounds: CGRect = PrototypeConfiguration.Page.bounds) -> CGRect? {
        let raw = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                         width: abs(end.x - start.x), height: abs(end.y - start.y))
        return validated(raw, within: bounds)
    }

    static func validated(_ rect: CGRect, within bounds: CGRect = PrototypeConfiguration.Page.bounds) -> CGRect? {
        guard [rect.origin.x, rect.origin.y, rect.width, rect.height].allSatisfy({ $0.isFinite }) else {
            return nil
        }
        let clipped = rect.standardized.intersection(bounds)
        let minimumSide = PrototypeConfiguration.Page.minimumSelectionSide
        guard !clipped.isNull, clipped.width >= minimumSide, clipped.height >= minimumSide else {
            return nil
        }
        return clipped
    }
}
