//
// Copyright (c) 2021-Present, Okta, Inc. and/or its affiliates. All rights reserved.
// The Okta software accompanied by this notice is provided pursuant to the Apache License, Version 2.0 (the "License.")
//
// You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0.
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
// WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//
// See the License for the specific language governing permissions and limitations under the License.
//

import XCTest
@testable import TestCommon
@testable import AuthFoundation
@testable import OktaOAuth2

class DeviceAuthorizationFlowDelegateRecorder: DeviceAuthorizationFlowDelegate {
    var context: DeviceAuthorizationFlow.Context?
    var token: Token?
    var error: OAuth2Error?
    var url: URL?
    var started = false
    var finished = false
    
    func authenticationStarted<Flow: DeviceAuthorizationFlow>(flow: Flow) {
        started = true
    }
    
    func authenticationFinished<Flow: DeviceAuthorizationFlow>(flow: Flow) {
        finished = true
    }

    func authentication<Flow>(flow: Flow, received context: DeviceAuthorizationFlow.Context) {
        self.context = context
    }
    
    func authentication<Flow>(flow: Flow, received token: Token) {
        self.token = token
    }
    
    func authentication<Flow>(flow: Flow, received error: OAuth2Error) {
        self.error = error
    }

    func authentication<Flow: DeviceAuthorizationFlow>(flow: Flow, customizeUrl urlComponents: inout URLComponents) {
        urlComponents.fragment = "customizedUrl"
    }
    
    func authentication<Flow: DeviceAuthorizationFlow>(flow: Flow, shouldAuthenticateUsing url: URL) {
        self.url = url
    }
}

final class DeviceAuthorizationFlowSuccessTests: XCTestCase {
    let issuer = URL(string: "https://example.com")!
    let clientMock = OAuth2ClientMock()
    var configuration: DeviceAuthorizationFlow.Configuration!
    let urlSession = URLSessionMock()
    var client: OAuth2Client!
    var flow: DeviceAuthorizationFlow!

    override func setUpWithError() throws {
        configuration = DeviceAuthorizationFlow.Configuration(clientId: "clientId",
                                                            scopes: "openid profile")
        client = OAuth2Client(baseURL: issuer, session: urlSession)
        
        urlSession.expect("https://example.com/oauth2/default/v1/device/authorize",
                          data: try data(for: "device-authorize", in: "MockResponses"),
                          contentType: "application/json")
        urlSession.expect("https://example.com/oauth2/default/v1/token",
                          data: try data(for: "token", in: "MockResponses"),
                          contentType: "application/json")
        flow = DeviceAuthorizationFlow(configuration, client: client)
    }
    
    func testWithDelegate() throws {
        let delegate = DeviceAuthorizationFlowDelegateRecorder()
        flow.add(delegate: delegate)

        // Ensure the initial state
        XCTAssertNil(flow.context)
        XCTAssertFalse(flow.isAuthenticating)
        XCTAssertFalse(delegate.started)
        
        // Begin
        flow.resume()
        XCTAssertNotNil(delegate.context)
        XCTAssertEqual(flow.context, delegate.context)
        XCTAssertTrue(flow.isAuthenticating)
        XCTAssertEqual(delegate.context?.verificationUri.absoluteString, "https://example.okta.com/activate")
        XCTAssertTrue(delegate.started)
        
        // Exchange code
        let expect = expectation(description: "Wait for timer")
        flow.resume(with: delegate.context!) { _ in
            expect.fulfill()
        }
        waitForExpectations(timeout: 5) { error in
            XCTAssertNil(error)
        }
        XCTAssertNil(flow.context)
        XCTAssertFalse(flow.isAuthenticating)
        XCTAssertNotNil(delegate.token)
        XCTAssertTrue(delegate.finished)
    }

    func testWithBlocks() throws {
        // Ensure the initial state
        XCTAssertNil(flow.context)
        XCTAssertFalse(flow.isAuthenticating)

        // Begin
        var wait = expectation(description: "resume")
        var context: DeviceAuthorizationFlow.Context?
        flow.resume { result in
            switch result {
            case .success(let response):
                context = response
            case .failure(let error):
                XCTAssertNil(error)
            }
            wait.fulfill()
        }
        waitForExpectations(timeout: 1) { error in
            XCTAssertNil(error)
        }
        
        XCTAssertEqual(flow.context?.deviceCode, context?.deviceCode)
        XCTAssertTrue(flow.isAuthenticating)
        XCTAssertNotNil(flow.context?.verificationUri)
        XCTAssertEqual(context, flow.context)
        XCTAssertEqual(flow.context?.verificationUri.absoluteString, "https://example.okta.com/activate")

        // Exchange code
        var token: Token?
        wait = expectation(description: "resume")
        flow.resume(with: context!) { result in
            switch result {
            case .success(let resultToken):
                token = resultToken
            case .failure(let error):
                XCTAssertNil(error)
            }
            wait.fulfill()
        }
        waitForExpectations(timeout: 2) { error in
            XCTAssertNil(error)
        }

        XCTAssertNil(flow.context)
        XCTAssertFalse(flow.isAuthenticating)
        XCTAssertNotNil(token)
    }

    #if swift(>=5.5.1) && !os(Linux)
    @available(iOS 15.0, tvOS 15.0, macOS 12.0, *)
    func testWithAsync() async throws {
        // Ensure the initial state
        XCTAssertNil(flow.context)
        XCTAssertFalse(flow.isAuthenticating)

        // Begin
        let context = try await flow.resume()

        XCTAssertEqual(flow.context, context)
        XCTAssertTrue(flow.isAuthenticating)
        XCTAssertEqual(context, flow.context)
        XCTAssertEqual(flow.context?.verificationUri.absoluteString, "https://example.okta.com/activate")

        // Exchange code
        let token = try await flow.resume(with: context)

        XCTAssertNil(flow.context)
        XCTAssertFalse(flow.isAuthenticating)
        XCTAssertNotNil(token)
    }
    #endif
}
