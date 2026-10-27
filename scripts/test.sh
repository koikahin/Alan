#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_dir"
build_dir="$repo_dir/.build"
mkdir -p "$build_dir/module-cache"
target="$(uname -m)-apple-macos15.7"

swiftc -parse-as-library -swift-version 5 -default-isolation MainActor \
    -target "$target" -module-cache-path "$build_dir/module-cache" \
    Alan/WindowGeometry.swift Alan/AccessibilityWindow.swift Tests/RegressionTests.swift \
    -o "$build_dir/regression-tests"
"$build_dir/regression-tests"

# Compile and link the entire app with the same default actor isolation as the
# Xcode project. Compiling the app's XIB resources still requires full Xcode.
swiftc -parse-as-library -swift-version 5 -default-isolation MainActor \
    -target "$target" -module-cache-path "$build_dir/module-cache" \
    Alan/*.swift -o "$build_dir/Alan"
printf 'App source compiled and linked successfully.\n'
