# Isosmart Photos Android App

Fork of Immich mobile (`mobile/` directory) branded as **Isosmart Photos** (`online.isosmart.photos`).

Upstream Immich: `https://github.com/immich-app/immich` (pinned base: `v3.3.6`).

## Rules
- GitHub Actions does all builds (`.github/workflows/app.yml`).
- Push to `main` builds APK artifact. Tag `vX.Y.Z-iso.N` builds and signs production release.
- Application ID: `online.isosmart.photos`.
- Dart/Kotlin package namespaces stay `app.alextran.immich` to keep upstream merges clean.
- Signing key: PKCS12 `PHOTOS_APP_KEYSTORE_B64`, alias `isosmart`. Stored in laptop vault + GitHub secrets only.
  - Release cert SHA-256: `bf1e1ddab512246b20e353462c27302e30b3e8c5155d9f28c92420652cc2c629`.
- Version scheme: `major.minor.patch-iso.build` (e.g. `3.3.6-iso.1`).
- Server gate: Sync job checks `https://photos.isosmart.online/api/server/version`. Never release app version ahead of server.
