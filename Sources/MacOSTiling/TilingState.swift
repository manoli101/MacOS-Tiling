import Foundation

enum Direction {
    case left, right, up, down
}

enum TilingState: Equatable {
    // Original states
    case floating
    case centered(screen: Int)
    case leftHalf(screen: Int)
    case rightHalf(screen: Int)
    case topHalf(screen: Int)
    case topLeft(screen: Int)
    case topRight(screen: Int)
    case bottomLeft(screen: Int)
    case bottomRight(screen: Int)
    case maximized(screen: Int)

    // Thirds
    case leftThird(screen: Int)       // leftmost 1/3
    case centerThird(screen: Int)     // middle 1/3
    case rightThird(screen: Int)      // rightmost 1/3
    case leftTwoThirds(screen: Int)   // left 2/3
    case rightTwoThirds(screen: Int)  // right 2/3

    static func == (lhs: TilingState, rhs: TilingState) -> Bool {
        switch (lhs, rhs) {
        case (.floating, .floating):                             return true
        case (.centered(let a),      .centered(let b)):          return a == b
        case (.leftHalf(let a),      .leftHalf(let b)):          return a == b
        case (.rightHalf(let a),     .rightHalf(let b)):         return a == b
        case (.topHalf(let a),       .topHalf(let b)):           return a == b
        case (.topLeft(let a),       .topLeft(let b)):           return a == b
        case (.topRight(let a),      .topRight(let b)):          return a == b
        case (.bottomLeft(let a),    .bottomLeft(let b)):        return a == b
        case (.bottomRight(let a),   .bottomRight(let b)):       return a == b
        case (.maximized(let a),     .maximized(let b)):         return a == b
        case (.leftThird(let a),     .leftThird(let b)):         return a == b
        case (.centerThird(let a),   .centerThird(let b)):       return a == b
        case (.rightThird(let a),    .rightThird(let b)):        return a == b
        case (.leftTwoThirds(let a), .leftTwoThirds(let b)):     return a == b
        case (.rightTwoThirds(let a),.rightTwoThirds(let b)):    return a == b
        default: return false
        }
    }
}
