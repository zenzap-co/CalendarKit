import UIKit

public protocol TimelineViewDelegate: AnyObject {
    func timelineView(_ timelineView: TimelineView, didTapAt date: Date)
    func timelineView(_ timelineView: TimelineView, didLongPressAt date: Date)
    func timelineView(_ timelineView: TimelineView, didTap event: EventView)
    func timelineView(_ timelineView: TimelineView, didLongPress event: EventView)
}

public final class TimelineView: UIView {
    public weak var delegate: TimelineViewDelegate?

    public var date = Date() {
        didSet {
            setNeedsLayout()
        }
    }

    private var currentTime: Date {
        Date()
    }

    private var eventViews = [EventView]()
    public private(set) var regularLayoutAttributes = [EventLayoutAttributes]()
    public private(set) var allDayLayoutAttributes = [EventLayoutAttributes]()

    public var layoutAttributes: [EventLayoutAttributes] {
        get {
            allDayLayoutAttributes + regularLayoutAttributes
        }
        set {

            // update layout attributes by separating all-day from non-all-day events
            allDayLayoutAttributes.removeAll()
            regularLayoutAttributes.removeAll()
            for anEventLayoutAttribute in newValue {
                let eventDescriptor = anEventLayoutAttribute.descriptor
                if eventDescriptor.isAllDay {
                    allDayLayoutAttributes.append(anEventLayoutAttribute)
                } else {
                    regularLayoutAttributes.append(anEventLayoutAttribute)
                }
            }

            recalculateEventLayout()
            prepareEventViews()
            allDayView.events = allDayLayoutAttributes.map { $0.descriptor }
            allDayView.isHidden = allDayLayoutAttributes.count == 0
            allDayView.scrollToBottom()

            setNeedsLayout()
        }
    }
    private var pool = ReusePool<EventView>()

    public var firstEventYPosition: Double? {
        let first = regularLayoutAttributes.sorted{$0.frame.origin.y < $1.frame.origin.y}.first
        guard let firstEvent = first else {return nil}
        let firstEventPosition = firstEvent.frame.origin.y
        let beginningOfDayPosition = dateToY(date)
        return max(firstEventPosition, beginningOfDayPosition)
    }

    private lazy var nowLine: CurrentTimeIndicator = CurrentTimeIndicator()

    private var allDayViewTopConstraint: NSLayoutConstraint?
    private lazy var allDayView: AllDayView = {
        let allDayView = AllDayView(frame: CGRect.zero)

        allDayView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(allDayView)

        allDayViewTopConstraint = allDayView.topAnchor.constraint(equalTo: topAnchor, constant: 0)
        allDayViewTopConstraint?.isActive = true

        allDayView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0).isActive = true
        allDayView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 0).isActive = true

        return allDayView
    }()

    var allDayViewHeight: Double {
        allDayView.bounds.height
    }

    var style = TimelineStyle()
    private var horizontalEventInset: Double = 3

    public var fullHeight: Double {
        style.verticalInset * 2 + style.verticalDiff * 24
    }

    public var calendarWidth: Double {
        bounds.width - style.leadingInset
    }
    
    public private(set) var is24hClock = true {
        didSet {
            setNeedsDisplay()
        }
    }

    public var calendar: Calendar = Calendar.autoupdatingCurrent {
        didSet {
            eventEditingSnappingBehavior.calendar = calendar
            nowLine.calendar = calendar
            regenerateTimeStrings()
            setNeedsLayout()
        }
    }

    public var eventEditingSnappingBehavior: EventEditingSnappingBehavior = SnapTo15MinuteIntervals() {
        didSet {
            eventEditingSnappingBehavior.calendar = calendar
        }
    }

    private var times: [String] {
        is24hClock ? _24hTimes : _12hTimes
    }

    private lazy var _12hTimes: [String] = TimeStringsFactory(calendar).make12hStrings()
    private lazy var _24hTimes: [String] = TimeStringsFactory(calendar).make24hStrings()

    private func regenerateTimeStrings() {
        let factory = TimeStringsFactory(calendar)
        _12hTimes = factory.make12hStrings()
        _24hTimes = factory.make24hStrings()
    }

    public lazy private(set) var longPressGestureRecognizer = UILongPressGestureRecognizer(target: self,
                                                                                           action: #selector(longPress(_:)))

    public lazy private(set) var tapGestureRecognizer = UITapGestureRecognizer(target: self,
                                                                               action: #selector(tap(_:)))

    private var isToday: Bool {
        calendar.isDateInToday(date)
    }

    // MARK: - Initialization

    public init() {
        super.init(frame: .zero)
        frame.size.height = fullHeight
        configure()
    }

    override public init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        configure()
    }

    private func configure() {
        contentScaleFactor = 1
        layer.contentsScale = 1
        contentMode = .redraw
        backgroundColor = .white
        addSubview(nowLine)

        // Add long press gesture recognizer
        addGestureRecognizer(longPressGestureRecognizer)
        addGestureRecognizer(tapGestureRecognizer)
    }

    // MARK: - Event Handling

    @objc private func longPress(_ gestureRecognizer: UILongPressGestureRecognizer) {
        if (gestureRecognizer.state == .began) {
            // Get timeslot of gesture location
            let pressedLocation = gestureRecognizer.location(in: self)
            if let eventView = findEventView(at: pressedLocation) {
                delegate?.timelineView(self, didLongPress: eventView)
            } else {
                delegate?.timelineView(self, didLongPressAt: yToDate(pressedLocation.y))
            }
        }
    }

    @objc private func tap(_ sender: UITapGestureRecognizer) {
        let pressedLocation = sender.location(in: self)
        if let eventView = findEventView(at: pressedLocation) {
            delegate?.timelineView(self, didTap: eventView)
        } else {
            delegate?.timelineView(self, didTapAt: yToDate(pressedLocation.y))
        }
    }

    private func findEventView(at point: CGPoint) -> EventView? {
        for eventView in allDayView.eventViews {
            let frame = eventView.convert(eventView.bounds, to: self)
            if frame.contains(point) {
                return eventView
            }
        }

        for eventView in eventViews {
            let frame = eventView.frame
            if frame.contains(point) {
                return eventView
            }
        }
        return nil
    }


    /**
     Custom implementation of the hitTest method is needed for the tap gesture recognizers
     located in the AllDayView to work.
     Since the AllDayView could be outside of the Timeline's bounds, the touches to the EventViews
     are ignored.
     In the custom implementation the method is recursively invoked for all of the subviews,
     regardless of their position in relation to the Timeline's bounds.
     */
    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        for subview in allDayView.subviews {
            if let subSubView = subview.hitTest(convert(point, to: subview), with: event) {
                return subSubView
            }
        }
        return super.hitTest(point, with: event)
    }

    // MARK: - Style

    public func updateStyle(_ newStyle: TimelineStyle) {
        style = newStyle
        allDayView.updateStyle(style.allDayStyle)
        nowLine.updateStyle(style.timeIndicator)

        switch style.dateStyle {
        case .twelveHour:
            is24hClock = false
        case .twentyFourHour:
            is24hClock = true
        default:
            is24hClock = calendar.locale?.uses24hClock ?? Locale.autoupdatingCurrent.uses24hClock
        }

        backgroundColor = style.backgroundColor
        setNeedsDisplay()
    }

    // MARK: - Background Pattern

    public var accentedDate: Date?

    override public func draw(_ rect: CGRect) {
        super.draw(rect)

        var hourToRemoveIndex = -1

        var accentedHour = -1
        var accentedMinute = -1

        if let accentedDate {
            accentedHour = eventEditingSnappingBehavior.accentedHour(for: accentedDate)
            accentedMinute = eventEditingSnappingBehavior.accentedMinute(for: accentedDate)
        }

        if isToday {
            let minute = component(component: .minute, from: currentTime)
            let hour = component(component: .hour, from: currentTime)
            if minute > 39 {
                hourToRemoveIndex = hour + 1
            } else if minute < 21 {
                hourToRemoveIndex = hour
            }
        }

        let mutableParagraphStyle = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
        mutableParagraphStyle.lineBreakMode = .byWordWrapping
        mutableParagraphStyle.alignment = .right
        let paragraphStyle = mutableParagraphStyle.copy() as! NSParagraphStyle

        let attributes = [NSAttributedString.Key.paragraphStyle: paragraphStyle,
                          NSAttributedString.Key.foregroundColor: self.style.timeColor,
                          NSAttributedString.Key.font: style.font] as [NSAttributedString.Key : Any]

        let scale = UIScreen.main.scale
        let hourLineHeight = 1 / UIScreen.main.scale

        let center: Double
        if Int(scale) % 2 == 0 {
            center = 1 / (scale * 2)
        } else {
            center = 0
        }

        let offset = 0.5 - center

        for (hour, time) in times.enumerated() {
            let rightToLeft = UIView.userInterfaceLayoutDirection(for: semanticContentAttribute) == .rightToLeft

            let hourFloat = Double(hour)
            let context = UIGraphicsGetCurrentContext()
            context!.interpolationQuality = .none
            context?.saveGState()
            context?.setStrokeColor(style.separatorColor.cgColor)
            context?.setLineWidth(hourLineHeight)
            let xStart: Double = {
                if rightToLeft {
                    return bounds.width - 53
                } else {
                    return 53
                }
            }()
            let xEnd: Double = {
                if rightToLeft {
                    return 0
                } else {
                    return bounds.width
                }
            }()
            let y = style.verticalInset + hourFloat * style.verticalDiff + offset
            context?.beginPath()
            context?.move(to: CGPoint(x: xStart, y: y))
            context?.addLine(to: CGPoint(x: xEnd, y: y))
            context?.strokePath()
            context?.restoreGState()

            if hour == hourToRemoveIndex { continue }

            let fontSize = style.font.pointSize
            let timeRect: CGRect = {
                var x: Double
                if rightToLeft {
                    x = bounds.width - 53
                } else {
                    x = 2
                }

                return CGRect(x: x,
                              y: hourFloat * style.verticalDiff + style.verticalInset - 7,
                              width: style.leadingInset - 8,
                              height: fontSize + 2)
            }()

            let timeString = NSString(string: time)
            timeString.draw(in: timeRect, withAttributes: attributes)

            if accentedMinute == 0 {
                continue
            }

            if hour == accentedHour {

                var x: Double
                if UIView.userInterfaceLayoutDirection(for: semanticContentAttribute) == .rightToLeft {
                    x = bounds.width - (style.leadingInset + 7)
                } else {
                    x = 2
                }

                let timeRect = CGRect(x: x, y: hourFloat * style.verticalDiff + style.verticalInset - 7     + style.verticalDiff * (Double(accentedMinute) / 60),
                                      width: style.leadingInset - 8, height: fontSize + 2)

                let timeString = NSString(string: ":\(accentedMinute)")

                timeString.draw(in: timeRect, withAttributes: attributes)
            }
        }
    }

    // MARK: - Layout

    override public func layoutSubviews() {
        super.layoutSubviews()
        recalculateEventLayout()
        layoutEvents()
        layoutNowLine()
        layoutAllDayEvents()
    }

    private func layoutNowLine() {
        if !isToday {
            nowLine.alpha = 0
        } else {
            bringSubviewToFront(nowLine)
            nowLine.alpha = 1
            let size = CGSize(width: bounds.size.width, height: 20)
            let rect = CGRect(origin: CGPoint.zero, size: size)
            nowLine.date = currentTime
            nowLine.frame = rect
            nowLine.center.y = dateToY(currentTime)
        }
    }

    private func layoutEvents() {
        if eventViews.isEmpty { return }

        for (idx, attributes) in regularLayoutAttributes.enumerated() {
            let descriptor = attributes.descriptor
            let eventView = eventViews[idx]
            eventView.frame = attributes.frame

            var x: Double
            if UIView.userInterfaceLayoutDirection(for: semanticContentAttribute) == .rightToLeft {
                x = bounds.width - attributes.frame.minX - attributes.frame.width
            } else {
                x = attributes.frame.minX
            }

            eventView.frame = CGRect(x: x,
                                     y: attributes.frame.minY,
                                     width: attributes.frame.width - style.eventGap,
                                     height: attributes.frame.height - style.eventGap)
            eventView.updateWithDescriptor(event: descriptor)
        }
    }

    private func layoutAllDayEvents() {
        //add day view needs to be in front of the nowLine
        bringSubviewToFront(allDayView)
    }

    /**
     This will keep the allDayView as a stationary view in its superview

     - parameter yValue: since the superview is a scrollView, `yValue` is the
     `contentOffset.y` of the scroll view
     */
    public func offsetAllDayView(by yValue: Double) {
        if let topConstraint = self.allDayViewTopConstraint {
            topConstraint.constant = yValue
            layoutIfNeeded()
        }
    }

    private func recalculateEventLayout() {
        
        // group events by their horizontalLayoutRange value
        let groupedEvents = Dictionary(grouping: regularLayoutAttributes, by: { $0.descriptor.horizontalLayoutRange })
        // calculate layout for each group
        for (_, group) in groupedEvents {
            calculateLayout(for: group)
        }
        
    }

    private func calculateLayout(for group: [EventLayoutAttributes]) {
        guard !group.isEmpty else { return }
        
        // Group events by their horizontalLayoutRange value
        let groupedEvents = Dictionary(grouping: group) { $0.descriptor.horizontalLayoutRange }
        
        for (_, events) in groupedEvents {
            // Sort events by start time, and then by end time (reverse order for end time)
            let sortedEvents = events.sorted {
                $0.descriptor.dateInterval.start < $1.descriptor.dateInterval.start ||
                ($0.descriptor.dateInterval.start == $1.descriptor.dateInterval.start && $0.descriptor.dateInterval.end > $1.descriptor.dateInterval.end)
            }
            
            // Group events into columns
            var columns = [[EventLayoutAttributes]]()
            var previousHighestEndValue: Date? = nil
            var isInserted = false
            
            for event in sortedEvents {
                isInserted = false
                // Check if we need to render a new group of columns
                if let previousEnd = previousHighestEndValue, event.descriptor.dateInterval.start >= previousEnd {
                    // Render events in the previous columns
                    layoutColumns(columns, horizontalRange: event.descriptor.horizontalLayoutRange)
                    // Reset columns
                    columns = []
                    previousHighestEndValue = nil
                }
                
                // Try to insert the event into an existing column
                for i in 0..<columns.count {
                    if let lastEvent = columns[i].last, !collisionDetection(lastEvent.descriptor.dateInterval, event.descriptor.dateInterval) {
                        columns[i].append(event)
                        isInserted = true
                        break
                    }
                }
                
                // If the event does not fit into any existing column, create a new column
                if !isInserted {
                    columns.append([event])
                }
                
                // Update the highest end value
                if previousHighestEndValue == nil || event.descriptor.dateInterval.end > previousHighestEndValue! {
                    previousHighestEndValue = event.descriptor.dateInterval.end
                }
            }
            
            // Layout the last group of columns
            if !columns.isEmpty {
                layoutColumns(columns, horizontalRange: events.first!.descriptor.horizontalLayoutRange)
            }
        }
    }

    private func layoutColumns(_ columns: [[EventLayoutAttributes]], horizontalRange: ClosedRange<CGFloat>) {
        let totalCount = Double(columns.count)
        let adjustedCalendarWidth = calendarWidth * (horizontalRange.upperBound - horizontalRange.lowerBound)
        let leadingInset = style.leadingInset + CGFloat(horizontalRange.lowerBound) * calendarWidth
        
        for (index, column) in columns.enumerated() {
            let columnWidth = adjustedCalendarWidth / totalCount
            let columnOffset = Double(index) * columnWidth + Double(leadingInset)
            
            for event in column {
                let startY = dateToY(event.descriptor.dateInterval.start)
                let endY = dateToY(event.descriptor.dateInterval.end)
                event.frame = CGRect(x: columnOffset, y: startY, width: columnWidth - style.eventGap, height: endY - startY)
            }
        }
        
        // Additional pass to expand events' width
        for column in columns {
            for event in column {
                var frame = event.frame
                let maxX = Double(leadingInset) + adjustedCalendarWidth
                var canExpand = true
                
                while canExpand && frame.maxX < maxX {
                    let testFrame = CGRect(x: frame.origin.x, y: frame.origin.y, width: frame.width + 1, height: frame.height)
                    canExpand = true
                    
                    for otherColumn in columns {
                        for otherEvent in otherColumn {
                            if otherEvent.frame != event.frame && testFrame.intersects(otherEvent.frame) {
                                canExpand = false
                                break
                            }
                        }
                        if !canExpand { break }
                    }
                    
                    if canExpand {
                        frame.size.width += 1
                    }
                }
                
                frame.size.width -= 1
                event.frame = frame
            }
        }
    }

    private func collisionDetection(_ interval1: DateInterval, _ interval2: DateInterval) -> Bool {
        return interval1.end > interval2.start && interval1.start < interval2.end
    }

    private func prepareEventViews() {
        pool.enqueue(views: eventViews)
        eventViews.removeAll()
        for _ in regularLayoutAttributes {
            let newView = pool.dequeue()
            if newView.superview == nil {
                addSubview(newView)
            }
            eventViews.append(newView)
        }
    }

    public func prepareForReuse() {
        pool.enqueue(views: eventViews)
        eventViews.removeAll()
        setNeedsDisplay()
    }

    // MARK: - Helpers

    public func dateToY(_ date: Date) -> Double {
        let provisionedDate = date.dateOnly(calendar: calendar)
        let timelineDate = self.date.dateOnly(calendar: calendar)
        var dayOffset: Double = 0
        if provisionedDate > timelineDate {
            // Event ending the next day
            dayOffset += 1
        } else if provisionedDate < timelineDate {
            // Event starting the previous day
            dayOffset -= 1
        }
        let fullTimelineHeight = 24 * style.verticalDiff
        let hour = component(component: .hour, from: date)
        let minute = component(component: .minute, from: date)
        let hourY = Double(hour) * style.verticalDiff + style.verticalInset
        let minuteY = Double(minute) * style.verticalDiff / 60
        return hourY + minuteY + fullTimelineHeight * dayOffset
    }

    public func yToDate(_ y: Double) -> Date {
        let timeValue = y - style.verticalInset
        var hour = Int(timeValue / style.verticalDiff)
        let fullHourPoints = Double(hour) * style.verticalDiff
        let minuteDiff = timeValue - fullHourPoints
        let minute = Int(minuteDiff / style.verticalDiff * 60)
        var dayOffset = 0
        if hour > 23 {
            dayOffset += 1
            hour -= 24
        } else if hour < 0 {
            dayOffset -= 1
            hour += 24
        }
        let offsetDate = calendar.date(byAdding: DateComponents(day: dayOffset),
                                       to: date)!
        let newDate = calendar.date(bySettingHour: hour,
                                    minute: minute.clamped(to: 0...59),
                                    second: 0,
                                    of: offsetDate)
        return newDate!
    }

    private func component(component: Calendar.Component, from date: Date) -> Int {
        calendar.component(component, from: date)
    }

    private func getDateInterval(date: Date) -> DateInterval {
        let earliestEventMintues = component(component: .minute, from: date)
        let splitMinuteInterval = style.splitMinuteInterval
        let minute = component(component: .minute, from: date)
        let minuteRange = (minute / splitMinuteInterval) * splitMinuteInterval
        let beginningRange = calendar.date(byAdding: .minute, value: -(earliestEventMintues - minuteRange), to: date)!
        let endRange = calendar.date(byAdding: .minute, value: splitMinuteInterval, to: beginningRange)!
        return DateInterval(start: beginningRange, end: endRange)
    }
}
