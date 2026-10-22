//
//  VaultCrypto+Recovery.swift
//  Persistence
//
//  Created by Aditya Sanehi on 23/10/26.
//

import CryptoKit
import Foundation

//	Re-signing the app with a certificate from another team makes the old keychain items unreadable.
//	A copy of the keys sealed with a key derived from a 12 word recovery phrase is stored next to the vault to bring them back.
public extension VaultCrypto {
	static let recoveryPhraseLength = 12
	
	//	132 bits of entropy, enough that the phrase doesn't need a slow key derivation
	static func generateRecoveryPhrase() -> [String] {
		var generator = SystemRandomNumberGenerator()
		return (0 ..< recoveryPhraseLength).map { _ in
			recoveryWordlist[Int.random(in: 0 ..< recoveryWordlist.count, using: &generator)]
		}
	}
	
	//	False while locked, or when a key isn't included in any backup and a new phrase should be saved
	var isBackedUp: Bool {
		let ids = keysLock.withLock { Set(keys.keys) }
		guard !ids.isEmpty else { return false }
		return Self.recoveryBackups.contains { ids.isSubset(of: $0.backup.keyIds) }
	}
	
	//	Seals every loaded key with the phrase, older backups whose keys are all included are removed
	func saveRecoveryBackup(phrase: [String]) throws {
		let keys = keysLock.withLock { self.keys }
		guard !keys.isEmpty else { throw CryptoError.locked }
		var generator = SystemRandomNumberGenerator()
		let salt = Data((0 ..< 16).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
		let recoveryKey = Self.recoveryKey(phrase: phrase, salt: salt)
		let sealedKeys = try keys.map { id, key in
			let keyData = key.withUnsafeBytes { Data($0) }
			guard let box = try AES.GCM.seal(keyData, using: recoveryKey, authenticating: id).combined else {
				throw CryptoError.malformedData
			}
			return RecoveryBackup.SealedKey(id: id, box: box)
		}
		let previous = Self.recoveryBackups
		try FileManager.default.createDirectory(at: Self.recoveryFolder, withIntermediateDirectories: true)
		let url = Self.recoveryFolder.appendingPathComponent(UUID().uuidString).appendingPathExtension(Self.recoveryExtension)
		try JSONEncoder().encode(RecoveryBackup(salt: salt, keys: sealedKeys)).write(to: url, options: [.atomic, .completeFileProtection])
		previous
			.filter { $0.backup.keyIds.isSubset(of: Set(keys.keys)) }
			.forEach { try? FileManager.default.removeItem(at: $0.url) }
	}
	
	//	Restores the keys from every backup the phrase opens, then unlocks
	func recover(phrase: String, completion: @escaping (Result<Void, Error>) -> Void) {
		unlock(prepare: { [self] in
			guard let words = Self.recoveryWords(in: phrase) else { throw CryptoError.wrongRecoveryPhrase }
			let restored = Self.recoveryBackups.compactMap { _, backup in
				let recoveryKey = Self.recoveryKey(phrase: words, salt: backup.salt)
				return try? backup.keys.map {
					try AES.GCM.open(AES.GCM.SealedBox(combined: $0.box), using: recoveryKey, authenticating: $0.id)
				}
			}
			guard !restored.isEmpty else { throw CryptoError.wrongRecoveryPhrase }
			try restored.joined().forEach { try createKey($0) }
		}, completion: completion)
	}
	
	//	For a lost phrase, items sealed with the old keys stay unreadable but their backups are kept for a later recovery
	func unlockWithNewKey(completion: @escaping (Result<Void, Error>) -> Void) {
		unlock(prepare: { [self] in try createKey() }, completion: completion)
	}
}

extension VaultCrypto {
	struct RecoveryBackup: Codable {
		struct SealedKey: Codable {
			let id: Data
			let box: Data
		}
		
		var version = 1
		let salt: Data
		let keys: [SealedKey]
		
		var keyIds: Set<Data> { Set(keys.map(\.id)) }
	}
	
	private static let recoveryExtension = "vaultkeys"
	private static let recoveryWordSet = Set(recoveryWordlist)
	
	//	Lives in the vault container, which is kept when the app is re-signed with the same bundle identifier
	static var recoveryFolder: URL {
		URL.container.appendingPathComponent("Recovery", isDirectory: true)
	}
	
	static var hasRecoveryBackups: Bool {
		!recoveryBackups.isEmpty
	}
	
	static var recoveryBackups: [(url: URL, backup: RecoveryBackup)] {
		let urls = (try? FileManager.default.contentsOfDirectory(at: recoveryFolder, includingPropertiesForKeys: nil)) ?? []
		return urls
			.filter { $0.pathExtension == recoveryExtension }
			.compactMap { url in
				guard let data = try? Data(contentsOf: url), let backup = try? JSONDecoder().decode(RecoveryBackup.self, from: data) else {
					return nil
				}
				return (url, backup)
			}
	}
	
	//	Accepts any capitalization, spacing or commas between words
	static func recoveryWords(in phrase: String) -> [String]? {
		let words = phrase.lowercased()
			.split { $0.isWhitespace || $0 == "," }
			.map(String.init)
		guard words.count == recoveryPhraseLength, words.allSatisfy(recoveryWordSet.contains) else { return nil }
		return words
	}
	
	static func recoveryKey(phrase: [String], salt: Data) -> SymmetricKey {
		HKDF<SHA256>.deriveKey(
			inputKeyMaterial: SymmetricKey(data: Data(phrase.joined(separator: " ").utf8)),
			salt: salt,
			info: Data("PrivateVault recovery".utf8),
			outputByteCount: 32
		)
	}
}
