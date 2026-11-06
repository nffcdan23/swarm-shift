// StoreKitBridge.swift - the StoreKit 2 side of the Godot purchase bridge.
//
// StoreKit 2 is Swift-only, so this file owns every StoreKit call and reports
// back through one Objective-C callback: `handler(event, payload)`, always on
// the main thread. storekit_ios.mm turns those into Godot signals.
//
// Events and payloads (all values are strings, numbers or arrays of strings):
//   "products"       { "products": [ {id, price, title, description, type} ], "invalid": [id] }
//   "products_failed"{ "error" }
//   "purchase"       { "product", "status": "purchased" | "cancelled" | "pending" | "unverified" | "failed",
//                      "transaction_id", "original_id", "jws", "error" }
//   "transaction"    a purchase that arrived on its own: an unfinished one from
//                    a previous launch, an "Ask to Buy" approval, a purchase on
//                    another device. Same keys as "purchase", status "purchased".
//
// Every purchased transaction carries "mine": 1 when this install started it
// (its appAccountToken is this install's token), 0 when it came from another
// device or install of the same Apple account. The game pays currency only for
// its own: the other device already paid it.
//   "revoked"        { "product", "transaction_id" } - refunded or revoked
//   "entitlements"   { "products": [id], "source": "launch" | "restore" }
//   "sync_failed"    { "error" }
//
// Only transactions StoreKit has verified (signed by the App Store for this app
// and device) are ever reported as purchased. A purchased transaction is kept
// unfinished until the game calls finish(transactionId) after it has saved the
// goods, so a crash between payment and saving delivers it again on the next
// launch instead of losing it.

import Foundation
import Security
import StoreKit
import UIKit

@MainActor
@objc(SKBStore)
public final class SKBStore: NSObject {
	@objc public static let shared = SKBStore()

	public typealias Handler = (String, [String: Any]) -> Void

	private var handler: Handler?
	private var products: [String: Product] = [:]
	/// Verified transactions waiting for the game to confirm delivery.
	private var unfinished: [String: Transaction] = [:]
	private var updatesTask: Task<Void, Never>?

	/// Identifies purchases started on this device. Apple returns it on every
	/// transaction the purchase creates, including an "Ask to Buy" approved days
	/// later. Kept in the Keychain as this-device-only, so it survives deleting
	/// and reinstalling the app (an interrupted purchase is still recognised)
	/// but never moves to another phone through a backup.
	private lazy var installToken: UUID = Self.loadToken()

	private static func loadToken() -> UUID {
		let base: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: "com.starscale.swarmshift.storekit",
			kSecAttrAccount as String: "install-token",
		]
		var query = base
		query[kSecReturnData as String] = true
		query[kSecMatchLimit as String] = kSecMatchLimitOne
		var found: CFTypeRef?
		if SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess,
			let data = found as? Data, let text = String(data: data, encoding: .utf8), let token = UUID(uuidString: text) {
			return token
		}
		let fallbackKey = "SKBInstallToken"
		let token = UUID(uuidString: UserDefaults.standard.string(forKey: fallbackKey) ?? "") ?? UUID()
		var add = base
		add[kSecValueData as String] = Data(token.uuidString.utf8)
		add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
		if SecItemAdd(add as CFDictionary, nil) != errSecSuccess {
			// No Keychain (it should not happen): this install's own storage.
			UserDefaults.standard.set(token.uuidString, forKey: fallbackKey)
		}
		return token
	}

	/// Starts listening for transactions. Call once, at launch, before anything
	/// else: Apple delivers pending purchases as soon as there is a listener.
	@objc public func start(_ handler: @escaping Handler) {
		self.handler = handler
		guard updatesTask == nil else { return }
		updatesTask = Task.detached(priority: .background) { [weak self] in
			for await update in Transaction.updates {
				await self?.handle(update, event: "transaction")
			}
		}
		Task {
			// Purchases paid for but never confirmed delivered (the app closed
			// mid-purchase): deliver them again.
			for await pending in Transaction.unfinished {
				await self.handle(pending, event: "transaction")
			}
			await self.reportEntitlements(source: "launch")
		}
	}

	@objc public func loadProducts(_ ids: [String]) {
		Task {
			do {
				let found = try await Product.products(for: ids)
				var list: [[String: Any]] = []
				for product in found {
					products[product.id] = product
					list.append([
						"id": product.id,
						"price": product.displayPrice,
						"title": product.displayName,
						"description": product.description,
						"type": Self.typeName(product.type),
					])
				}
				let invalid = ids.filter { id in !found.contains { $0.id == id } }
				// The App Store country the lookup ran in ("none": no App Store
				// account on the device), for diagnosing products that do not load.
				let storefront = await Storefront.current?.countryCode ?? "none"
				emit("products", ["products": list, "invalid": invalid, "requested": ids, "storefront": storefront])
			} catch {
				emit("products_failed", ["error": error.localizedDescription])
			}
		}
	}

	@objc public func purchase(_ productId: String) {
		Task {
			guard let product = products[productId] else {
				emit("purchase", ["product": productId, "status": "failed", "error": "product_not_loaded"])
				return
			}
			do {
				let options: Set<Product.PurchaseOption> = [.appAccountToken(installToken)]
				// iOS 17 and later want to be told which window the App Store
				// sheet belongs to; without it the sheet may never be shown.
				let result: Product.PurchaseResult
				if #available(iOS 17.0, *), let scene = Self.activeScene() {
					result = try await product.purchase(confirmIn: scene, options: options)
				} else {
					result = try await product.purchase(options: options)
				}
				switch result {
				case .success(let verification):
					switch verification {
					case .verified(let transaction):
						deliver(transaction, jws: verification.jwsRepresentation, event: "purchase")
					case .unverified(_, let error):
						emit("purchase", ["product": productId, "status": "unverified", "error": error.localizedDescription])
					}
				case .userCancelled:
					emit("purchase", ["product": productId, "status": "cancelled"])
				case .pending:
					// Ask to Buy or a payment that needs action: it arrives later
					// through Transaction.updates if it goes through.
					emit("purchase", ["product": productId, "status": "pending"])
				@unknown default:
					emit("purchase", ["product": productId, "status": "failed", "error": "unknown_result"])
				}
			} catch {
				emit("purchase", ["product": productId, "status": "failed", "error": Self.describe(error)])
			}
		}
	}

	/// The game has saved what this transaction bought.
	@objc public func finish(_ transactionId: String) {
		guard let transaction = unfinished.removeValue(forKey: transactionId) else { return }
		Task { await transaction.finish() }
	}

	/// Non-consumables this account owns, from StoreKit's local cache. No sign-in.
	@objc public func requestEntitlements() {
		Task { await reportEntitlements(source: "launch") }
	}

	/// Restore Purchases: syncs with the App Store (may ask the player to sign
	/// in), then reports what the account owns.
	@objc public func sync() {
		Task {
			do {
				try await AppStore.sync()
				await reportEntitlements(source: "restore")
			} catch {
				emit("sync_failed", ["error": Self.describe(error)])
			}
		}
	}

	// MARK: - Internals

	private func handle(_ verification: VerificationResult<Transaction>, event: String) async {
		guard case .verified(let transaction) = verification else { return }
		if transaction.revocationDate != nil {
			emit("revoked", ["product": transaction.productID, "transaction_id": String(transaction.id)])
			await transaction.finish()
			return
		}
		deliver(transaction, jws: verification.jwsRepresentation, event: event)
	}

	private func deliver(_ transaction: Transaction, jws: String, event: String) {
		let id = String(transaction.id)
		DispatchQueue.main.async {
			self.unfinished[id] = transaction
			self.handler?(event, [
				"product": transaction.productID,
				"status": "purchased",
				"transaction_id": id,
				"original_id": String(transaction.originalID),
				"jws": jws,
				"mine": transaction.appAccountToken == self.installToken ? 1 : 0,
			])
		}
	}

	private func reportEntitlements(source: String) async {
		var owned: [String] = []
		for await entitlement in Transaction.currentEntitlements {
			if case .verified(let transaction) = entitlement, transaction.revocationDate == nil {
				owned.append(transaction.productID)
			}
		}
		emit("entitlements", ["products": owned, "source": source])
	}

	/// The app's window scene on screen (the one in front, else any), for the
	/// App Store purchase sheet.
	private static func activeScene() -> UIWindowScene? {
		let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
		return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
	}

	private func emit(_ event: String, _ payload: [String: Any]) {
		DispatchQueue.main.async { self.handler?(event, payload) }
	}

	private static func typeName(_ type: Product.ProductType) -> String {
		switch type {
		case .consumable: return "consumable"
		case .nonConsumable: return "non_consumable"
		case .autoRenewable: return "subscription"
		case .nonRenewable: return "non_renewing"
		default: return "other"
		}
	}

	private static func describe(_ error: Error) -> String {
		if let storeError = error as? StoreKitError {
			switch storeError {
			case .networkError: return "network"
			case .userCancelled: return "cancelled"
			case .notAvailableInStorefront: return "not_available"
			case .notEntitled: return "not_entitled"
			default: break
			}
		}
		if let purchaseError = error as? Product.PurchaseError {
			switch purchaseError {
			case .purchaseNotAllowed: return "not_allowed"
			case .productUnavailable: return "not_available"
			default: break
			}
		}
		return error.localizedDescription
	}
}
