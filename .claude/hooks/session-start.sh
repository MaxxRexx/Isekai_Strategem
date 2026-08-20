#!/bin/bash
# Gets a Claude Code on the web session ready to actually run this project.
#
# Without this, a session starts with no Dart or Flutter at all, so the first
# `flutter test` fails and the toolchain has to be installed by hand before any
# work can be verified. Installing it here costs the session start a few
# minutes once and then nothing, because the container is cached afterwards.
#
# Pinned to the same Flutter version the deploy workflow uses, so what passes
# here is what passes in CI.
set -euo pipefail

# Local machines have their own toolchains; this is only for the web sessions.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

FLUTTER_VERSION="3.44.4"
FLUTTER_DIR="${HOME}/flutter"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# 1. Flutter itself, which brings Dart with it.
if [ ! -x "${FLUTTER_DIR}/bin/flutter" ]; then
  echo "Installing Flutter ${FLUTTER_VERSION}..."
  rm -rf "${FLUTTER_DIR}"
  git clone --depth 1 --branch "${FLUTTER_VERSION}" \
    https://github.com/flutter/flutter.git "${FLUTTER_DIR}"
else
  echo "Flutter already present at ${FLUTTER_DIR}"
fi

export PATH="${FLUTTER_DIR}/bin:${PATH}"

# git refuses to work in a directory it thinks someone else owns, and Flutter
# shells out to git constantly to work out its own version.
git config --global --add safe.directory "${FLUTTER_DIR}" 2>/dev/null || true

# 2. Warm the SDK. The first invocation builds the Dart snapshots, which is
#    slow; doing it here means the first real command in the session is fast.
flutter --version

# 3. Dependencies for both packages. `pub get` rather than anything stricter,
#    so the cached container can reuse what it already downloaded.
echo "Fetching battle_engine dependencies..."
(cd "${PROJECT_DIR}/packages/battle_engine" && dart pub get)

echo "Fetching app dependencies..."
(cd "${PROJECT_DIR}/app" && flutter pub get)

# 4. Keep Flutter on PATH for the rest of the session.
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PATH=\"${FLUTTER_DIR}/bin:\${PATH}\"" >> "${CLAUDE_ENV_FILE}"
  # Chromium is preinstalled; point Playwright at it rather than downloading.
  echo 'export PLAYWRIGHT_BROWSERS_PATH="/opt/pw-browsers"' >> "${CLAUDE_ENV_FILE}"
fi

echo "Ready: dart test in packages/battle_engine, flutter test in app."
