# Firestore invitation rule tests

These tests run only against the `demo-together-invites` local emulator project.
They do not sign in to or modify the production Firebase project.

Requirements: Node.js compatible with firebase-tools and Java 21 or later.
From this directory:

```powershell
npm ci
npm test
```

If Java is not on PATH, use the JDK bundled with Android Studio:

```powershell
$env:JAVA_HOME = 'C:/Program Files/Android/Android Studio/jbr'
$env:PATH = "$env:JAVA_HOME/bin;$env:PATH"
npm test
```

The first run downloads the Firestore emulator. Ports 8080, 4400 and 9150 must be free.
The test environment resets only its local demo database between tests.

Coverage: owner issuance; authenticated exact-code lookups; no listing or anonymous
access; expiration, replacement and revocation; repeated and concurrent joins;
member limit; cross-group misuse; membership/ownership tampering; the client
transaction pattern; and preserving existing expense splits after a member joins.
Expected permission-denied messages appear for rejected malicious requests.

The npm dependencies are developer-only test tooling; they are not included in the
Flutter app or its Android APK. The lockfile pins the reproducible toolchain.
