import UIKit

public final class DaySymbolsView: UIView {
    public private(set) var daysInWeek = 7
    private var calendar = Calendar.autoupdatingCurrent
    private var labels = [UILabel]()
    private var style: DaySymbolsStyle = DaySymbolsStyle()
    
    override public init(frame: CGRect) {
        super.init(frame: frame)
        initializeViews()
    }
    
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        initializeViews()
    }
    
    public init(daysInWeek: Int = 7, calendar: Calendar = Calendar.autoupdatingCurrent) {
        self.calendar = calendar
        self.daysInWeek = daysInWeek
        super.init(frame: CGRect.zero)
        initializeViews()
    }
    
    private func initializeViews() {
        for _ in 1...daysInWeek {
            let label = UILabel()
            label.textAlignment = .center
            labels.append(label)
            addSubview(label)
        }
        configure()
    }
    
    public func updateStyle(_ newStyle: DaySymbolsStyle) {
        style = newStyle
        configure()
    }
    
    private func configure() {
        let daySymbols = (style.useShortDaySymbols ? calendar.veryShortWeekdaySymbols : calendar.shortWeekdaySymbols).map { $0.uppercased() }
        let weekendMask = [true] + [Bool](repeating: false, count: 5) + [true]
        var weekDays = Array(zip(daySymbols, weekendMask))
        
        weekDays.shift(calendar.firstWeekday - 1)
        
        let rightToLeft = UIView.userInterfaceLayoutDirection(for: semanticContentAttribute) == .rightToLeft
        if rightToLeft { weekDays.reverse() }
        
        for (index, label) in labels.enumerated() {
            label.text = weekDays[index].0
            label.textColor = weekDays[index].1 ? style.weekendColor : style.weekDayColor
            label.font = style.font
        }
    }
    
    
    override public func layoutSubviews() {
        let labelWidth = bounds.width / CGFloat(daysInWeek)
        for (index, label) in labels.enumerated() {
            label.frame = CGRect(x: CGFloat(index) * labelWidth, y: 0, width: labelWidth, height: bounds.height)
        }
    }
}
