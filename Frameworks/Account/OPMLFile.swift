//
//  OPMLFile.swift
//  Account
//
//  Created by Maurice Parker on 9/12/19.
//  Copyright © 2019 Ranchero Software, LLC. All rights reserved.
//

import Foundation
import os.log
import RSCore
import RSParser

final class OPMLFile: NSObject, NSFilePresenter {
	
	private var log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "opmlFile")

	private var isDirty = false {
		didSet {
			queueSaveToDiskIfNeeded()
		}
	}
	
	private var isLoading = false
	private let fileURL: URL
	private let account: Account
	private let operationQueue: OperationQueue
	
	var presentedItemURL: URL? {
		return fileURL
	}
	
	var presentedItemOperationQueue: OperationQueue {
		return operationQueue
	}
	
	init(filename: String, account: Account) {
		self.fileURL = URL(fileURLWithPath: filename)
		self.account = account
		operationQueue = OperationQueue()
		operationQueue.maxConcurrentOperationCount = 1
	
		super.init()
		
		NSFileCoordinator.addFilePresenter(self)
	}
	
	func presentedItemDidChange() {
		DispatchQueue.main.async {
			self.reload()
		}
	}
	
	func markAsDirty() {
		if !isLoading {
			isDirty = true
		}
	}
	
	func queueSaveToDiskIfNeeded() {
		Account.saveQueue.add(self, #selector(saveToDiskIfNeeded))
	}

	func load() {
		isLoading = true
		guard let opmlItems = parsedOPMLItems() else { return }
		BatchUpdate.shared.perform {
			account.loadOPMLItems(opmlItems, parentFolder: nil)
		}
		isLoading = false
	}
	
}

private extension OPMLFile {
	
	@objc func saveToDiskIfNeeded() {
		if isDirty && !account.isDeleted {
			isDirty = false
			save()
		}
	}

	func save() {
		let opmlDocumentString = opmlDocument()
		
		let errorPointer: NSErrorPointer = nil
		let fileCoordinator = NSFileCoordinator(filePresenter: self)
		
		fileCoordinator.coordinate(writingItemAt: fileURL, options: .forReplacing, error: errorPointer, byAccessor: { writeURL in
			do {
				try opmlDocumentString.write(to: writeURL, atomically: true, encoding: .utf8)
			} catch let error as NSError {
				os_log(.error, log: log, "OPML save to disk failed: %@.", error.localizedDescription)
			}
		})
		
		if let error = errorPointer?.pointee {
			os_log(.error, log: log, "OPML save to disk coordination failed: %@.", error.localizedDescription)
		}
	}
	
	func reload() {
		isLoading = true
		guard let opmlItems = parsedOPMLItems() else { return }
		BatchUpdate.shared.perform {
			account.topLevelFeeds.removeAll()
			account.loadOPMLItems(opmlItems, parentFolder: nil)
		}
		isLoading = false
	}

	func parsedOPMLItems() -> [RSOPMLItem]? {

		var fileData: Data? = nil
		let errorPointer: NSErrorPointer = nil
		let fileCoordinator = NSFileCoordinator(filePresenter: self)
		
		fileCoordinator.coordinate(readingItemAt: fileURL, options: [], error: errorPointer, byAccessor: { readURL in
			do {
				fileData = try Data(contentsOf: readURL)
			} catch {
				// Commented out because it’s not an error on first run.
				// TODO: make it so we know if it’s first run or not.
				//NSApplication.shared.presentError(error)
				os_log(.error, log: log, "OPML read from disk failed: %@.", error.localizedDescription)
			}
		})
		
		if let error = errorPointer?.pointee {
			os_log(.error, log: log, "OPML read from disk coordination failed: %@.", error.localizedDescription)
		}

		guard let opmlData = fileData else {
			return nil
		}

		let parserData = ParserData(url: fileURL.absoluteString, data: opmlData)
		var opmlDocument: RSOPMLDocument?

		do {
			opmlDocument = try RSOPMLParser.parseOPML(with: parserData)
		} catch {
			os_log(.error, log: log, "OPML Import failed: %@.", error.localizedDescription)
			return nil
		}
		
		return opmlDocument?.children
		
	}
	
	func opmlDocument() -> String {
		let escapedTitle = account.nameForDisplay.rs_stringByEscapingSpecialXMLCharacters()
		let openingText =
		"""
		<?xml version="1.0" encoding="UTF-8"?>
		<!-- OPML generated by NetNewsWire -->
		<opml version="1.1">
		<head>
		<title>\(escapedTitle)</title>
		</head>
		<body>

		"""

		let middleText = account.OPMLString(indentLevel: 0)

		let closingText =
		"""
				</body>
			</opml>
			"""

		let opml = openingText + middleText + closingText
		return opml
	}
	
}