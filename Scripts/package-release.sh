#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
version="$(<"$project_dir/VERSION")"
archive="$project_dir/release/AI-Leave-My-Mac-Alone-$version.zip"
stable_archive="$project_dir/release/AI-Leave-My-Mac-Alone.zip"

cd "$project_dir"
./Scripts/preflight.sh
/bin/mkdir -p release
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "dist/AI, Leave My Mac Alone!.app" "$archive"
/bin/cp "$archive" "$stable_archive"
(cd release && /usr/bin/shasum -a 256 "AI-Leave-My-Mac-Alone-$version.zip" > "AI-Leave-My-Mac-Alone-$version.zip.sha256")
[[ "$(<"$archive.sha256")" == *"  AI-Leave-My-Mac-Alone-$version.zip" ]] || {
    print -u2 "Checksum contains a non-portable path"
    exit 1
}
print "$archive"
