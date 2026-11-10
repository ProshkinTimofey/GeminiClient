import UIKit

public final class SlideOverDrawerController: UIViewController {

    private let mainViewController: UIViewController
    private let sidebarViewController: HistorySidebarViewController

    private lazy var drawerWidth: CGFloat = min(260.0, UIScreen.main.bounds.width * 0.8)

    private var isSidebarOpen: Bool = false
    private var sidebarLeadingConstraint: NSLayoutConstraint!

    private lazy var dimmingView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        view.alpha = 0.0
        view.translatesAutoresizingMaskIntoConstraints = false
        let tap = UITapGestureRecognizer(target: self, action: #selector(closeSidebar))
        view.addGestureRecognizer(tap)
        return view
    }()

    public init(mainViewController: UIViewController, sidebarViewController: HistorySidebarViewController) {
        self.mainViewController = mainViewController
        self.sidebarViewController = sidebarViewController
        super.init(nibName: nil, bundle: nil)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        addChild(mainViewController)
        view.addSubview(mainViewController.view)
        mainViewController.view.frame = view.bounds
        mainViewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mainViewController.didMove(toParent: self)

        view.addSubview(dimmingView)
        NSLayoutConstraint.activate([
            dimmingView.topAnchor.constraint(equalTo: view.topAnchor),
            dimmingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            dimmingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimmingView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        addChild(sidebarViewController)
        view.addSubview(sidebarViewController.view)
        sidebarViewController.view.translatesAutoresizingMaskIntoConstraints = false

        sidebarLeadingConstraint = sidebarViewController.view.leadingAnchor.constraint(
            equalTo: view.leadingAnchor,
            constant: -drawerWidth
        )

        NSLayoutConstraint.activate([
            sidebarLeadingConstraint,
            sidebarViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            sidebarViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sidebarViewController.view.widthAnchor.constraint(equalToConstant: drawerWidth)
        ])
        sidebarViewController.didMove(toParent: self)

        let edgePan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        view.addGestureRecognizer(edgePan)
    }

    @objc public func toggleSidebar() {
        if isSidebarOpen {
            closeSidebar()
        } else {
            openSidebar()
        }
    }

    @objc public func openSidebar() {
        isSidebarOpen = true
        sidebarLeadingConstraint.constant = 0
        sidebarViewController.loadHistory()

        UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseOut]) {
            self.dimmingView.alpha = 1.0
            self.view.layoutIfNeeded()
        }
    }

    @objc public func closeSidebar() {
        isSidebarOpen = false
        sidebarLeadingConstraint.constant = -drawerWidth

        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseIn]) {
            self.dimmingView.alpha = 0.0
            self.view.layoutIfNeeded()
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)

        switch gesture.state {
        case .changed:
            if !isSidebarOpen && translation.x > 0 {
                let offset = min(translation.x - drawerWidth, 0)
                sidebarLeadingConstraint.constant = offset
                dimmingView.alpha = (offset + drawerWidth) / drawerWidth
                view.layoutIfNeeded()
            } else if isSidebarOpen && translation.x < 0 {
                let offset = max(translation.x, -drawerWidth)
                sidebarLeadingConstraint.constant = offset
                dimmingView.alpha = (offset + drawerWidth) / drawerWidth
                view.layoutIfNeeded()
            }
        case .ended, .cancelled:
            if sidebarLeadingConstraint.constant > -drawerWidth / 2 {
                openSidebar()
            } else {
                closeSidebar()
            }
        default:
            break
        }
    }
}
