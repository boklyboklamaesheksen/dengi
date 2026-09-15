#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
python3 tools/generate_localizations.py --check
python3 tools/check_release_metadata.py
git diff --check
