#!/usr/bin/env bash
#
# Generates the iOS and Android platform folders for this project.
#
# The repository holds only the Dart source. `flutter create` is what produces
# ios/ and android/ — but it also wants to scaffold its own lib/main.dart and
# pubspec.yaml over the top of the real ones, so this backs the source up,
# lets it generate the platform folders, then puts the source back.
#
# Safe to re-run. Nothing here touches your logged data, which lives on the
# phone rather than in the repository.
#
# Usage:
#   ./tool/bootstrap.sh
#   ORG=com.yourname ./tool/bootstrap.sh    # your own bundle identifier prefix

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

# A free Apple ID will not sign a bundle identifier somebody else has already
# used, so override ORG if the default is taken.
ORG="${ORG:-com.hydrafuel}"
PROJECT_NAME="hydrafuel"

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter is not on your PATH." >&2
  echo "Install it first: https://docs.flutter.dev/get-started/install/macos" >&2
  exit 1
fi

# Files flutter create will overwrite if they are in its way.
BACKED_UP=(lib test pubspec.yaml analysis_options.yaml .gitignore README.md)

BACKUP="$(mktemp -d)"
RESTORED=0

restore() {
  [ "$RESTORED" = 1 ] && return 0
  RESTORED=1
  for item in "${BACKED_UP[@]}"; do
    if [ -e "$BACKUP/$item" ]; then
      rm -rf "${ROOT:?}/$item"
      cp -R "$BACKUP/$item" "$ROOT/$item"
    fi
  done
}

# If anything below fails, put the source back before exiting. Without this a
# failure between the delete and the copy would leave the checkout gutted.
trap 'restore; echo; echo "Bootstrap failed. Your source has been restored." >&2' ERR
trap 'rm -rf "$BACKUP"' EXIT

echo "==> Backing up source to $BACKUP"
for item in "${BACKED_UP[@]}"; do
  if [ -e "$item" ]; then
    cp -R "$item" "$BACKUP/$item"
  fi
done

echo "==> Generating platform folders (org: $ORG)"
flutter create \
  --project-name "$PROJECT_NAME" \
  --org "$ORG" \
  --platforms=ios,android \
  "$ROOT"

echo "==> Restoring source"
restore
trap - ERR

# flutter create leaves a default widget test for the counter app template,
# which this project does not have.
rm -f test/widget_test.dart

# flutter_local_notifications needs the notification centre delegate set, or
# a reminder that fires while the app is open is delivered silently and never
# appears. The default template does not set it.
APP_DELEGATE="ios/Runner/AppDelegate.swift"
if [ -f "$APP_DELEGATE" ]; then
  if grep -q "UNUserNotificationCenter.current().delegate" "$APP_DELEGATE"; then
    echo "==> AppDelegate already sets the notification delegate"
  else
    echo "==> Patching AppDelegate for foreground notifications"
    awk '
      /GeneratedPluginRegistrant\.register\(with: self\)/ && !inserted {
        print "    // Required by flutter_local_notifications: without this a"
        print "    // reminder that fires while the app is open never appears."
        print "    if #available(iOS 10.0, *) {"
        print "      UNUserNotificationCenter.current().delegate ="
        print "          self as? UNUserNotificationCenterDelegate"
        print "    }"
        print ""
        inserted = 1
      }
      { print }
    ' "$APP_DELEGATE" > "$APP_DELEGATE.tmp" && mv "$APP_DELEGATE.tmp" "$APP_DELEGATE"
  fi
fi

echo "==> Fetching packages"
flutter pub get

echo "==> Installing iOS pods"
if command -v pod >/dev/null 2>&1; then
  (cd ios && pod install)
else
  echo "    CocoaPods is not installed. Run: sudo gem install cocoapods"
  echo "    then: cd ios && pod install"
fi

echo
echo "==> Done."
echo
echo "Connected devices:"
flutter devices || true
echo
echo "Next:"
echo "  1. flutter test            # the full suite, no device needed"
echo "  2. open ios/Runner.xcworkspace"
echo "     Runner target > Signing & Capabilities > Team = your Apple ID."
echo "     Change the Bundle Identifier if Xcode says it is taken."
echo "  3. flutter run             # builds and installs on the phone"
echo
echo "On the iPhone, first time only:"
echo "  - Settings > Privacy & Security > Developer Mode > On, then restart."
echo "  - After the first install: Settings > General >"
echo "    VPN & Device Management > your Apple ID > Trust."
