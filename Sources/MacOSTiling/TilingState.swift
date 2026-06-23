import Foundation

enum Direction {
    case left, right, up, down
}

enum TilingState: Equatable {
    case floating
    case centered(screen: Int)     // ~60% width, 65% height, centrado en pantalla
    case leftHalf(screen: Int)
    case rightHalf(screen: Int)
    case topHalf(screen: Int)
    case topLeft(screen: Int)
    case topRight(screen: Int)
    case bottomLeft(screen: Int)
    case bottomRight(screen: Int)
    case maximized(screen: Int)

    static func == (lhs: TilingState, rhs: TilingState) -> Bool {
        switch (lhs, rhs) {
        case (.floating, .floating): return true
        case (.centered(let a), .centered(let b)): return a == b
        case (.leftHalf(let a), .leftHalf(let b)): return a == b
        case (.rightHalf(let a), .rightHalf(let b)): return a == b
        case (.topHalf(let a), .topHalf(let b)): return a == b
        case (.topLeft(let a), .topLeft(let b)): return a == b
        case (.topRight(let a), .topRight(let b)): return a == b
        case (.bottomLeft(let a), .bottomLeft(let b)): return a == b
        case (.bottomRight(let a), .bottomRight(let b)): return a == b
        case (.maximized(let a), .maximized(let b)): return a == b
        default: return false
        }
    }
}
