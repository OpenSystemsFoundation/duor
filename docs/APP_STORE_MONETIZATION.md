# Publishing Duor: free with ads + "Remove Ads" purchase

Plan: free download, a banner ad at the bottom of Settings, and a one-time "Remove Ads" in-app purchase for €1–3. This is a common, accepted model and works fine on a personal Apple Developer account. Most of the work is paperwork and privacy, not code.

## 1. Account and legal setup (do this first, it takes days)

- **Sign the Paid Apps Agreement** in App Store Connect and add bank and tax details. It's needed for any in-app purchase, even in a free app.
- **Join the App Store Small Business Program.** Apple then takes 15% of each purchase instead of 30%.
- **EU trader status (Digital Services Act).** Ads plus a purchase almost certainly make you a "trader." On a personal account, your name, address, phone and email are then shown publicly on the EU App Store page. If you don't want your home address shown, sort out a business address first. In the Netherlands, also check whether you need to register with the KvK and how to declare the income.
- **A small website.** You need a privacy policy URL, a support URL, and an `app-ads.txt` file at the site's root for AdMob. A free GitHub Pages site covers all three.

## 2. The "Remove Ads" purchase

- **Type:** a non-consumable in-app purchase (buy once, keep forever, works on all your devices).
- **Price:** €1.99 is the usual sweet spot; €2.99 also works. Pick it from Apple's price points and Apple converts it for other countries.
- **Code:** use StoreKit 2, which needs no extra libraries.
  - `Product.products(for:)` loads the product.
  - `product.purchase()` buys it.
  - `Transaction.currentEntitlements` checks ownership on launch.
  - A `Transaction.updates` listener catches purchases made on another device or approved later through Ask to Buy.
  - SwiftUI's `ProductView` gives you a ready-made buy button.
- **A "Restore Purchases" button is required** by App Review (guideline 3.1.1). Call `AppStore.sync()` from it.
- **Testing:** add a StoreKit configuration file so purchases work in the simulator and in `make test`. Then test real purchases with Sandbox accounts through TestFlight.
- **App Review:** submit the purchase together with the first app version that uses it, including a review screenshot. Make sure the reviewer can find it easily.

## 3. The ads

- **SDK:** Google AdMob (Google Mobile Ads SDK via Swift Package Manager) is the standard choice.
- **Format:** an anchored adaptive banner. In SwiftUI, put it in `.safeAreaInset(edge: .bottom)` on the settings `Form`, so the list scrolls above the banner instead of under it. A banner that floats over content breaks AdMob's rules on accidental clicks. Size it from the available width only (never from the hinge).
- **EU consent is required.** Google requires a certified consent tool for users in the EU/EEA. Use Google's own User Messaging Platform (UMP) SDK. The order is: ask for consent, then start the ad SDK, then load ads.
- **Tracking prompt (ATT):** for personalised ads, add `NSUserTrackingUsageDescription` and show the "Allow tracking?" prompt. The simpler option is to skip it and serve only non-personalised ads, which earn less.
- **If the user has paid, don't start the ad SDK at all.** That's better for privacy and battery, and it avoids any ad audio interfering with the audio engine.
- **Privacy labels need updating.** [PrivacyInfo.xcprivacy](../Duor/Resources/PrivacyInfo.xcprivacy) currently says the app collects nothing. The AdMob SDK ships its own privacy manifest, but the App Store privacy answers must now declare device ID, usage data and advertising data.
- **Use Google's test ad unit IDs during development.** Never tap your own live ads; AdMob bans accounts for it.
- **Don't list the app in the Kids category.** Ads and tracking are heavily restricted there. Something like Entertainment fits.

## 4. What to expect

A banner shown only on the settings screen gets few views, so expect cents to a few euros a month from ads. The ad-free purchase will probably earn more than the ads; in practice the banner mostly gives people a reason to buy. To keep the app privacy-clean and skip the consent and tracking work, a "Remove ads" purchase framed as a tip jar, or a few paid door styles, earns about the same with much less hassle.

## Suggested order

1. Sign the agreements, enrol in the Small Business Program, set trader status.
2. Build the StoreKit 2 purchase with Restore, test it with a StoreKit config file, and add tests.
3. Add AdMob with the UMP consent flow and the bottom banner, shown only when the purchase isn't owned.
4. Update the privacy labels and privacy policy, and publish `app-ads.txt`.
5. Test through TestFlight with a Sandbox account, then submit.
