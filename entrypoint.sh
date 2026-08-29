#!/usr/bin/env bash
set -e

echo "[*] Starting Smart Hybrid Routing Engine (Tor + Psiphon with Bootstrap Servers)..."

# ========================================================
# 1. راه‌اندازی Tor (ایتالیا، نروژ، دانمارک)
# ========================================================
BASE_DIR_TOR="/etc/tor/t_sin_nodes"
DATA_DIR_TOR="/var/lib/tor/t_sin_nodes"
TOR_USER="tor"

declare -A TOR_NODES=(
    ["IT"]="9089"
    ["NO"]="9098"
    ["DK"]="9099"
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

# ========================================================
# 2. راه‌اندازی سایفون با دیتابیس سرورهای اولیه (دانمارک، ایتالیا، نروژ)
# ========================================================
if command -v psiphon-tunnel-core &> /dev/null; then
    echo "[*] Launching Psiphon Engine with Embedded Server List..."
    BASE_DIR_PSI="/etc/psiphon"
    DATA_DIR_PSI="/var/lib/psiphon"

    declare -A PSI_NODES=(
        ["DK"]="9100"
        ["IT"]="9101"
        ["NO"]="9102"
    )

    for code in "${!PSI_NODES[@]}"; do
        port="${PSI_NODES[$code]}"
        inst_dir="$DATA_DIR_PSI/${code}_${port}"
        conf_file="$BASE_DIR_PSI/psiphon_${code}_${port}.json"

        mkdir -p "$inst_dir"

        if [ -f "/app/psiphon-src/config.json" ]; then
            jq --arg region "$code" \
               --argport "$port" \
               --arg datadir "$inst_dir" \
               '. + {EgressRegion: $region, LocalSocksProxyPort: ($port | tonumber), DataStoreDirectory: $datadir}' \
               /app/psiphon-src/config.json > "$conf_file"
        else
            cat <<EOF > "$conf_file"
{
  "EgressRegion": "$code",
  "LocalSocksProxyPort": $port,
  "DataStoreDirectory": "$inst_dir"
}
EOF
        fi

        echo "[*] Launching Psiphon Node: $code on SOCKS5 Port $port..."
        psiphon-tunnel-core --config "$conf_file" >/dev/null 2>&1 &
    done
else
    echo "[!] Psiphon binary not found, skipping Psiphon launch."
fi

# ========================================================
# 3. اجرای ورودی اصلی پنل
# ========================================================
exec /app/DockerEntrypoint.sh "$@"
