#!/bin/zsh
set -euo pipefail
project_root="${0:A:h}"
exec "$project_root/05_构建工具/build.command" --install
