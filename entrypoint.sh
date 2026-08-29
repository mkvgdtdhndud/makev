#!/usr/bin/env bash
set -e

echo "[*] Starting Smart Hybrid Routing Engine (Tor + Psiphon)..."

# ========================================================
# 1. راه‌اندازی نودهای Tor (پورت‌های 9080 تا 9088)
# ========================================================
BASE_DIR_TOR="/etc/tor/t_sin_nodes"
DATA_DIR_TOR="/var/lib/tor/t_sin_nodes"
TOR_USER="tor"

declare -A TOR_NODES=(
    ["DK"]="9099" ["IT"]="9089" ["NO"]="9098"
)

for code in "${!TOR_NODES[@]}"; do
    port="${TOR_NODES[$code]}"
    inst_dir="$DATA_DIR_TOR/${code}_${port}"
    conf_file="$BASE_DIR_TOR/node_${code}_${port}.conf"

    mkdir -p "$inst_dir"
    chown -R $TOR_USER:$TOR_USER "$inst_dir"

    cat <<EOF > "$conf_file"
SocksPort 127.0.0.1:$port
DataDirectory $inst_dir
ExitNodes {$code}
StrictNodes 1
RunAsDaemon 1
Log notice file $inst_dir/notices.log
EOF
    chown $TOR_USER:$TOR_USER "$conf_file"

    echo "[*] Launching Tor Node: $code on SOCKS5 Port $port..."
    su -s /bin/sh $TOR_USER -c "tor -f $conf_file" >/dev/null 2>&1 &
    
    (
        clean_attempts=0
        max_attempts=3
        while [ $clean_attempts -lt $max_attempts ]; do
            sleep 6
            public_ip=$(curl -s --socks5-hostname 127.0.0.1:$port https://api.ipify.org --max-time 10 || true)
            if [[ "$public_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                api_resp=$(curl -s "https://api.ipapi.is/?q=$public_ip" --max-time 10 || true)
                if echo "$api_resp" | grep -iq '"abuser_score".*High'; then
                    clean_attempts=$((clean_attempts+1))
                    echo "[-] Tor IP $public_ip for $code is High Risk! Requesting new IP..."
                    pkill -f "$conf_file" 2>/dev/null || true
                    su -s /bin/sh $TOR_USER -c "tor -f $conf_file" >/dev/null 2>&1 &
                else
                    echo "[+] Tor Node $code connected with Clean IP: $public_ip"
                    break
                fi
            fi
        done
    ) &
done

# ========================================================
# 2. راه‌اندازی نودهای سایفون (پورت‌های 9100 تا 9108)
# ========================================================
if command -v psiphon-tunnel-core &> /dev/null; then
    echo "[*] Launching Psiphon Engine..."
    BASE_DIR_PSI="/etc/psiphon"
    DATA_DIR_PSI="/var/lib/psiphon"

    declare -A PSI_NODES=(
        ["DK"]="9100" ["IT"]="9101" ["NO"]="9102"
    )

    for code in "${!PSI_NODES[@]}"; do
        port="${PSI_NODES[$code]}"
        inst_dir="$DATA_DIR_PSI/${code}_${port}"
        conf_file="$BASE_DIR_PSI/psiphon_${code}_${port}.json"

        mkdir -p "$inst_dir"

        cat <<EOF > "$conf_file"
{
  "EgressRegion": "$code",
  "LocalSocksProxyPort": $port,
  "DataStoreDirectory": "$inst_dir"
}
EOF

        echo "[*] Launching Psiphon Node: $code on SOCKS5 Port $port..."
        psiphon-tunnel-core --config "$conf_file" >/dev/null 2>&1 &
    done
else
    echo "[!] Psiphon binary not found, skipping Psiphon launch."
fi

# ========================================================
# 3. اجرای ورودی اصلی داکر پنل
# ========================================================
exec /app/DockerEntrypoint.sh "$@"
