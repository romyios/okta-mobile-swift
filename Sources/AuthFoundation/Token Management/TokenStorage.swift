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

import Foundation

/// Protocol used to customize the way tokens are stored, updated, and removed throughout the lifecycle of an application.
///
/// A default implementation is provided, but for advanced use-cases, you may implement this protocol yourself and assign an instance to the ``User/tokenStorage`` property.
///
/// > Warning: When implementing a custom token storage class, it's vitally important that you do not directly invoke any of these methods yourself. These methods are intended to be called on-demand by the other AuthFoundation classes, and the behavior is undefined if these methods are called directly by the developer.
public protocol TokenStorage {
    /// Mandatory delegate property that is used to communicate changes to the token store to the rest of the user management system.
    var delegate: TokenStorageDelegate? { get set }
    
    /// Accessor for defining which token shall be the default.
    ///
    /// > Note: Setting a new token should implicitly invoke ``add(token:)`` if the token doesn't previously exist within storage.
    /// >
    /// > The ``TokenStorageDelegate/token(storage:defaultChanged:)`` method should also be invoked.
    var defaultToken: Token? { get set }

    /// Returns all tokens currently in storage.
    var allTokens: [Token] { get }
    
    /// Determines whether or not the given token is stored.
    func contains(token: Token) -> Bool

    /// Adds the given token.
    ///
    /// This should avoid adding duplicate tokens. If the new token is semantically the same as another token already within storage, but some other value (such as refresh token or expiration time) may have changed, this method should update the underlying data store with the refreshed value.
    ///
    /// > Note: This method should invoke the relevant datasource method, either calling ``TokenStorageDelegate/token(storage:added:)`` or ``TokenStorageDelegate/token(storage:updated:)``.
    func add(token: Token) throws
    
    /// Removes the given token.
    ///
    /// > Note: This method should invoke the  ``TokenStorageDelegate/token(storage:removed:)`` method.
    func remove(token: Token) throws
}

public protocol TokenStorageDelegate: AnyObject {
    func token(storage: TokenStorage, defaultChanged token: Token?)
    func token(storage: TokenStorage, added token: Token?)
    func token(storage: TokenStorage, removed token: Token?)
    func token(storage: TokenStorage, updated token: Token?)
}