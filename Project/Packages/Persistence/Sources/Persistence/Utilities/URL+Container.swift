//
//  URL+Container.swift
//  PrivateVault
//
//  Created by Emilio Peláez on 15/3/21.
//

import Foundation

public extension URL {
	static let appGroupIdentifier = "group.com.emiliopelaez.Private-Vault"
	
	//	False when the app was re-signed without the app group, like most sideloaded builds
	static var hasAppGroup: Bool {
		FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) != nil
	}
	
	//	Falls back to the app's own sandbox when the app group is missing, the import extension can't reach it then
	static var container: URL {
		if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
			return url
		}
		do {
			return try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
		} catch {
			fatalError("Unable to get container url.")
		}
	}
}
