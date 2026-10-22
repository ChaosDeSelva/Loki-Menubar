import CoreGraphics

/// Geometry from brand/loki-folded-rune.svg. Shared by the UI and app-icon renderer.
enum LokiGlyph {
    static func paths(in rect: CGRect, flipped: Bool = false) -> [CGPath] {
        let bounds = CGRect(x: 300, y: 150, width: 740, height: 950)
        let scale = min(rect.width / bounds.width, rect.height / bounds.height)
        let x = rect.midX - bounds.width * scale / 2 - bounds.minX * scale
        let y = flipped ? rect.midY + bounds.height * scale / 2 + bounds.minY * scale : rect.midY - bounds.height * scale / 2 - bounds.minY * scale
        var transform = CGAffineTransform(a: scale, b: 0, c: 0, d: flipped ? -scale : scale, tx: x, ty: y)
        var result: [CGPath] = []
        do {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 382, y: 756))
            p.addLine(to: CGPoint(x: 382, y: 390))
            p.addCurve(to: CGPoint(x: 435, y: 288), control1: CGPoint(x: 382, y: 345), control2: CGPoint(x: 399, y: 311))
            p.addLine(to: CGPoint(x: 635, y: 175))
            p.addCurve(to: CGPoint(x: 676, y: 211), control1: CGPoint(x: 660, y: 160), control2: CGPoint(x: 676, y: 176))
            p.addLine(to: CGPoint(x: 676, y: 709))
            p.addCurve(to: CGPoint(x: 637, y: 791), control1: CGPoint(x: 676, y: 748), control2: CGPoint(x: 664, y: 774))
            p.addLine(to: CGPoint(x: 548, y: 850))
            p.addLine(to: CGPoint(x: 622, y: 891))
            p.addLine(to: CGPoint(x: 700, y: 839))
            p.addCurve(to: CGPoint(x: 815, y: 800), control1: CGPoint(x: 734, y: 816), control2: CGPoint(x: 772, y: 800))
            p.addLine(to: CGPoint(x: 1023, y: 800))
            p.addCurve(to: CGPoint(x: 895, y: 1005), control1: CGPoint(x: 1001, y: 898), control2: CGPoint(x: 959, y: 963))
            p.addLine(to: CGPoint(x: 800, y: 1060))
            p.addCurve(to: CGPoint(x: 714, y: 1083), control1: CGPoint(x: 770, y: 1078), control2: CGPoint(x: 747, y: 1083))
            p.addLine(to: CGPoint(x: 450, y: 1083))
            p.addCurve(to: CGPoint(x: 338, y: 1033), control1: CGPoint(x: 402, y: 1083), control2: CGPoint(x: 365, y: 1066))
            p.addCurve(to: CGPoint(x: 318, y: 942), control1: CGPoint(x: 324, y: 1015), control2: CGPoint(x: 318, y: 984))
            p.addLine(to: CGPoint(x: 318, y: 859))
            p.addCurve(to: CGPoint(x: 365, y: 768), control1: CGPoint(x: 318, y: 818), control2: CGPoint(x: 335, y: 788))
            p.closeSubpath()
            result.append(p.copy(using: &transform)!)
        }
        do {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 435, y: 288))
            p.addLine(to: CGPoint(x: 635, y: 175))
            p.addCurve(to: CGPoint(x: 676, y: 211), control1: CGPoint(x: 660, y: 160), control2: CGPoint(x: 676, y: 176))
            p.addLine(to: CGPoint(x: 676, y: 533))
            p.addCurve(to: CGPoint(x: 631, y: 613), control1: CGPoint(x: 676, y: 570), control2: CGPoint(x: 662, y: 592))
            p.addLine(to: CGPoint(x: 548, y: 660))
            p.addLine(to: CGPoint(x: 548, y: 493))
            p.addCurve(to: CGPoint(x: 516, y: 435), control1: CGPoint(x: 548, y: 466), control2: CGPoint(x: 538, y: 450))
            p.addLine(to: CGPoint(x: 444, y: 389))
            p.addCurve(to: CGPoint(x: 435, y: 288), control1: CGPoint(x: 402, y: 362), control2: CGPoint(x: 398, y: 323))
            p.closeSubpath()
            result.append(p.copy(using: &transform)!)
        }
        do {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 382, y: 756))
            p.addLine(to: CGPoint(x: 548, y: 660))
            p.addLine(to: CGPoint(x: 548, y: 850))
            p.addLine(to: CGPoint(x: 622, y: 891))
            p.addLine(to: CGPoint(x: 427, y: 1003))
            p.addCurve(to: CGPoint(x: 404, y: 1071), control1: CGPoint(x: 393, y: 1023), control2: CGPoint(x: 384, y: 1050))
            p.addCurve(to: CGPoint(x: 338, y: 1033), control1: CGPoint(x: 377, y: 1063), control2: CGPoint(x: 355, y: 1050))
            p.addCurve(to: CGPoint(x: 318, y: 942), control1: CGPoint(x: 324, y: 1015), control2: CGPoint(x: 318, y: 984))
            p.addLine(to: CGPoint(x: 318, y: 859))
            p.addCurve(to: CGPoint(x: 365, y: 768), control1: CGPoint(x: 318, y: 818), control2: CGPoint(x: 335, y: 788))
            p.closeSubpath()
            result.append(p.copy(using: &transform)!)
        }
        do {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 622, y: 891))
            p.addLine(to: CGPoint(x: 700, y: 839))
            p.addCurve(to: CGPoint(x: 815, y: 800), control1: CGPoint(x: 734, y: 816), control2: CGPoint(x: 772, y: 800))
            p.addLine(to: CGPoint(x: 1023, y: 800))
            p.addCurve(to: CGPoint(x: 927, y: 984), control1: CGPoint(x: 1005, y: 883), control2: CGPoint(x: 973, y: 944))
            p.addCurve(to: CGPoint(x: 809, y: 980), control1: CGPoint(x: 890, y: 1007), control2: CGPoint(x: 851, y: 1000))
            p.closeSubpath()
            result.append(p.copy(using: &transform)!)
        }
        return result
    }
}
