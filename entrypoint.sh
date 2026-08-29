#!/usr/bin/env bash
set -e

echo "[*] Starting Pure Multi-Country Tor Engine..."

BASE_DIR_TOR="/etc/tor/t_sin_nodes"
DATA_DIR_TOR="/var/lib/tor/t_sin_nodes"
TOR_USER="tor"

# لیست پورت‌های SOCKS5 تور برای کشورها
declare -A TOR_NODES=(
    ["IT"]="9089" # ایتالیا
    ["NO"]="9098" # نروژ
    ["DK"]="9099" # دانمارک
    ["NL"]="9100" # هلند
    ["TR"]="9101" # ترکیه
    ["SE"]="9102" # سوئد
)

for code in "${!TOR_NODES[@]}"; do
    port="${TOR_NODES[$code]}"
    inst_dir="$DATA_DIR_TOR/${code}_${port}"
    conf_file="$BASE_DIR_TOR/node_${code}_${port}.conf"

    mkdir -p "$inst_dir"
    chown -R $TOR_USER:$TOR_USER "$inst_dir" "$BASE_DIR_TOR"

    cat <<EOF > "$conf_file"
SocksPort 127.0.0.1:$port
DataDirectory $inst_dir
ExitNodes {$code}
StrictNodes 0
RunAsDaemon 1
Log notice file $inst_dir/notices.log
EOF
    chown $TOR_USER:$TOR_USER "$conf_file"

    echo "[*] Launching Tor Node: $code on SOCKS5 Port $port..."
    su -s /bin/sh $TOR_USER -c "tor -f $conf_file" >/dev/null 2>&1 &
done

exec /app/DockerEntrypoint.sh "$@"
