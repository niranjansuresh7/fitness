#!/usr/bin/env bash
#
# Generates the iOS (and Android) platform folders for this project.
#
# `flutter create` wants to scaffold a whole app including lib/main.dart, so
# this backs up the hand-written code first, lets it generate only the platform
# directories, then puts the code back. Safe to re-run.

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
BACKUP="$(mktemp -d)"

echo "==> Backing up source to $BACKUP"
cp -R lib "$BACKUP/lib"
cp -R test "$BACKUP/test"
cp pubspec.yaml "$BACKUP/pubspec.yaml"
[ -f analysis_options.yaml ] && cp analysis_options.yaml "$BACKUP/analysis_options.yaml"

echo "==> Generating platform folders"
flutter create \
  --project-name hydrafuel \
  --org com.hydrafuel \
  --platforms=ios,android \
  "$ROOT"

echo "==> Restoring source"
rm -rf lib test
cp -R "$BACKUP/lib" lib
cp -R "$BACKUP/test" test
cp "$BACKUP/pubspec.yaml" pubspec.yaml
[ -f "$BACKUP/analysis_options.yaml" ] && cp "$BACKUP/analysis_options.yaml" analysis_options.yaml

# flutter create leaves a default widget test that references a counter app
# this project does not have.
rm -f test/widget_test.dart

echo "==> Fetching packages"
flutter pub get

echo "==> Done. Next:"
echo "    flutter test          # 100+ tests, all offline"
echo "    flutter devices       # check your iPhone is listed"
echo "    flutter run           # builds and installs"
echo
echo "    If Xcode asks for a signing team, open ios/Runner.xcworkspace,"
echo "    select the Runner target, and pick your Apple ID under"
echo "    Signing & Capabilities."

rm -rf "$BACKUP"
