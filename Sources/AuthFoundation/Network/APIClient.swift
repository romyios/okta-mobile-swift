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

public protocol APIClient {
    var baseURL: URL { get }
    var session: URLSessionProtocol { get }
    var additionalHttpHeaders: [String:String]? { get }
    var requestIdHeader: String? { get }
    var userAgent: String { get }

    func decode<T: Decodable>(_ type: T.Type, from data: Data, userInfo: [CodingUserInfoKey:Any]?) throws -> T
    func error(from data: Data) -> Error?

    func willSend(request: inout URLRequest)
    func didSend<T>(request: URLRequest, received response: APIResponse<T>)

    func send<T: Decodable>(_ request: URLRequest, completion: @escaping (Result<APIResponse<T>, APIClientError>) -> Void)

    #if swift(>=5.5.1) && !os(Linux)
    @available(iOS 15.0, tvOS 15.0, macOS 12.0, *)
    func send<T: Decodable>(_ request: URLRequest) async throws -> APIResponse<T>
    #endif
}

public protocol APIClientDelegate: AnyObject {
    func api(client: APIClient, willSend request: inout URLRequest)
    func api(client: APIClient, didSend request: URLRequest, received error: APIClientError)
    func api<T>(client: APIClient, didSend request: URLRequest, received response: APIResponse<T>)
}

extension APIClientDelegate {
    public func api(client: APIClient, willSend request: inout URLRequest) {}
    public func api(client: APIClient, didSend request: URLRequest, received error: APIClientError) {}
    public func api<T>(client: APIClient, didSend request: URLRequest, received response: APIResponse<T>) {}
}

extension APIClient {
    public var additionalHttpHeaders: [String:String]? { nil }
    public var requestIdHeader: String? { "x-okta-request-id" }
    public var userAgent: String { SDKVersion.userAgent }
    
    public func decode<T>(_ type: T.Type, from data: Data, userInfo: [CodingUserInfoKey:Any]? = nil) throws -> T where T: Decodable {
        var info: [CodingUserInfoKey:Any] = userInfo ?? [:]
        info[.baseURL] = baseURL
        
        let jsonDecoder: JSONDecoder
        if let jsonType = type as? JSONDecodable.Type {
            jsonDecoder = jsonType.jsonDecoder
        } else {
            jsonDecoder = defaultJSONDecoder
        }
        
        jsonDecoder.userInfo = info
        
        return try jsonDecoder.decode(type, from: data)
    }
    
    public func error(from data: Data) -> Error? {
        defaultJSONDecoder.userInfo = [:]
        return try? defaultJSONDecoder.decode(OktaAPIError.self, from: data)
    }

    public func willSend(request: inout URLRequest) {}
    
    public func didSend(request: URLRequest, received error: APIClientError) {}

    public func didSend<T>(request: URLRequest, received response: APIResponse<T>) {}

    public func send<T: Decodable>(_ request: URLRequest, completion: @escaping (Result<APIResponse<T>, APIClientError>) -> Void) where T : Decodable {
        var urlRequest = request
        
        willSend(request: &urlRequest)
        session.dataTaskWithRequest(urlRequest) { data, response, httpError in
            guard let data = data,
                  let response = response
            else {
                let apiError: APIClientError
                if let error = httpError {
                    apiError = .serverError(error)
                } else {
                    apiError = .missingResponse
                }
                
                completion(.failure(apiError))
                return
            }

            do {
                let response: APIResponse<T> = try self.validate(data, response)
                self.didSend(request: request, received: response)
                
                completion(.success(response))
            } catch {
                let apiError = error as? APIClientError ?? .cannotParseResponse(error: error)
                self.didSend(request: request, received: apiError)
                completion(.failure(apiError))
            }
        }.resume()
    }
    
    public func send<T: Decodable>(_ request: APIRequest, completion: @escaping (Result<APIResponse<T>, APIClientError>) -> Void) where T : Decodable {
        do {
            let urlRequest = try request.request(for: self)
            send(urlRequest, completion: completion)
        } catch {
            completion(.failure(.serverError(error)))
        }
    }

    #if swift(>=5.5.1) && !os(Linux)
    @available(iOS 15.0, tvOS 15.0, macOS 12.0, *)
    public func send<T: Decodable>(_ request: URLRequest) async throws -> APIResponse<T> {
        var urlRequest = request
        willSend(request: &urlRequest)

        let (data, response) = try await session.data(for: urlRequest, delegate: nil)
        let result: APIResponse<T>
        do {
            result = try validate(data, response)
            self.didSend(request: request, received: result)
        } catch {
            let apiError = error as? APIClientError ?? .cannotParseResponse(error: error)
            self.didSend(request: request, received: apiError)
            throw apiError
        }

        return result
    }

    @available(iOS 15.0, tvOS 15.0, macOS 12.0, *)
    public func send<T: Decodable>(_ request: APIRequest) async throws -> APIResponse<T> {
        try await send(try request.request(for: self))
    }
    #endif
}

extension APIClient {
    private func relatedLinks<T>(from linkHeader: String?) -> [APIResponse<T>.Link:URL] {
        guard let linkHeader = linkHeader,
           let matches = linkRegex?.matches(in: linkHeader, options: [], range: NSMakeRange(0, linkHeader.count))
        else {
            return [:]
        }
        
        var links: [APIResponse<T>.Link:URL] = [:]
        for match in matches {
            guard let urlRange = Range(match.range(at: 1), in: linkHeader),
                  let url = URL(string: String(linkHeader[urlRange])),
                  let keyRange = Range(match.range(at: 2), in: linkHeader),
                  let key = APIResponse<T>.Link(rawValue: String(linkHeader[keyRange]))
            else {
                continue
            }
            
            links[key] = url
        }

        return links
    }
    
    private func validate<T: Decodable>(_ data: Data, _ response: URLResponse) throws -> APIResponse<T> {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }
        
        guard 200..<300 ~= httpResponse.statusCode else {
            if let error = error(from: data) {
                throw APIClientError.serverError(error)
            } else {
                throw APIClientError.statusCode(httpResponse.statusCode)
            }
        }
        
        var requestId: String? = nil
        if let requestIdHeader = requestIdHeader {
            requestId = httpResponse.allHeaderFields[requestIdHeader] as? String
        }
        
        var date: Date? = nil
        if let dateString = httpResponse.allHeaderFields["Date"] as? String {
            date = httpDateFormatter.date(from: dateString)
        }
        
        let rateInfo = APIResponse<T>.RateLimit(with: httpResponse.allHeaderFields)
        
        return APIResponse(result: try decode(T.self, from: data),
                           date: date ?? Date(),
                           links: relatedLinks(from: httpResponse.allHeaderFields["Link"] as? String),
                           rateInfo: rateInfo,
                           requestId: requestId)
    }
}

fileprivate let linkRegex = try? NSRegularExpression(pattern: "<([^>]+)>; rel=\"([^\"]+)\"", options: [])

fileprivate let httpDateFormatter: DateFormatter = {
    let dateFormatter = DateFormatter()
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")
    dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
    dateFormatter.dateFormat = "EEEE, dd LLL yyyy HH:mm:ss zzz"
    return dateFormatter
}()

let defaultIsoDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .iso8601)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
    return formatter
}()

let defaultJSONEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .formatted(defaultIsoDateFormatter)
    if #available(macOS 10.13, iOS 11.0, tvOS 11.0, *) {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    } else {
        encoder.outputFormatting = .prettyPrinted
    }
    return encoder
}()

fileprivate let defaultJSONDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .formatted(defaultIsoDateFormatter)
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
}()