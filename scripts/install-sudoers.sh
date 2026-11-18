#!/usr/bin/env bash
# 安装 sudoers 白名单：只允许免密执行两条精确的 pmset 命令
#   sudo pmset -a disablesleep 1
#   sudo pmset -a disablesleep 0
# 这样 App 调用 `sudo -n` 就不会每次弹密码框。整个文件的撤销方式见末尾。
set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
  echo "请用 sudo 运行: sudo ./scripts/install-sudoers.sh"
  exit 1
fi

USER_NAME="${SUDO_USER:-$(logname 2>/dev/null || echo lonqi)}"
FILE="/etc/sudoers.d/roadmode"

cat > "$FILE" <<EOF
# RoadMode: 只白名单这两条精确参数的 pmset，其它 sudo 命令仍需密码
$USER_NAME ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0
EOF

chmod 440 "$FILE"
chown root:wheel "$FILE"
visudo -c -f "$FILE" >/dev/null

echo "已写入 $FILE ，内容:"
cat "$FILE"
echo
echo "验证: sudo -n /usr/bin/pmset -a disablesleep 0 && echo OK"
echo "撤销: sudo rm $FILE"
