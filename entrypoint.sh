#!/usr/bin/env bash
set -e

echo "[*] Starting Smart Tor Automation Engine for Railway (Alpine Environment)..."

BASE_DIR="/etc/tor/t_sin_nodes"
DATA_DIR="/var/lib/tor/t_sin_nodes"
TOR_USER="tor"

# لیست کشورها و پورت‌های خروجی Tor
declare -A NODES=(
    ["DE"]="9080" ["TR"]="9081" ["US"]="9082" 
    ["FR"]="9083" ["NL"]="9084" ["GB"]="9085"
    ["CA"]="9086" ["FI"]="9087" ["ES"]="9088"
    ["IT"]="9089" ["NO"]="9098" ["CH"]="9091"
)

for code in "${!NODES[@]}"; do
    port="${NODES[$code]}"
    inst_dir="$DATA_DIR/${code}_${port}"
    conf_file="$BASE_DIR/node_${code}_${port}.conf"

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
    
    # تست و بررسی خودکار آی‌پی تمیز
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
                    echo "[-] IP $public_ip for $code is High Risk! Requesting new IP..."
                    pkill -f "$conf_file" 2>/dev/null || true
                    su -s /bin/sh $TOR_USER -c "tor -f $conf_file" >/dev/null 2>&1 &
                else
                    echo "[+] Node $code connected with Clean IP: $public_ip"
                    break
                fi
            fi
        done
    ) &
done

# اجرای ورودی اصلی داکر پنل بدون ایجاد اختلال
exec /app/DockerEntrypoint.sh "$@"
