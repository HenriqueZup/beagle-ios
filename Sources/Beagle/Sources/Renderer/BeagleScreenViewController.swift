/*
 * Copyright 2020 ZUP IT SERVICOS EM TECNOLOGIA E INOVACAO SA
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import UIKit

public typealias BeagleController = UIViewController & BeagleControllerProtocol

public protocol BeagleControllerProtocol: NSObjectProtocol {
    var serverDrivenState: ServerDrivenState { get set }
    var screenType: ScreenType { get }
    var screen: Screen? { get }
    
    func setIdentifier(_ id: String?, in view: UIView)
    func setContext(_ context: Context, in view: UIView)
    
    func addOnInit(_ onInit: [Action], in view: UIView)
    func addBinding<T: Decodable>(expression: ContextExpression, in view: UIView, update: @escaping (T?) -> Void)
    
    func execute(actions: [Action]?, event: String?, origin: UIView)
    func execute(actions: [Action]?, with contextId: String, and contextValue: DynamicObject, origin: UIView)
    
    func setNeedsLayout(component: UIView)
}

public class BeagleScreenViewController: BeagleController {
    
    private let viewModel: BeagleScreenViewModel
    
    var content: Content? {
        willSet { content?.remove() }
        didSet { content?.add(to: self) }
    }
    
    lazy var layoutManager = LayoutManager(self)
    
    lazy var renderer = CurrentEnviroment.renderer(self)
    
    let bindings = Bindings()
    
    private var onInit: [(UIView, [Action])] = []
    
    private var navigationControllerId: String?
    
    // TODO: This workaround should be removed in BeagleView future implementation
    var skipNavigationCreation = false
    
    // MARK: - Dependencies
    
    @Injected var navigator: NavigationProtocolInternal
    
    // MARK: - Init
    
    @discardableResult
    static func remote(
        _ remote: ScreenType.Remote,
        viewClient: ViewClientProtocol,
        completion: @escaping (Result<BeagleScreenViewController, Request.Error>) -> Void
    ) -> RequestToken? {
        return BeagleScreenViewModel.remote(remote, viewClient: viewClient) {
            completion($0.map { viewModel in
                return self.init(viewModel: viewModel)
            })
        }
    }
    
    public convenience init(_ remote: ScreenType.Remote, controllerId: String? = nil) {
        self.init(viewModel: .init(screenType: .remote(remote)), controllerId: controllerId)
        self.navigationControllerId = controllerId
    }
    
    public convenience init(_ json: String, controllerId: String? = nil) {
        self.init(viewModel: .init(screenType: .declarativeText(json)), controllerId: controllerId)
        self.navigationControllerId = controllerId
    }
    
    convenience init(_ component: ServerDrivenComponent, controllerId: String? = nil) {
        self.init(viewModel: .init(screenType: .declarative(component.toScreen())), controllerId: controllerId)
        self.navigationControllerId = controllerId
    }
    
    required init(viewModel: BeagleScreenViewModel, controllerId: String? = nil) {
        self.viewModel = viewModel
        self.navigationControllerId = controllerId
        super.init(nibName: nil, bundle: nil)
        extendedLayoutIncludesOpaqueBars = true
        automaticallyAdjustsScrollViewInsets = false
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - BeagleControllerProtocol

    public var serverDrivenState: ServerDrivenState = .finished {
        didSet {
            notifyBeagleNavigation(state: serverDrivenState)
            loadBeagleViewState(serverDrivenState)
        }
    }
        
    public var screenType: ScreenType {
        return viewModel.screenType
    }
    
    public var screen: Screen? {
        return viewModel.screen
    }
    
    public func addOnInit(_ onInit: [Action], in view: UIView) {
        self.onInit.append((view, onInit))
    }
    
    public func addBinding<T: Decodable>(expression: ContextExpression, in view: UIView, update: @escaping (T?) -> Void) {
        bindings.add(self, expression, view, update)
    }
    
    public func execute(actions: [Action]?, event: String?, origin: UIView) {
        actions?.forEach {
            AnalyticsService.shared?.createRecord(action: .init(action: $0, event: event, origin: origin, controller: self))
            $0.execute(controller: self, origin: origin)
        }
    }
    
    public func execute(actions: [Action]?, with contextId: String, and contextValue: DynamicObject, origin: UIView) {
        guard let actions = actions else { return }
        let context = Context(id: contextId, value: contextValue)
        origin.setContext(context)
        execute(actions: actions, event: contextId, origin: origin)
    }
            
    // MARK: - Lifecycle
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        initView()
        createContent()
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateNavigationBar(animated: animated)
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if case .view = content {
            viewModel.trackEventOnScreenAppeared()
        }
    }
    
    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if case .view = content {
            viewModel.trackEventOnScreenDisappeared()
        }
    }
    
    public override func viewDidLayoutSubviews() {
        executeOnInit()
        bindings.config()
        layoutManager.applyLayout()
        super.viewDidLayoutSubviews()
    }
    
    private func executeOnInit() {
        for (view, actions) in onInit {
            execute(actions: actions, event: "onInit", origin: view)
        }
        onInit.removeAll()
    }
    
    private func createContent() {
        if navigationController == nil && !skipNavigationCreation {
            createNavigationContent()
            return
        }
        viewModel.stateObserver = self
        viewModel.loadScreen()
    }
    
    private func createNavigationContent() {
        let navigation = navigator.navigationController(forId: navigationControllerId)
        navigation.viewControllers = [BeagleScreenViewController(viewModel: viewModel)]
        content = .navigation(navigation)
    }
    
    private func updateNavigationBar(animated: Bool) {
        guard let screen = screen, !skipNavigationCreation else { return }
        let screenNavigationBar = screen.navigationBar
        let hideNavBar = screenNavigationBar == nil
        navigationController?.setNavigationBarHidden(hideNavBar, animated: animated)
        
        navigationItem.title = screen.navigationBar?.title
        navigationItem.backBarButtonItem = UIBarButtonItem(title: nil, style: .plain, target: nil, action: nil)
        navigationItem.hidesBackButton = !(screen.navigationBar?.showBackButton ?? true)
        ViewConfigurator.applyAccessibility(screenNavigationBar?.backButtonAccessibility, to: navigationItem)
        
        navigationItem.rightBarButtonItems = screenNavigationBar?.navigationBarItems?.reversed().map {
            $0.toBarButtonItem(controller: self)
        }
        
        if let style = screen.navigationBar?.styleId,
        let navigationBar = navigationController?.navigationBar {
            navigationBar.beagle.applyStyle(for: navigationBar as UINavigationBar, styleId: style, with: self)
        }
    }
    
    // MARK: - Update View
    
    fileprivate func updateView(state: ServerDrivenState) {
        switch state {
        case .started:
            serverDrivenState = .started
        case .finished:
            serverDrivenState = .finished
        case .success:
            serverDrivenState = .success
            serverDrivenState = .finished
            renderScreenIfNeeded()
        case .error(let error, _):
            renderScreenIfNeeded()
            serverDrivenState = .error(error, viewModel.loadScreen)
            serverDrivenState = .finished
        }
    }
    
    private func renderScreenIfNeeded() {
        if content == nil, let screen = screen {
            updateNavigationBar(animated: true)
            content = .view(renderer.render(screen))
        }
    }
    
    private func loadBeagleViewState(_ state: ServerDrivenState) {
        guard let beagleViewState = viewModel.beagleViewStateObserver else { return }
        beagleViewState(state)
    }

    public func reloadScreen(with screenType: ScreenType) {
        content = nil
        viewModel.screenType = screenType
        createContent()
    }
    
    public func hasServerDrivenScreen() -> Bool {
        return screen != nil
    }
    
    // MARK: - View Setup
    
    private func initView() {
        if #available(iOS 13.0, *) {
            view.backgroundColor = UIColor.systemBackground
        } else {
            view.backgroundColor = .white
        }
        view.setContext(Context(id: NavigationContext.id, value: nil))
        updateView(state: viewModel.state)
    }
    
    private func notifyBeagleNavigation(state: ServerDrivenState) {
        (navigationController as? BeagleNavigationController)?.serverDrivenStateDidChange(to: state, at: self)
    }
}

extension BeagleControllerProtocol {
    public func setIdentifier(_ id: String?, in view: UIView) {
        CurrentEnviroment.viewConfigurator(view).setup(id: id)
    }
    
    public func setContext(_ context: Context, in view: UIView) {
        view.setContext(context)
    }
}

extension BeagleControllerProtocol where Self: UIViewController {
    public func setNeedsLayout(component: UIView) {
        CurrentEnviroment.style(component).markDirty()
        if let beagleView = view.superview as? BeagleView {
            beagleView.invalidateIntrinsicContentSize()
        }
        viewIfLoaded?.setNeedsLayout()
    }
}

// MARK: - Observer

extension BeagleScreenViewController: BeagleScreenStateObserver {
    func didChangeState(_ state: ServerDrivenState) {
        updateView(state: state)
    }
}

extension BeagleScreenViewController {
    enum Content {
        case navigation(BeagleNavigationController)
        case view(UIView)
    }
}

extension BeagleScreenViewController.Content {
    func add(to host: BeagleScreenViewController) {
        switch self {
        case .navigation(let controller):
            host.addChild(controller)
            host.view.addSubview(controller.view)
            controller.view.anchorTo(superview: host.view)
            controller.didMove(toParent: host)
        case .view(let view):
            host.view.addSubview(view)
            view.anchorTo(superview: host.view)
            host.view.setNeedsLayout()
            host.view.superview?.invalidateIntrinsicContentSize()
        }
    }
    
    func remove() {
        switch self {
        case .navigation(let controller):
            controller.willMove(toParent: nil)
            controller.view.removeFromSuperview()
            controller.removeFromParent()
        case .view(let view):
            view.removeFromSuperview()
        }
    }
}
