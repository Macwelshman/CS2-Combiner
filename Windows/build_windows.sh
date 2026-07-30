#!/bin/bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "$script_dir/.." && pwd)"
app_project="$script_dir/CS2Combiner.App/CS2Combiner.App.csproj"
test_project="$script_dir/CS2Combiner.Tests/CS2Combiner.Tests.csproj"
dist_dir="$repo_dir/dist/windows"
version="0.2.2"

cd "$repo_dir"

dotnet test "$test_project" \
  --configuration Release \
  --disable-build-servers

mkdir -p "$dist_dir"

for runtime in win-arm64 win-x64; do
  publish_dir="$dist_dir/$runtime"
  archive="$dist_dir/CS2-Combiner-$version-windows-${runtime#win-}.zip"

  rm -rf "$publish_dir"
  dotnet publish "$app_project" \
    --configuration Release \
    --runtime "$runtime" \
    --self-contained true \
    --disable-build-servers \
    --output "$publish_dir"

  cp "$script_dir/README.md" "$publish_dir/README-Windows.md"
  cp "$script_dir/THIRD-PARTY-NOTICES.md" "$publish_dir/THIRD-PARTY-NOTICES.md"
  rm -f "$archive"
  (
    cd "$publish_dir"
    /usr/bin/zip -qry "$archive" .
  )
  /usr/bin/unzip -tq "$archive"
done

echo "WINDOWS_PACKAGES_OK"
