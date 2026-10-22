//
//  StoredItem+Creation.swift
//  PrivateVault
//
//  Created by Emilio Peláez on 20/2/21.
//

import CoreData
import UIKit

public extension StoredItem {
	
	//	`sealedData` and `sealedPreviewData` must already be encrypted with `VaultCrypto`
	convenience init(context: NSManagedObjectContext, sealedData: Data, sealedPreviewData: Data? = nil, type: DataType, name: String, fileExtension: String, folder: Folder?) {
		self.init(context: context)
		self.id = UUID().uuidString
		self.data = sealedData
		self.previewData = sealedPreviewData
		self.dataType = type
		self.name = name
		self.fileExtension = fileExtension
		self.folder = folder
		self.timestamp = Date()
	}
	
	convenience init(context: NSManagedObjectContext, url: URL, sealedPreviewData: Data? = nil, name: String, folder: Folder?) {
		self.init(context: context)
		self.id = UUID().uuidString
		self.remoteUrl = url
		self.previewData = sealedPreviewData
		self.dataType = .url
		self.name = name
		self.folder = folder
		self.timestamp = Date()
	}
	
	//	Only used by `PreviewEnvironment`, stores unencrypted data that `VaultCrypto.decrypt` passes through
	convenience init(context: NSManagedObjectContext, image: UIImage, name: String, extension _: String, folder: Folder?) {
		let data = image.pngData()
		let resizedImage = image.square(200)?.jpegData(compressionQuality: 0.85)
		self.init(context: context)
		self.id = UUID().uuidString
		self.data = data
		self.previewData = resizedImage
		self.dataType = .image
		self.name = name
		self.fileExtension = "png"
		self.folder = folder
		self.timestamp = Date()
	}
}
