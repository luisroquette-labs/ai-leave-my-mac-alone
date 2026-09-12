#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
dist_dir="$project_dir/dist"
final_app="$dist_dir/AI, Leave My Mac Alone!.app"
staging_root="$(/usr/bin/mktemp -d "$project_dir/.ai-leave-my-mac-alone-package.XXXXXX")"
staging_app="$staging_root/AI, Leave My Mac Alone!.app"
contents_dir="$staging_app/Contents"

cd "$project_dir"
swift build -c release

/bin/mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources" "$dist_dir"
/bin/cp "$project_dir/.build/release/CleanMyMac" "$contents_dir/MacOS/CleanMyMac"
/bin/cp "$project_dir/Resources/Info.plist" "$contents_dir/Info.plist"
if [[ -f "$project_dir/Resources/AppIcon.icns" ]]; then
    /bin/cp "$project_dir/Resources/AppIcon.icns" "$contents_dir/Resources/AppIcon.icns"
fi
/usr/bin/codesign --force --deep --sign - "$staging_app"
/usr/bin/codesign --verify --deep --strict "$staging_app"

if [[ -e "$final_app" ]]; then
    backup="$dist_dir/.previous-AI-Leave-My-Mac-Alone-$(/bin/date +%Y%m%d-%H%M%S).app"
    /bin/mv "$final_app" "$backup"
fi
/bin/mv "$staging_app" "$final_app"
/bin/rmdir "$staging_root"

if [[ "${1:-}" == "--install" ]]; then
    install_dir="$HOME/Applications/AI, Leave My Mac Alone!.app"
    /bin/mkdir -p "$HOME/Applications"
    if [[ -e "$install_dir" ]]; then
        installed_backup="$dist_dir/.installed-previous-$(/bin/date +%Y%m%d-%H%M%S).app"
        /bin/mv "$install_dir" "$installed_backup"
    fi
    /usr/bin/ditto "$final_app" "$install_dir"
    /usr/bin/codesign --verify --deep --strict "$install_dir"
    print "$install_dir"
else
    print "$final_app"
fi
