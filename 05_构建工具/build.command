#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
build_mode="${1:---build-only}"
case "$build_mode" in
    --build-only|--install) ;;
    *) print '用法：build.command [--build-only | --install]'; exit 2 ;;
esac

app_id='local.wechat.practice-assistant'
destination="$HOME/Applications/练琴消息助手.app"
if [[ "$build_mode" == '--install' ]] && /usr/bin/pgrep -x PracticeAssistant >/dev/null; then
    print '请先退出忙碌消息助手，再运行「更新应用.command」。'
    exit 1
fi

cd "$project_root"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' '05_构建工具/Info.plist')
build_root=$(/usr/bin/mktemp -d /tmp/wechat-reply-build.XXXXXX)
app_path="$build_root/练琴消息助手.app"
generated_assets="$build_root/GeneratedAssets"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources" "$generated_assets"

# Work outside Desktop/iCloud while signing to avoid inherited resource forks.
/usr/bin/xcrun swiftc '04_资源/MakeIcon.swift' -o "$build_root/make-icon" -framework Cocoa
"$build_root/make-icon" "$generated_assets/AppIconPreview.png"
/usr/bin/sips -z 1024 1024 "$generated_assets/AppIconPreview.png" >/dev/null
iconset="$build_root/AppIcon.iconset"
mkdir -p "$iconset"
for icon_size in 16 32 128 256 512; do
    /usr/bin/sips -z "$icon_size" "$icon_size" "$generated_assets/AppIconPreview.png" --out "$iconset/icon_${icon_size}x${icon_size}.png" >/dev/null
    double_size=$((icon_size * 2))
    /usr/bin/sips -z "$double_size" "$double_size" "$generated_assets/AppIconPreview.png" --out "$iconset/icon_${icon_size}x${icon_size}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$iconset" -o "$generated_assets/AppIcon.icns"
cp "$generated_assets/AppIcon.icns" "$generated_assets/AppIconPreview.png" "$app_path/Contents/Resources/"

source_files=(
    '02_源码/Core.swift'
    '02_源码/ReaderQueue.swift'
    '02_源码/Profile.swift'
    '02_源码/Conversation.swift'
    '02_源码/Activity.swift'
    '02_源码/Engine.swift'
    '02_源码/UI.swift'
    '02_源码/Main.swift'
    '03_测试/BasicRulesTests.swift'
    '03_测试/RegressionTests.swift'
    '03_测试/ProfileTests.swift'
    '03_测试/ConversationTests.swift'
    '03_测试/FirstScreenTests.swift'
    '03_测试/ActivityTests.swift'
)
/usr/bin/xcrun swiftc -swift-version 5 -O "${source_files[@]}" \
    -o "$app_path/Contents/MacOS/PracticeAssistant" \
    -framework Cocoa -framework SwiftUI -framework ApplicationServices -framework Security
cp '05_构建工具/Info.plist' "$app_path/Contents/Info.plist"
/usr/bin/xattr -cr "$app_path"
/usr/bin/codesign --force --sign - --identifier "$app_id" "$app_path"

# In-memory tests only: no WeChat messages, Keychain reads or network requests.
"$app_path/Contents/MacOS/PracticeAssistant" --self-test
/usr/bin/codesign --verify --deep --strict "$app_path"

# Verify the portable archive before Desktop/iCloud can attach Finder metadata.
archive_path="$build_root/消息回复助手_v${version}.zip"
/usr/bin/ditto -c -k --norsrc --noextattr --keepParent "$app_path" "$archive_path"
archive_check="$build_root/ArchiveCheck"
/usr/bin/ditto -x -k "$archive_path" "$archive_check"
/usr/bin/codesign --verify --deep --strict "$archive_check/练琴消息助手.app"
/bin/rm -r "$archive_check"

product_name="v${version}_$(/bin/date +%Y-%m-%d_%H-%M-%S)_${build_root:t}"
product_dir="$project_root/06_发布版本/构建产物/$product_name"
mkdir -p "${product_dir:h}"
/bin/mv "$build_root" "$product_dir"
product_app="$product_dir/练琴消息助手.app"
/usr/bin/xattr -cr "$product_app"
/bin/ln -sfn "构建产物/$product_name" "$project_root/06_发布版本/最新构建"
print "编译、测试与签名检查通过：$product_app"

if [[ "$build_mode" == '--build-only' ]]; then
    print '已生成待安装版本。日常使用的应用保持原样。'
    exit 0
fi

# Do not replace an unrelated application or a running copy.
if /usr/bin/pgrep -x PracticeAssistant >/dev/null; then
    print '助手在编译期间被打开，请先退出再更新。待安装版本已保留。'
    exit 1
fi
if [[ -e "$destination" ]]; then
    existing_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$destination/Contents/Info.plist")
    [[ "$existing_id" == "$app_id" ]] || { print '安装位置已有其他应用，未覆盖。'; exit 1; }
    installed_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$destination/Contents/Info.plist")
    rollback_dir="$project_root/06_发布版本/更新前备份/v${installed_version}_$(/bin/date +%Y-%m-%d_%H-%M-%S)"
    mkdir -p "$rollback_dir"
    /usr/bin/ditto --noextattr "$destination" "$rollback_dir/练琴消息助手.app"
    /usr/bin/ditto -c -k --norsrc --noextattr --keepParent "$destination" "$rollback_dir/消息回复助手_v${installed_version}.zip"
fi
mkdir -p "${destination:h}"
# Install from the verified archive, never from a metadata-modified Desktop copy.
install_root=$(/usr/bin/mktemp -d /tmp/wechat-reply-install.XXXXXX)
/usr/bin/ditto -x -k "$product_dir/消息回复助手_v${version}.zip" "$install_root"
/usr/bin/codesign --verify --deep --strict "$install_root/练琴消息助手.app"
/usr/bin/ditto --noextattr "$install_root/练琴消息助手.app" "$destination"
/usr/bin/xattr -cr "$destination"
/usr/bin/codesign --verify --deep --strict "$destination"
/bin/rm -r "$install_root"
print "应用已更新：$destination"
print '更新后若微信权限失效，在辅助功能中重新添加这个应用并重启即可。'
