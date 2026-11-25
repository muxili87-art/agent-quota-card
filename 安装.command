#!/bin/zsh
set -euo pipefail
dir="${0:A:h}"
src="$dir/app/dist/Agent 额度.app"
dst="/Applications/Agent 额度.app"

if [[ ! -d "$src" ]]; then
  "$dir/app/Scripts/build-app.sh"
fi

pkill -x AgentQuotaCard >/dev/null 2>&1 || true
rm -rf "$dst"
cp -R "$src" "$dst"
ln -sfn "$dst" "$HOME/Desktop/Agent 额度.app"
open "$dst"
echo "已安装并启动：$dst"
