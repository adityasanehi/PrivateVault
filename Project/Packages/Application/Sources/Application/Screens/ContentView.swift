//
//  ContentView.swift
//  PrivateVault
//
//  Created by Emilio Peláez on 19/2/21.
//

import LockScreen
import Middleware
import Persistence
import Shared
import SwiftUI

struct ContentView: View {
	enum VaultSheet: Identifiable {
		case createPhrase([String])
		case recover
		
		var id: String {
			switch self {
			case .createPhrase: return "createPhrase"
			case .recover: return "recover"
			}
		}
	}
	
	@State private var vaultSheet: VaultSheet?
	
	@StateObject private var appState = AppState()
	@StateObject private var filter = ItemFilter()
	@Environment(\.scenePhase) private var scenePhase
	@EnvironmentObject private var settings: UserSettings
	@EnvironmentObject private var passcodeManager: PasscodeManager
	@EnvironmentObject private var persistenceController: PersistenceManager

	var body: some View {
		content
			.onChange(of: appState.isLocked, initial: true) { _, isLocked in
				updateVault(isLocked: isLocked)
			}
			.sheet(item: $vaultSheet) { sheet in
				NavigationStack {
					switch sheet {
					case let .createPhrase(words):
						RecoveryPhraseView(words: words) {
							saveRecoveryPhrase(words)
						} later: {
							vaultSheet = nil
						}
					case .recover:
						RecoverVaultView(recover: recover, startOver: startOver)
					}
				}
			}
	}
	
	@ViewBuilder
	private var content: some View {
		if !passcodeManager.passcodeSet {
			SetPasscodeView { newCode, newLength in
				withAnimation {
					passcodeManager.passcodeLength = newLength
					passcodeManager.passcode = newCode
					appState.isLocked = false
				}
			}
			.transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing)))
		} else {
			NavigationView {
				GalleryView(isLocked: $appState.isLocked)
			}
			.navigationViewStyle(StackNavigationViewStyle())
			.transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing)))
			.overlay(
				Group {
					if appState.isLocked {
						LockView(isLocked: $appState.isLocked)
							.transition(.asymmetric(insertion: .opacity, removal: .move(edge: .bottom)))
					}
				}
			)
			.onChange(of: scenePhase) { _, phase in
				if [.inactive, .background].contains(phase) {
					appState.isLocked = true
				}
			}
			.environmentObject(appState)
			.environmentObject(filter)
		}
	}
	
	//	Encryption keys are only held in memory while the lock screen is dismissed
	private func updateVault(isLocked: Bool) {
		if isLocked {
			//	The recovery phrase shouldn't stay on screen behind the lock
			vaultSheet = nil
			VaultCrypto.shared.lock()
			PreviewCache.shared.clear()
		} else {
			VaultCrypto.shared.unlock { result in
				switch result {
				case .success:
					didUnlockVault()
				case .failure(VaultCrypto.CryptoError.locked):
					break
				case .failure(VaultCrypto.CryptoError.recoveryRequired):
					vaultSheet = .recover
				case .failure:
					persistenceController.errorString = "Unable to load the encryption key from the Keychain."
				}
			}
		}
	}
	
	private func didUnlockVault() {
		persistenceController.encryptLegacyItems()
		//	Asked again on every unlock until a phrase covering every key has been saved
		guard !demoContent, !VaultCrypto.shared.isBackedUp else { return }
		vaultSheet = .createPhrase(VaultCrypto.generateRecoveryPhrase())
	}
	
	private func saveRecoveryPhrase(_ words: [String]) {
		do {
			try VaultCrypto.shared.saveRecoveryBackup(phrase: words)
			vaultSheet = nil
		} catch {
			vaultSheet = nil
			persistenceController.errorString = "Unable to save the recovery backup."
		}
	}
	
	private func recover(phrase: String, completion: @escaping (Bool) -> Void) {
		VaultCrypto.shared.recover(phrase: phrase) { result in
			completion((try? result.get()) != nil)
			guard case .success = result else { return }
			vaultSheet = nil
			didUnlockVault()
		}
	}
	
	private func startOver() {
		VaultCrypto.shared.unlockWithNewKey { result in
			vaultSheet = nil
			switch result {
			case .success:
				didUnlockVault()
			case .failure:
				persistenceController.errorString = "Unable to create a new encryption key."
			}
		}
	}
}

struct ContentView_Previews: PreviewProvider {
	static let preview = PreviewEnvironment()
	
	static var previews: some View {
		ContentView()
			.environment(\.managedObjectContext, preview.context)
			.environmentObject(preview.controller)
			.environmentObject(UserSettings())
			.environmentObject(PasscodeManager())
			.environmentObject(AppState())
	}
}
