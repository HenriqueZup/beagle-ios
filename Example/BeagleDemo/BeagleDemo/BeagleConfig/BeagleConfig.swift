/*
 * Copyright 2020, 2022 ZUP IT SERVICOS EM TECNOLOGIA E INOVACAO SA
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

import Foundation
import Beagle

class BeagleConfig {

    private init() {  }

    static func start() {
        let deepLinkHandler = registerDeepLink()

        var dependencies = BeagleDependencies()
        dependencies.networkClient = NetworkClientDefault()
        dependencies.theme = AppTheme.theme
        dependencies.urlBuilder = UrlBuilder(baseUrl: URL(string: .baseURL))
        dependencies.deepLinkHandler = deepLinkHandler

        dependencies.analyticsProvider = AnalyticsProviderDemo()

        registerCustomOperations(in: dependencies)
        registerCustomComponents(in: dependencies)
        setupNavigation(in: dependencies)

        BeagleConfigurator.setup(dependencies: dependencies)
    }

    private static func registerDeepLink() -> DeeplinkScreenManager {
        let deepLink = DeeplinkScreenManager.shared
        return deepLink
    }

    private static func registerCustomComponents(in dependencies: BeagleDependencies) {
        dependencies.coder.register(type: DSCollection.self)
    }

    private static func setupNavigation(in dependencies: BeagleDependencies) {
        dependencies.navigator.registerNavigationController(builder: CustomBeagleNavigationController.init, forId: "CustomBeagleNavigation")
        dependencies.navigator.registerNavigationController(builder: CustomPushStackNavigationController.init, forId: "PushStackNavigation")
        dependencies.navigator.setDefaultAnimation(.init(
            pushTransition: .init(type: .fade, subtype: .fromRight, duration: 0.1),
            modalPresentationStyle: .formSheet
        ))
    }
    
    private static func registerCustomOperations(in dependencies: BeagleDependencies) {
        dependencies.operationsProvider.register(operationId: "sum") { parameters in
            let anyParameters = parameters.map { $0.asAny() }
            if let integerParameters = anyParameters as? [Int] {
                return .int(integerParameters.reduce(0, +))
            } else if let doubleParameters = anyParameters as? [Double] {
                return .double(doubleParameters.reduce(0.0, +))
            }
            return nil
        }
        
        dependencies.operationsProvider.register(operationId: "SUBTRACT") { parameters in
            let anyParameters = parameters.map { $0.asAny() }
            if let integerParameters = anyParameters as? [Int] {
                return .int(integerParameters.reduce(integerParameters[0] * 2, -))
            } else if let doubleParameters = anyParameters as? [Double] {
                return .double(doubleParameters.reduce(doubleParameters[0] * 2, -))
            }
            return nil
        }
    }
}
