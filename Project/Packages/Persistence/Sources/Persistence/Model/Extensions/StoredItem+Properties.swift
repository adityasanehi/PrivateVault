//
//  StoredItem+Properties.swift
//  PrivateVault
//
//  Created by Emilio Peláez on 20/2/21.
//

import SwiftUI

public extension StoredItem {
	//	Throws `VaultCrypto.CryptoError.locked` while the vault is locked
	func generatePreview() throws -> Image? {
		try previewData.map(VaultCrypto.shared.decrypt).flatMap(UIImage.init).map(Image.init)
	}
	
	var searchText: String {
		let tags = self.tags as? Set<Tag>
		let tagSearch = tags?.compactMap(\.name).joined(separator: " ")
		return [tagSearch, name].compactMap { $0 }.joined(separator: " ")
	}
	
	var tagsText: String {
		guard let tags = self.tags as? Set<Tag>, !tags.isEmpty else {
			return "No Tags"
		}
		return tags.map(\.name).compactMap { $0 }.sorted().joined(separator: ", ")
	}
}
