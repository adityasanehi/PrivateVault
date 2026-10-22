//
//  RecoveryPhraseView.swift
//  LockScreen
//
//  Created by Aditya Sanehi on 23/10/26.
//

import SwiftUI

//	Shows a new recovery phrase, the caller saves the backup when `save` is called
public struct RecoveryPhraseView: View {
	let words: [String]
	let save: () -> Void
	let later: (() -> Void)?
	
	@State private var confirmed = false
	
	public init(words: [String], save: @escaping () -> Void, later: (() -> Void)? = nil) {
		self.words = words
		self.save = save
		self.later = later
	}
	
	public var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 20) {
				Text("Write these \(words.count) words down in order and keep them somewhere safe. If the app is installed again with a different certificate, they're the only way to open your files.")
					.foregroundColor(.secondary)
				LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
					ForEach(Array(words.enumerated()), id: \.offset) { index, word in
						HStack {
							Text("\(index + 1).")
								.foregroundColor(.secondary)
								.monospacedDigit()
							Text(word)
								.font(.body.monospaced())
							Spacer()
						}
						.padding(10)
						.background(Color(.secondarySystemBackground))
						.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
					}
				}
				.privacySensitive()
				Toggle("I've written down my recovery phrase", isOn: $confirmed)
				Button(action: save) {
					Text("Save Recovery Phrase")
						.frame(maxWidth: .infinity)
				}
				.buttonStyle(.borderedProminent)
				.controlSize(.large)
				.disabled(!confirmed)
			}
			.padding()
		}
		.navigationTitle("Recovery Phrase")
		.navigationBarTitleDisplayMode(.inline)
		.interactiveDismissDisabled()
		.toolbar {
			if let later = later {
				ToolbarItem(placement: .cancellationAction) {
					Button("Later", action: later)
				}
			}
		}
	}
}

struct RecoveryPhraseView_Previews: PreviewProvider {
	static var previews: some View {
		NavigationStack {
			RecoveryPhraseView(words: ["abandon", "ability", "able", "about", "above", "absent", "absorb", "abstract", "absurd", "abuse", "access", "accident"], save: {}, later: {})
		}
	}
}
