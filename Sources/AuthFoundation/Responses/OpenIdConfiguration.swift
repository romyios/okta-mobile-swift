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

public struct OpenIdConfiguration: Decodable, JSONDecodable {
    public let authorizationEndpoint: URL
    public let endSessionEndpoint: URL
    public let introspectionEndpoint: URL
    public let issuer: URL
    public let jwksUri: URL
    public let registrationEndpoint: URL
    public let revocationEndpoint: URL
    public let tokenEndpoint: URL
    public let userinfoEndpoint: URL
    public let claimsSupported: [Claim]
    public let grantTypesSupported: [GrantType]
    
    public subscript(key: String) -> [String]? {
        additionalStingArrayValues[key]
    }
    
    public static let jsonDecoder: JSONDecoder = {
        let result = JSONDecoder()
        result.keyDecodingStrategy = .convertFromSnakeCase
        return result
    }()
    
    private let additionalStingArrayValues: [String:[String]]
    
    enum CodingKeys: CodingKey {
        case url(_ key: String)
        case claimArray(_ key: String)
        case grantTypeArray(_ key: String)
        case other(_ key: String)

        public typealias RawValue = String

        init?(stringValue rawValue: String) {
            switch rawValue {
            case "authorizationEndpoint", "endSessionEndpoint", "introspectionEndpoint", "issuer", "jwksUri", "registrationEndpoint", "revocationEndpoint", "tokenEndpoint", "userinfoEndpoint":
                self = .url(rawValue)
            case "claimsSupported":
                self = .claimArray(rawValue)
            case "grantTypesSupported":
                self = .grantTypeArray(rawValue)
            default:
                self = .other(rawValue)
            }
        }
        init?(intValue: Int) { return nil }

        var intValue: Int? { nil }
        var stringValue: String {
            switch self {
            case .url(let key):
                return key
            case .claimArray(let key):
                return key
            case .grantTypeArray(let key):
                return key
            case .other(let key):
                return key
            }
        }
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        authorizationEndpoint = try container.decode(URL.self, forKey: .url("authorizationEndpoint"))
        endSessionEndpoint = try container.decode(URL.self, forKey: .url("endSessionEndpoint"))
        introspectionEndpoint = try container.decode(URL.self, forKey: .url("introspectionEndpoint"))
        issuer = try container.decode(URL.self, forKey: .url("issuer"))
        jwksUri = try container.decode(URL.self, forKey: .url("jwksUri"))
        registrationEndpoint = try container.decode(URL.self, forKey: .url("registrationEndpoint"))
        revocationEndpoint = try container.decode(URL.self, forKey: .url("revocationEndpoint"))
        tokenEndpoint = try container.decode(URL.self, forKey: .url("tokenEndpoint"))
        userinfoEndpoint = try container.decode(URL.self, forKey: .url("userinfoEndpoint"))
        
        claimsSupported = try container.decode([Claim].self, forKey: .claimArray("claimsSupported"))
        grantTypesSupported = try container.decode([GrantType].self, forKey: .grantTypeArray("grantTypesSupported"))

        additionalStingArrayValues = container.allKeys.reduce(into: [:]) { partialResult, key in
            guard let values = try? container.decodeIfPresent([String].self, forKey: key) else { return }
            partialResult[key.stringValue] = values
        }
    }
}