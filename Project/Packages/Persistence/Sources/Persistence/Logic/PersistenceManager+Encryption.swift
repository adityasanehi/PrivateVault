//
//  PersistenceManager+Encryption.swift
//  Persistence
//
//  Created by Aditya Sanehi on 23/10/26.
//

import CoreData

public extension PersistenceManager {
	private static let legacyItemsEncryptedKey = "legacyItemsEncrypted"
	
	//	Items stored before encryption was introduced are sealed in place, call after unlocking the vault
	func encryptLegacyItems() {
		guard usage == .main, !encryptingLegacyItems else { return }
		guard !UserDefaults.standard.bool(forKey: Self.legacyItemsEncryptedKey) else { return }
		encryptingLegacyItems = true
		container.performBackgroundTask { context in
			context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
			context.transactionAuthor = "App"
			let completed = Self.encryptItems(in: context)
			DispatchQueue.main.async {
				self.encryptingLegacyItems = false
				if completed {
					UserDefaults.standard.set(true, forKey: Self.legacyItemsEncryptedKey)
				}
			}
		}
	}
	
	//	Returns false if the vault locked or saving failed, the remaining items are picked up on the next unlock
	private static func encryptItems(in context: NSManagedObjectContext) -> Bool {
		let request = StoredItem.fetchRequest()
		guard let ids = try? context.fetch(request).map(\.objectID) else { return false }
		let batchSize = 20
		for batchStart in stride(from: 0, to: ids.count, by: batchSize) {
			for id in ids[batchStart ..< min(batchStart + batchSize, ids.count)] {
				guard let item = try? context.existingObject(with: id) as? StoredItem else { continue }
				do {
					if let data = item.data, !VaultCrypto.isSealed(data) {
						item.data = try VaultCrypto.shared.encrypt(data)
					}
					if let previewData = item.previewData, !VaultCrypto.isSealed(previewData) {
						item.previewData = try VaultCrypto.shared.encrypt(previewData)
					}
				} catch {
					context.rollback()
					return false
				}
			}
			do {
				if context.hasChanges { try context.save() }
			} catch {
				return false
			}
			//	Turns the batch back into faults so their contents don't stay in memory
			context.refreshAllObjects()
		}
		return true
	}
}
