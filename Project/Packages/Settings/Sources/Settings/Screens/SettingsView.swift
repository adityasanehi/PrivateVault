//
//  SettingsView.swift
//  PrivateVault
//
//  Created by Ian Manor on 20/02/21.
//

import LocalAuthentication
import LockScreen
import Middleware
import Persistence
import SwiftUI
import UIToolKit

public struct SettingsView: View {
	@EnvironmentObject private var settings: UserSettings
	@EnvironmentObject private var passcodeManager: PasscodeManager
	@Environment(\.dismiss) var dismiss

	let biometricsContext = LAContext()

	@State var resetPasscode: Bool = false
	@State private var newRecoveryPhrase: [String]?
	@State private var recoverFiles = false
	@State private var recoveryError: String?
	let version = "1.0"
	
	public init() {}
	
	var biometricSupported: Bool {
		biometricsContext.availableType != .none
	}

	var biometricTitle: String {
		switch biometricsContext.availableType {
		case .faceID: return "Face ID"
		case .touchID: return "Touch ID"
		case _: return ""
		}
	}

	public var body: some View {
		NavigationStack {
			Form {
				Section(header: Text("Security")) {
					if biometricSupported {
						HStack {
							Text(biometricTitle)
							Spacer()
							Toggle("", isOn: $settings.biometrics)
						}
					}
					HStack {
						Stepper(value: $settings.maxAttempts, in: 1 ... 10) {
							HStack {
								Text("Attempt Limit")
								Text("\(settings.maxAttempts)")
							}
						}
					}
					Button {
						resetPasscode = true
					} label: {
						HStack {
							Text("Reset Passcode")
								.foregroundColor(.primary)
							Spacer()
							Image(systemName: "chevron.right")
								.font(.footnote.weight(.semibold))
								.foregroundColor(Color(.tertiaryLabel))
						}
					}
				}
				Section(header: Text("Recovery"), footer: Text("The recovery phrase restores your encryption key if the app is installed again with a different certificate.")) {
					Button {
						newRecoveryPhrase = VaultCrypto.generateRecoveryPhrase()
					} label: {
						navigationRow("Create New Recovery Phrase")
					}
					Button {
						recoverFiles = true
					} label: {
						navigationRow("Recover Files")
					}
				}
				Section(header: Text("General")) {
					Toggle(isOn: $settings.sound) {
						Text("Sound")
					}
					Toggle(isOn: $settings.hapticFeedback) {
						Text("Haptic Feedback")
					}
				}
				Section(header: Text("iCloud")) {
					CloudSyncStatusRow()
				}
				Section(header: Text("Legal")) {
					NavigationLink(destination: AboutView()) {
						Text("About")
					}
					NavigationLink(destination: SettingsLicenseView()) {
						Text("License")
					}
					NavigationLink(destination: SettingsPrivacyView()) {
						Text("Privacy")
					}
				}
			}
			.listStyle(InsetGroupedListStyle())
			.navigationTitle("Settings")
			.navigationDestination(isPresented: $resetPasscode) { resetView }
			.navigationDestination(item: $newRecoveryPhrase) { words in
				RecoveryPhraseView(words: words) {
					do {
						try VaultCrypto.shared.saveRecoveryBackup(phrase: words)
					} catch {
						recoveryError = "Unable to save the recovery backup."
					}
					newRecoveryPhrase = nil
				}
			}
			.navigationDestination(isPresented: $recoverFiles) {
				RecoverVaultView { phrase, completion in
					VaultCrypto.shared.recover(phrase: phrase) { result in
						completion((try? result.get()) != nil)
						if case .success = result { recoverFiles = false }
					}
				}
			}
			.alert("Recovery Phrase", isPresented: Binding { recoveryError != nil } set: { if !$0 { recoveryError = nil } }) {
				Button("OK") {}
			} message: {
				Text(recoveryError ?? "")
			}
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					ModalDismissButton(dismiss)
				}
			}
		}
	}
	
	func navigationRow(_ title: String) -> some View {
		HStack {
			Text(title)
				.foregroundColor(.primary)
			Spacer()
			Image(systemName: "chevron.right")
				.font(.footnote.weight(.semibold))
				.foregroundColor(Color(.tertiaryLabel))
		}
	}
	
	var resetView: some View {
		SetPasscodeView { newCode, newLength in
			passcodeManager.passcodeLength = newLength
			passcodeManager.passcode = newCode
			resetPasscode = false
		}
		.navigationBarTitle(Text("Reset"), displayMode: .inline)
	}

	var footer: some View {
		HStack {
			Spacer()
			Text("Version \(version)")
				.font(.footnote)
				.foregroundColor(Color(.secondaryLabel))
			Spacer()
		}
	}

	func requestBiometric() {
		let context = LAContext()
		var error: NSError?

		if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
		} else {
			return
		}
	}
}

struct SettingsView_Previews: PreviewProvider {
	static var previews: some View {
		SettingsView()
			.environmentObject(UserSettings())
			.environmentObject(PasscodeManager())
	}
}
