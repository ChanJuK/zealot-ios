//
//  Client.swift
//  Zealot
//
//  Created by icyleaf on 2020/1/8.
//

import Foundation

private final class HTTPSOnlyRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard request.url?.scheme?.lowercased() == "https" else {
            completionHandler(nil)
            return
        }

        completionHandler(request)
    }
}

@objcMembers
public final class Client {
    private var endpoint: String
    private var channelKey: String
    private static let secureSession = URLSession(
        configuration: .ephemeral,
        delegate: HTTPSOnlyRedirectDelegate(),
        delegateQueue: nil
    )

    typealias CompletionHandler = (Result<Channel, ZealotError>) -> Void

    public init(endpoint: String, channelKey: String) {
        self.endpoint = endpoint
        self.channelKey = channelKey
    }

    func checkVersion(completion: CompletionHandler?) {
        guard let url = latestVersionURL() else {
            completion?(.failure(.invalidEndpoint))
            return
        }

        let request = URLRequest(url: url)
        let task = Self.secureSession.dataTask(with: request) { data, response, error in
            guard let data = data, let response = response as? HTTPURLResponse,
                response.statusCode == 200, error == nil else {
                    completion?(.failure(.notFoundChannel))
                    return
            }

            do {
                let decoder = JSONDecoder()
                let channel = try decoder.decode(Channel.self, from: data)
                completion?(.success(channel))
            } catch let parsingError {
                completion?(.failure(.invaildJson(parsingError.localizedDescription)))
            }
        }
        task.resume()
    }

    private func latestVersionURL() -> URL? {
        guard var components = URLComponents(string: endpoint),
              components.scheme?.lowercased() == "https",
              components.host != nil,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            return nil
        }

        let basePath = components.path.hasSuffix("/")
            ? String(components.path.dropLast())
            : components.path
        components.path = "\(basePath)/api/apps/latest"
        components.queryItems = buildQuery()
        return components.url
    }

    func buildQuery() -> [URLQueryItem] {
        return [
            URLQueryItem(name: "channel_key", value: channelKey),
            URLQueryItem(name: "bundle_id", value: bundleId),
            URLQueryItem(name: "release_version", value: version),
            URLQueryItem(name: "build_version", value: buildVersion),
            URLQueryItem(name: "sdk", value: sdkInfo)
        ]
    }
}

extension Client {
    var bundleId: String {
        return Bundle.main.infoDictionary?["CFBundleIdentifier"] as! String
    }

    var version: String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as! String
    }

    var buildVersion: String {
        return Bundle.main.infoDictionary?["CFBundleVersion"] as! String
    }

    var sdkInfo: String {
        let zealotVersion = Bundle(for: type(of: self))
                .object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String

        return "ios-\(zealotVersion)"
    }
}
