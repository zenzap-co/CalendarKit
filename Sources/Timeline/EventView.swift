import UIKit

open class EventView: UIView {
    public var descriptor: EventDescriptor?
    public var color = SystemColors.label
    
    public var contentHeight: Double {
        textView.frame.height
    }
    
    public private(set) lazy var backgroundView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 4
        view.layer.masksToBounds = true
        return view
    }()
    
    public private(set) lazy var textView: MultilineTopAlignedLabel = {
        let view = MultilineTopAlignedLabel()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }()
    
    /// Resize Handle views showing up when editing the event.
    /// The top handle has a tag of `0` and the bottom has a tag of `1`
    public private(set) lazy var eventResizeHandles = [EventResizeHandleView(), EventResizeHandleView()]
    
    override public init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }
    
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        configure()
    }
    
    private func configure() {
        clipsToBounds = false
        color = tintColor
        addSubview(backgroundView)
        addSubview(textView)
        
        for (idx, handle) in eventResizeHandles.enumerated() {
            handle.tag = idx
            addSubview(handle)
        }
        
    }
    
    public func updateWithDescriptor(event: EventDescriptor) {
        if let attributedText = event.attributedText {
            textView.label.attributedText = attributedText
        } else {
            textView.label.text = event.text
            textView.label.textColor = event.textColor
            textView.label.font = event.font
        }
        if let lineBreakMode = event.lineBreakMode {
            textView.label.lineBreakMode = lineBreakMode
        }
        descriptor = event
        backgroundView.layer.backgroundColor = event.backgroundColor.cgColor
        backgroundView.layer.borderWidth = 1
        backgroundView.layer.borderColor = event.color.cgColor
        
        color = event.color
        eventResizeHandles.forEach{
            $0.borderColor = event.color
            $0.isHidden = event.editedEvent == nil || event.editingCanChangeDuration == false
        }
        drawsShadow = event.editedEvent != nil
        setNeedsDisplay()
        setNeedsLayout()
    }
    
    public func animateCreation() {
        transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        func scaleAnimation() {
            transform = .identity
        }
        UIView.animate(withDuration: 0.2,
                       delay: 0,
                       usingSpringWithDamping: 0.2,
                       initialSpringVelocity: 10,
                       options: [],
                       animations: scaleAnimation,
                       completion: nil)
    }
    
    /**
     Custom implementation of the hitTest method is needed for the tap gesture recognizers
     located in the ResizeHandleView to work.
     Since the ResizeHandleView could be outside of the EventView's bounds, the touches to the ResizeHandleView
     are ignored.
     In the custom implementation the method is recursively invoked for all of the subviews,
     regardless of their position in relation to the Timeline's bounds.
     */
    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        for resizeHandle in eventResizeHandles {
            if let subSubView = resizeHandle.hitTest(convert(point, to: resizeHandle), with: event) {
                return subSubView
            }
        }
        return super.hitTest(point, with: event)
    }
    
    private var drawsShadow = false
    
    override open func layoutSubviews() {
        super.layoutSubviews()
        backgroundView.frame = bounds
        textView.frame = {
            if UIView.userInterfaceLayoutDirection(for: semanticContentAttribute) == .rightToLeft {
                return CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width - 3, height: bounds.height)
            } else {
                return CGRect(x: bounds.minX + 3, y: bounds.minY, width: bounds.width - 3, height: bounds.height)
            }
        }()
        if frame.minY < 0 {
            var textFrame = textView.frame;
            textFrame.origin.y = frame.minY * -1;
            textFrame.size.height += frame.minY;
            textView.frame = textFrame;
        }
        let first = eventResizeHandles.first
        let last = eventResizeHandles.last
        let radius: Double = 40
        let yPad: Double =  -radius / 2
        let width = bounds.width
        let height = bounds.height
        let size = CGSize(width: radius, height: radius)
        first?.frame = CGRect(origin: CGPoint(x: width - radius - layoutMargins.right, y: yPad),
                              size: size)
        last?.frame = CGRect(origin: CGPoint(x: layoutMargins.left, y: height - yPad - radius),
                             size: size)
        
        if drawsShadow {
            applySketchShadow(alpha: 0.13,
                              blur: 10)
        }
    }
    
    private func applySketchShadow(
        color: UIColor = .black,
        alpha: Float = 0.5,
        x: Double = 0,
        y: Double = 2,
        blur: Double = 4,
        spread: Double = 0)
    {
        layer.shadowColor = color.cgColor
        layer.shadowOpacity = alpha
        layer.shadowOffset = CGSize(width: x, height: y)
        layer.shadowRadius = blur / 2.0
        if spread == 0 {
            layer.shadowPath = nil
        } else {
            let dx = -spread
            let rect = bounds.insetBy(dx: dx, dy: dx)
            layer.shadowPath = UIBezierPath(rect: rect).cgPath
        }
    }
}

public class MultilineTopAlignedLabel: UIView {
     let label = UILabel()
    
    init() {
        super.init(frame: .zero)
        
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(label)
        
        let minimizer = label.bottomAnchor.constraint(equalTo: topAnchor)
        minimizer.priority = .defaultLow
        
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
            minimizer
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
