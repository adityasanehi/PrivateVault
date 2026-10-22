//
//  VaultCrypto.swift
//  Persistence
//
//  Created by Aditya Sanehi on 23/10/26.
//

import CryptoKit
import Foundation
import LocalAuthentication
import Security

//	Encrypts item contents and previews with AES-256-GCM before they reach the store.
//	Keys are kept in the iCloud Keychain so every device on the same account can open synced items,
//	they're only loaded into memory after the user unlocks the vault and are dropped when it locks again.
//	Builds without iCloud sync keep their keys on this device only.
public class VaultCrypto: ObservableObject {

	public enum CryptoError: Swift.Error {
		case locked
		case unknownKey
		case malformedData
		case authenticationFailed
		case keychain(OSStatus)
		//	The keychain is empty but a recovery backup exists, usually after re-signing with another team
		case recoveryRequired
		case wrongRecoveryPhrase
	}

	public static let shared = VaultCrypto()

	@Published public private(set) var isUnlocked = false

	//	Sealed data is laid out as `magic + key id + AES.GCM combined box (nonce, ciphertext, tag)`
	private static let magic = Data("PVENC1".utf8)
	private static let keyIdLength = 8
	private static let headerLength = magic.count + keyIdLength

	private static let service = "com.emiliopelaez.Private-Vault.encryption"
	//	App groups double as keychain access groups, this lets the import extension use the same keys
	private static let accessGroup = URL.hasAppGroup ? URL.appGroupIdentifier : nil
	private static let syncsKeys = PersistenceManager.cloudSyncEnabled

	//	Internal so `VaultCrypto+Recovery` can reach them, must be accessed while holding `keysLock`
	var keys: [Data: SymmetricKey] = [:]
	//	Lowest key id, so devices that created keys at the same time converge on the same one
	var primaryKeyId: Data?
	//	Incremented on every lock, an unlock that finishes after a lock is discarded
	private var generation = 0
	let keysLock = NSLock()
	let queue = DispatchQueue(label: "VaultCrypto", qos: .userInitiated)

	private init() {}

	public static func isSealed(_ data: Data) -> Bool {
		data.count > headerLength && data.starts(with: magic)
	}

	//	Call once the user has passed the app's lock screen
	public func unlock(completion: @escaping (Result<Void, Error>) -> Void = { _ in }) {
		unlock(prepare: { [self] in
			guard try fetchKeys().isEmpty else { return }
			//	A new key would leave the backed up items unreadable, those need the recovery phrase
			guard !Self.hasRecoveryBackups else { throw CryptoError.recoveryRequired }
			try createKey()
		}, completion: completion)
	}
	
	//	Runs `prepare` on the crypto queue, then loads every key in the keychain
	func unlock(prepare: @escaping () throws -> Void, completion: @escaping (Result<Void, Error>) -> Void) {
		let generation = keysLock.withLock { self.generation }
		queue.async { [self] in
			let result = Result {
				try prepare()
				let keys = try fetchKeys()
				guard !keys.isEmpty else { throw CryptoError.keychain(errSecItemNotFound) }
				return keys
			}
			let installed = result.map { keys in
				keysLock.withLock {
					guard generation == self.generation else { return false }
					install(keys)
					return true
				}
			}
			DispatchQueue.main.async {
				switch installed {
				case .success(true):
					//	Previews that failed with a missing key get another chance, setting `isUnlocked` redraws them
					PreviewCache.shared.clear()
					self.isUnlocked = true
					completion(.success(()))
				case .success(false):
					completion(.failure(CryptoError.locked))
				case let .failure(error):
					completion(.failure(error))
				}
			}
		}
	}

	//	For contexts without their own lock screen, like the import extension, asks for Face ID, Touch ID or the device passcode first
	public func unlock(reason: String, completion: @escaping (Result<Void, Error>) -> Void) {
		let context = LAContext()
		context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { [self] success, error in
			//	Devices without a passcode can't evaluate any policy, there's nothing stronger to check against
			if success || (error as? LAError)?.code == .passcodeNotSet {
				unlock(completion: completion)
			} else {
				DispatchQueue.main.async {
					completion(.failure(CryptoError.authenticationFailed))
				}
			}
		}
	}

	public func lock() {
		keysLock.withLock {
			keys = [:]
			primaryKeyId = nil
			generation += 1
		}
		isUnlocked = false
	}

	public func encrypt(_ data: Data) throws -> Data {
		let (keyId, key) = try keysLock.withLock { () throws -> (Data, SymmetricKey) in
			guard let keyId = primaryKeyId, let key = keys[keyId] else { throw CryptoError.locked }
			return (keyId, key)
		}
		guard let combined = try AES.GCM.seal(data, using: key).combined else {
			throw CryptoError.malformedData
		}
		return Self.magic + keyId + combined
	}

	//	Data stored before encryption was introduced is returned unchanged
	public func decrypt(_ data: Data) throws -> Data {
		guard Self.isSealed(data) else { return data }
		let keyId = Data(data.dropFirst(Self.magic.count).prefix(Self.keyIdLength))
		let box = try AES.GCM.SealedBox(combined: data.dropFirst(Self.headerLength))
		return try AES.GCM.open(box, using: key(for: keyId))
	}

	private func key(for keyId: Data) throws -> SymmetricKey {
		let cached = try keysLock.withLock { () throws -> SymmetricKey? in
			guard primaryKeyId != nil else { throw CryptoError.locked }
			return keys[keyId]
		}
		if let cached = cached { return cached }
		//	Items from another device can arrive before its key does, check if it has synced since unlocking
		let fetched = try fetchKeys()
		return try keysLock.withLock {
			guard primaryKeyId != nil else { throw CryptoError.locked }
			install(fetched)
			guard let key = keys[keyId] else { throw CryptoError.unknownKey }
			return key
		}
	}

	//	Must be called while holding `keysLock`
	func install(_ newKeys: [Data: SymmetricKey]) {
		keys.merge(newKeys) { current, _ in current }
		primaryKeyId = keys.keys.min { $0.lexicographicallyPrecedes($1) }
	}

	static func identifier(for keyData: Data) -> Data {
		Data(SHA256.hash(data: keyData).prefix(keyIdLength))
	}

	private var baseQuery: [CFString: Any] {
		var query: [CFString: Any] = [
			kSecClass: kSecClassGenericPassword,
			kSecAttrService: Self.service,
			kSecUseDataProtectionKeychain: true,
		]
		query[kSecAttrAccessGroup] = Self.accessGroup
		return query
	}

	func fetchKeys() throws -> [Data: SymmetricKey] {
		var query = baseQuery
		query[kSecAttrSynchronizable] = kSecAttrSynchronizableAny
		query[kSecMatchLimit] = kSecMatchLimitAll
		query[kSecReturnData] = true
		var result: CFTypeRef?
		let status = SecItemCopyMatching(query as CFDictionary, &result)
		switch status {
		case errSecSuccess:
			let items = result as? [Data] ?? []
			return items
				.filter { $0.count == SymmetricKeySize.bits256.bitCount / 8 }
				.reduce(into: [:]) { $0[Self.identifier(for: $1)] = SymmetricKey(data: $1) }
		case errSecItemNotFound:
			return [:]
		default:
			throw CryptoError.keychain(status)
		}
	}

	//	Stores `keyData` when restoring from a recovery backup, otherwise generates a new key
	func createKey(_ keyData: Data = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }) throws {
		var query = baseQuery
		query[kSecAttrAccount] = Self.identifier(for: keyData).map { String(format: "%02x", $0) }.joined()
		query[kSecAttrSynchronizable] = Self.syncsKeys
		query[kSecAttrAccessible] = Self.syncsKeys ? kSecAttrAccessibleWhenUnlocked : kSecAttrAccessibleWhenUnlockedThisDeviceOnly
		query[kSecValueData] = keyData
		let status = SecItemAdd(query as CFDictionary, nil)
		guard status == errSecSuccess || status == errSecDuplicateItem else {
			throw CryptoError.keychain(status)
		}
	}
}
