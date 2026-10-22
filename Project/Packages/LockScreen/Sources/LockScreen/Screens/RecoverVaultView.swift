//
//  RecoverVaultView.swift
//  LockScreen
//
//  Created by Aditya Sanehi on 23/10/26.
//

import SwiftUI

//	Asks for the recovery phrase, `recover` calls its completion with whether the phrase opened a backup
public struct RecoverVaultView: View {
	let recover: (String, @escaping (Bool) -> Void) -> Void
	let startOver: (() -> Void)?
	
	@State private var phrase = ""
	@State private var working = false
	@State private var failed = false
	@State private var confirmStartOver = false
	
	public init(recover: @escaping (String, @escaping (Bool) -> Void) -> Void, startOver: (() -> Void)? = nil) {
		self.recover = recover
		self.startOver = startOver
	}
	
	public var body: some View {
		Form {
			Section(footer: Text("Enter the 12 word recovery phrase you saved when you set up encryption.")) {
				TextField("Recovery phrase", text: $phrase, axis: .vertical)
					.lineLimit(3 ... 6)
					.textInputAutocapitalization(.never)
					.autocorrectionDisabled()
					.privacySensitive()
			}
			if failed {
				Section {
					Text("That phrase doesn't match any recovery backup.")
						.foregroundColor(.red)
				}
			}
			Section {
				Button {
					submit()
				} label: {
					if working {
						ProgressView()
					} else {
						Text("Recover Files")
					}
				}
				.disabled(working || phrase.isEmpty)
			}
			if startOver != nil {
				Section(footer: Text("Creates a new key so you can keep using the app. Files stored before stay unreadable until you recover them from Settings with the phrase.")) {
					Button("Continue Without Recovering", role: .destructive) {
						confirmStartOver = true
					}
				}
			}
		}
		.navigationTitle("Recover Vault")
		.interactiveDismissDisabled(startOver != nil)
		.confirmationDialog("Continue without recovering?", isPresented: $confirmStartOver, titleVisibility: .visible) {
			Button("Continue", role: .destructive) {
				startOver?()
			}
		} message: {
			Text("Your existing files can't be opened until you enter the recovery phrase.")
		}
	}
	
	private func submit() {
		working = true
		failed = false
		recover(phrase) { success in
			working = false
			failed = !success
		}
	}
}

struct RecoverVaultView_Previews: PreviewProvider {
	static var previews: some View {
		NavigationStack {
			RecoverVaultView(recover: { _, completion in completion(false) }, startOver: {})
		}
	}
}
