import Foundation
import UIKit

public protocol EventDescriptor: AnyObject {
    var id: String { get }
    var dateInterval: DateInterval {get set}
    var isAllDay: Bool {get}
    var text: String {get}
    var horizontalLayoutRange: ClosedRange<CGFloat> {get}
    var attributedText: NSAttributedString? {get}
    var lineBreakMode: NSLineBreakMode? {get}
    var font : UIFont {get}
    var color: UIColor {get}
    var textColor: UIColor {get}
    var backgroundColor: UIColor {get}
    var editedEvent: EventDescriptor? {get set}
    var editingCanChangeDuration: Bool { get }
    func makeEditable() -> Self
    func commitEditing()
}

public extension EventDescriptor where Self: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.id == rhs.id
    }
}
