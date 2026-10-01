#!/bin/zsh
set -euo pipefail
installed_app="$HOME/Applications/练琴消息助手.app"
if [[ ! -d "$installed_app" ]]; then
    print '还没有安装应用，请先运行本文件夹中的「更新应用.command」。'
    exit 1
fi
app_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$installed_app/Contents/Info.plist")
[[ "$app_id" == 'local.wechat.practice-assistant' ]] || { print '安装位置对应其他应用，未打开。'; exit 1; }
/usr/bin/open "$installed_app"
