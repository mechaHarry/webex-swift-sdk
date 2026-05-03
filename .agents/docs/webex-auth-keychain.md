# Webex Auth And Keychain Notes

The SDK stores user-provided Webex integration credentials and refresh-token
records in Keychain through `KeychainWebexStore`.

## macOS Keychain Storage Mode

`KeychainWebexStore` defaults to `.automatic` storage:

- Resolve the usable keychain path with a non-secret Data Protection probe the
  first time the store touches Keychain.
- Use the macOS Data Protection keychain path when the probe succeeds by adding
  `kSecUseDataProtectionKeychain: true` to add, load, update, and delete query
  dictionaries.
- Use the legacy keychain path when the Data Protection probe or operation fails
  with the missing-entitlement status observed as `-34018` or `34018`.
- Do not fall back on auth failures, decode failures, cancellation, or other
  security-relevant statuses.
- Keep `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` on added records.
- Do not add user-presence, biometrics, or application-password
  `SecAccessControl` flags for SDK credential/refresh-token records unless the
  SDK explicitly wants local user approval on every read.

The Data Protection keychain path is preferred because it is closer to
iOS-style SecItem semantics and avoids legacy ACL prompts for normal token
lifecycle reads. It may require the host process to be a properly signed and
entitled macOS app. Unsigned SwiftPM/debug smoke executables can hit status
`34018`; `.automatic` exists so those tools remain usable by falling back to the
legacy keychain.

The legacy macOS keychain path can attach ACL behavior to generic password
items. In SwiftPM/debug smoke clients this can show repeated local password
prompts even after the user selects "Always Allow", because the executable
identity can change across rebuilds and runs.

## Existing Legacy Records

Records may exist in both the Data Protection and legacy keychain paths for the
same `WEBEX_KEYCHAIN_SERVICE`. `.automatic` loads from Data Protection first. If
Data Protection is available and the item is absent, the SDK treats the item as
absent instead of probing legacy storage. Legacy is used only when the process
cannot use Data Protection keychain operations.

For released app flows that need deterministic behavior, prefer an explicitly
signed and entitled host app and consider constructing `KeychainWebexStore` with
`.dataProtection`. If migration is ever needed for a released app, make it
explicit and one-time instead of treating every read as a broad compatibility
scan.
