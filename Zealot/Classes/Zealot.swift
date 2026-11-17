//
//  Zealot.swift
//  Zealot
//
//  Created by icyleaf on 2020/1/7.
//

import UIKit

@objcMembers
public final class Zealot: NSObject {
    public let defaultEnvironment: String = "default"
    public var enviroment: String
    public var endpoint: String
    public var channelKeys: [String: String] = [:]
    /// Hosts that may serve an installation URL or an `itms-services` manifest.
    /// The endpoint host is allowed by default; add a trusted CDN host when needed.
    public var allowedInstallHosts: [String]

    public init(endpoint: String, channelKey: String) {
        self.endpoint = endpoint
        self.enviroment = defaultEnvironment
        self.channelKeys[enviroment] = channelKey
        self.allowedInstallHosts = Zealot.defaultAllowedInstallHosts(for: endpoint)
        super.init()
    }

    public init(endpoint: String, channelKey: String, enviroment: String) {
        self.endpoint = endpoint
        self.enviroment = enviroment
        self.channelKeys[enviroment] = channelKey
        self.allowedInstallHosts = Zealot.defaultAllowedInstallHosts(for: endpoint)
        super.init()
    }

    public init(endpoint: String, channelKeys: [String: String], default_enviroment: String) {
        self.endpoint = endpoint
        self.enviroment = default_enviroment
        self.channelKeys = channelKeys
        self.allowedInstallHosts = Zealot.defaultAllowedInstallHosts(for: endpoint)
        super.init()
    }
}

// MARK: - Public methods
public extension Zealot {

    func setChannelKey(channelKey: String, environment: String) {
        self.channelKeys[environment] = channelKey
    }

    func checkVersion() {
        guard let channelKey = try? useChannelKey() else { return }
        let client = Client(endpoint: endpoint, channelKey: channelKey)
        client.checkVersion { (result) in
            switch result {
            case .success(let channel):
                DispatchQueue.main.async {
                    self.showAlert(channel)
                }
            case .failure(_): break  // ignore
            }
        }
    }
}

// MARK: - Alert
private extension Zealot {
    func showAlert(_ channel: Channel) {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        let releases = channel.releases.filter { $0.bundleId == bundleIdentifier }
        guard let release = releases.first,
              let installURL = validatedInstallURL(release.installUrl) else { return }

        let alertController = createAlertVC(releases: releases, installURL: installURL)
        WindowHandler.shared.present(viewController: alertController)
    }

    func updateAlertAction(url: URL) -> UIAlertAction {
        let title = Bundle.localizedString(forKey: "Update")
        return UIAlertAction(title: title, style: .default) { (UIAlertAction) in
            if #available(iOS 10.0, *) {
                UIApplication.shared.open(url, options: [:]) { _ in
                    WindowHandler.shared.dismiss()
                }
            } else {
                WindowHandler.shared.dismiss()
                UIApplication.shared.openURL(url)
            }
        }
    }

    func cancelAlertAction() -> UIAlertAction {
        let title = Bundle.localizedString(forKey: "Next time")
        return UIAlertAction(title: title, style: .cancel) { (UIAlertAction) in
            WindowHandler.shared.dismiss()
        }
    }

    func createAlertVC(releases: [Channel.Release], installURL: URL) -> UIAlertController {
        let release = releases[0]

        let title = Bundle.localizedString(forKey: "Update Available")
        let message = "\(release.releaseVersion) (\(release.buildVersion))"
        let changelog = generateChangelog(releases: releases)



        let alert = UIAlertController(title: title,
                                                message: message,
                                                preferredStyle: .alert)

        alert.setMaxHeight(UIScreen.main.bounds.height / 2)
        alert.addTextView(text: changelog)
        alert.addAction(updateAlertAction(url: installURL))
        alert.addAction(cancelAlertAction())

        return alert
    }
}

// MARK: - Helper methods
private extension Zealot {
    static func defaultAllowedInstallHosts(for endpoint: String) -> [String] {
        guard let host = normalizedHost(URLComponents(string: endpoint)?.host) else { return [] }
        return [host]
    }

    static func normalizedHost(_ value: String?) -> String? {
        guard let value = value?.lowercased(), !value.isEmpty else { return nil }
        return value.hasSuffix(".") ? String(value.dropLast()) : value
    }

    func validatedInstallURL(_ value: String) -> URL? {
        guard let url = URL(string: value),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil,
              components.password == nil,
              let scheme = components.scheme?.lowercased() else {
            return nil
        }

        switch scheme {
        case "https":
            guard let host = Self.normalizedHost(components.host), isAllowedInstallHost(host) else {
                return nil
            }
            return url
        case "itms-services":
            let queryItems = components.queryItems ?? []
            let actions = queryItems.filter { $0.name == "action" }.compactMap(\.value)
            let manifests = queryItems.filter { $0.name == "url" }.compactMap(\.value)
            guard components.host == nil,
                  actions == ["download-manifest"],
                  manifests.count == 1,
                  let manifestURL = URL(string: manifests[0]),
                  let manifestComponents = URLComponents(url: manifestURL, resolvingAgainstBaseURL: false),
                  manifestComponents.scheme?.lowercased() == "https",
                  manifestComponents.user == nil,
                  manifestComponents.password == nil,
                  let manifestHost = Self.normalizedHost(manifestComponents.host),
                  isAllowedInstallHost(manifestHost) else {
                return nil
            }
            return url
        default:
            return nil
        }
    }

    func isAllowedInstallHost(_ host: String) -> Bool {
        return allowedInstallHosts.compactMap(Self.normalizedHost).contains(host)
    }

    func generateChangelog(releases: [Channel.Release]) -> String {
        var changelogMessage = [String]()
        var number = 1
        for release in releases {
            for changelog in release.changelog {
                if changelog.message.isEmpty { continue }

                changelogMessage.append("\(number). \(changelog.message)")
                number += 1
            }
        }

        return changelogMessage.joined(separator: "\n")
    }

    func useChannelKey() throws -> String {
        guard let channelKey = channelKeys[enviroment] else {
            let defaultChannelkey = channelKeys[defaultEnvironment]
            if defaultChannelkey != nil {
                return defaultChannelkey!
            }

            throw ZealotError.notFoundChannelKey
        }

        return channelKey
    }
}

enum ZealotError: Error {
    case notFoundChannelKey
    case notFoundChannel
    case invalidEndpoint
    case invaildJson(String)
}
