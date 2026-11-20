#!/bin/bash

# Cháº·n needrestart tá»± Ã½ restart card máº¡ng vÃ  SSH daemon lÃ m rá»›t káº¿t ná»‘i
export DEBIAN_FRONTEND=noninteractive
mkdir -p /etc/needrestart/conf.d 2>/dev/null
echo '$nrconf{restart} = "l";' > /etc/needrestart/conf.d/no-restart.conf 2>/dev/null

# Tá»± Ä‘á»™ng giáº£i phÃ³ng khÃ³a apt/dpkg náº¿u VPS Ä‘ang cháº¡y cáº­p nháº­t ngáº§m (unattended-upgrades)
systemctl stop unattended-upgrades 2>/dev/null
killall -9 apt apt-get unattended-upgrade unattended-upgr 2>/dev/null
rm -f /var/lib/dpkg/lock* /var/lib/apt/lists/lock* /var/cache/apt/archives/lock* 2>/dev/null
dpkg --configure -a 2>/dev/null

# === CRLF Auto-Fix ===
if [ -z "$_CRLF_FIXED" ]; then
  _TMPSCRIPT=$(mktemp /tmp/phuonglien4g.XXXXXX.sh)
  cat "$0" | tr -d '\r' > "$_TMPSCRIPT"
  export _CRLF_FIXED=1
  bash "$_TMPSCRIPT" "$@"
  _RET=$?
  rm -f "$_TMPSCRIPT"
  exit $_RET
fi

# === Phân tích tham số dòng lệnh ===
API_HOST=""
API_KEY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --api-host|-h)
      API_HOST="$2"
      shift 2
      ;;
    --api-key|-k)
      API_KEY="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

function check_api_config(){
  if [ -z "$API_HOST" ]; then
    echo ""
    echo -e "   \033[0;33mVui lòng nhập thông tin kết nối V2Board Panel:\033[0m"
    read -p "   Domain Web Panel (Ví dụ: https://global.phuonglien4g.com): " API_HOST
  fi
  API_HOST=$(echo "$API_HOST" | sed 's:/*$::')

  if [ -z "$API_KEY" ]; then
    read -p "   Server Token (ApiKey): " API_KEY
  fi
}

function ask_cert_config(){
  echo ""
  echo "   Chon kieu chung chi SSL cho cong 443:"
  echo "   1. HTTP (Tu dong xin chung chi Lets Encrypt)"
  echo "   2. File (Dung chung chi vn.speed4g.me co san)"
  read -p "   Vui Long Chon [1/2]: " cert_choice
  cert_choice=$(echo "$cert_choice" | sed 's/[^12]//g')

  if [ "$cert_choice" == "1" ]; then
    read -p "   Nhap ten mien can xin chung chi: " cert_domain
    # Loc sach ky tu la tu ban phim tieng Viet (chi giu a-z 0-9 . -)
    cert_domain=$(echo "$cert_domain" | sed 's/[^a-zA-Z0-9._-]//g')
    [ -z "${cert_domain}" ] && cert_domain="example.com"
    cert_mode="http"
    cert_file="/etc/XrayR/cert/${cert_domain}.cert"
    key_file="/etc/XrayR/cert/${cert_domain}.key"
    echo "   Chung chi moi se tu dong xin cho: $cert_domain"
  else
    cert_mode="file"
    cert_domain="vn.speed4g.me"
    cert_file="/etc/XrayR/speed4g.crt"
    key_file="/etc/XrayR/speed4g.key"
  fi
}

# Xin chung chi TRUOC khi cai XrayR (cong 80 con trong)
function obtain_cert(){
  if [ "$cert_mode" == "http" ]; then
    mkdir -p /etc/XrayR/cert/

    # Dung XrayR neu dang chay de giai phong cong 80
    systemctl stop XrayR 2>/dev/null
    sleep 1

    # Cai dat acme.sh neu chua co
    if [ ! -f /root/.acme.sh/acme.sh ]; then
      echo "   Dang cai dat acme.sh..."
      curl https://get.acme.sh | sh 2>/dev/null
      source /root/.bashrc 2>/dev/null
    fi

    # Dat Lets Encrypt lam CA mac dinh
    /root/.acme.sh/acme.sh --set-default-ca --server letsencrypt 2>/dev/null

    # Xin chung chi qua standalone mode (dung cong 80 tam thoi)
    # pre-hook/post-hook: tu dong dung/khoi dong XrayR khi gia han (moi 60 ngay)
    echo "   Dang xin chung chi Lets Encrypt cho: $cert_domain ..."
    /root/.acme.sh/acme.sh --issue -d $cert_domain --standalone --httpport 80 --force \
      --pre-hook "systemctl stop XrayR" \
      --post-hook "systemctl start XrayR"

    # Cai chung chi vao thu muc XrayR (reloadcmd: tu dong restart khi gia han)
    /root/.acme.sh/acme.sh --install-cert -d $cert_domain \
      --cert-file $cert_file \
      --key-file $key_file \
      --fullchain-file /etc/XrayR/cert/${cert_domain}.fullchain.cert \
      --reloadcmd "systemctl restart XrayR"

    if [ -f "$cert_file" ] && [ -f "$key_file" ]; then
      echo "   OK Xin chung chi thanh cong cho: $cert_domain"
      cert_mode="file"
    else
      echo "   LOI Xin chung chi that bai! Su dung chung chi mac dinh speed4g."
      cert_mode="file"
      cert_domain="vn.speed4g.me"
      cert_file="/etc/XrayR/speed4g.crt"
      key_file="/etc/XrayR/speed4g.key"
    fi
  fi
}

function run_install(){
  echo "   [XrayR Core] Đang cài đặt XrayR v0.9.6-VN (Việt Hóa, ML-KEM, Tối ưu RAM)..."
  local install_url="https://raw.githubusercontent.com/hqp1310/XrayR/main/install.sh"
  if ! curl -sfI "$install_url" >/dev/null 2>&1; then
    if [ -n "$API_HOST" ]; then
      install_url="${API_HOST}/xraywarp/install.sh"
    else
      install_url="https://phuonglien4g.com/xraywarp/install.sh"
    fi
  fi
  curl -Ls "$install_url" | tr -d '\r' | bash -s -- --only-binary
}

function ask_warp(){
  echo ""
  echo "   Tuy chon an IP VPS bang Cloudflare WARP (Khuyen dung):"
  echo "   1. Cai dat warp-cli (Ping thap, add duoc Key WARP+, tu dong reset chong nghen moi 1 tieng)"
  echo "   2. Cai dat WireProxy (Ping cao hon 1 chut, nhung On dinh tuyet doi, danh cho Server lon)"
  echo "   3. Cai dat warp-go (Rat nhe, it tieu thu RAM, khong can thiep he dieu hanh)"
  echo "   4. Khong cai dat WARP (Dung IP goc cua VPS)"
  read -p "   Vui Long Chon [1-4]: " warp_choice
  warp_choice=$(echo "$warp_choice" | sed 's/[^1234]//g')

  warp_udp=false
  if [ "$warp_choice" == "1" ]; then
    enable_warp=true
    warp_mode="c"
    echo "   Da chon warp-cli (Che do C)."
    echo ""
    read -p "   Ban co muon nhap Key WARP+ khong? (Nhan Enter de bo qua, dung Free): " warp_plus_key
    echo ""
  elif [ "$warp_choice" == "2" ]; then
    enable_warp=true
    warp_mode="w"
    echo "   Da chon WireProxy (Che do W)."
  elif [ "$warp_choice" == "3" ]; then
    enable_warp=true
    warp_mode="g"
    echo "   Da chon warp-go (Che do G)."
  else
    enable_warp=false
    echo "   Bo qua cai dat WARP. (Van se cai dat khieng chong DDoS)"
  fi

  if [ "$enable_warp" = true ]; then
    echo ""
    echo "   Pham vi dinh tuyen du lieu qua WARP:"
    echo "   1. Boc TCP (Mac dinh - Khuyen dung cho Game): Web an IP, UDP Game di Direct Ping thap 20-30ms."
    echo "   2. Boc ca TCP & UDP (An 100% IP): Chong lo WebRTC/STUN, nhung Ping choi Game se CAO HON."
    read -p "   Vui long chon [1-2, mac dinh 1]: " udp_choice
    udp_choice=$(echo "$udp_choice" | sed 's/[^12]//g')
    if [ "$udp_choice" == "2" ]; then
      warp_udp=true
      echo "   Da chon: Boc ca TCP va UDP qua WARP (An 100% IP goc VPS, luu y Ping game se cao hon)."
    else
      warp_udp=false
      echo "   Da chon: Boc TCP, BO BOC UDP (UDP di Direct - Toi uu Ping thap 20-30ms cho Game)."
    fi
  fi
  
  # Chung ta se luon su dung custom route de block Port 53, chong DDoS DNS Amplification.
  route_config_path="/etc/XrayR/custom_route.json"
  outbound_config_path="/etc/XrayR/custom_outbound.json"
}

function install_warp(){
  if [ "$enable_warp" = true ]; then
    echo "   Dang cau hinh Cloudflare WARP..."
    
    # === Don dep triet de WARP/WireGuard cu (CHONG LOI w0 con ton tai) ===
    echo "   [Cleanup] Dang kiem tra va go sach WARP/WireGuard cu..."

    # Tat toan bo dich vu WARP lien quan
    for svc in warp-svc wireproxy warp-go wg-quick@wgcf wg-quick@wg0 xray-warp; do
      systemctl stop "$svc" >/dev/null 2>&1
      systemctl disable "$svc" >/dev/null 2>&1
    done

    # Xoa interface mang wg0 / w0 / wgcf (NGUYEN NHAN CHINH GAY LOI)
    for iface in wg0 w0 wgcf; do
      if ip link show "$iface" >/dev/null 2>&1; then
        echo "   [Cleanup] Phat hien interface $iface, dang xoa..."
        ip link set "$iface" down 2>/dev/null
        ip link delete "$iface" 2>/dev/null
      fi
    done

    # Go xray-warp sidecar (ban xraywg cu)
    if [ -f /usr/local/bin/xray-warp ] || [ -f /etc/systemd/system/xray-warp.service ]; then
      echo "   [Cleanup] Dang go xray-warp sidecar..."
      rm -f /etc/systemd/system/xray-warp.service
      rm -f /usr/local/bin/xray-warp
      rm -f /etc/XrayR/warp-client.json
      rm -f /usr/local/bin/wgcf
      rm -f /etc/XrayR/wgcf-account.toml
      rm -f /etc/XrayR/wgcf-profile.conf
    fi

    # Go warp-go
    if [ -f /usr/local/bin/warp-go ] || [ -f /opt/warp-go/warp-go ]; then
      echo "   [Cleanup] Dang go warp-go..."
      rm -f /etc/systemd/system/warp-go.service
      rm -rf /opt/warp-go/
      rm -f /usr/local/bin/warp-go
    fi

    # Go wireproxy
    if [ -f /usr/local/bin/wireproxy ]; then
      echo "   [Cleanup] Dang go wireproxy..."
      rm -f /etc/systemd/system/wireproxy.service
      rm -f /usr/local/bin/wireproxy
    fi

    # Go wgcf config cu va script thua
    rm -f /etc/wireguard/wgcf.conf
    rm -f /etc/wireguard/wg0.conf
    rm -f /root/menu.sh /root/warp-go.sh

    # Fix config.yml: Xoa RouteConfigPath va OutboundConfigPath tro vao WARP
    #  (TRANH LOI: XrayR crash mat mang neu config.yml van tro vao file da bi xoa)
    if [ -f /etc/XrayR/config.yml ]; then
      sed -i 's|^RouteConfigPath:.*|RouteConfigPath: |' /etc/XrayR/config.yml 2>/dev/null
      sed -i 's|^OutboundConfigPath:.*|OutboundConfigPath: |' /etc/XrayR/config.yml 2>/dev/null
    fi
    rm -f /etc/XrayR/custom_route.json
    rm -f /etc/XrayR/custom_outbound.json

    # Xoa cronjob lien quan den warp cu
    (crontab -l 2>/dev/null | grep -v "warp-svc" | grep -v "warp-go" | grep -v "wireproxy") | crontab - 2>/dev/null

    systemctl daemon-reload
    echo "   [Cleanup] Don dep WARP/WireGuard cu hoan tat!"
    
    # 4.1 Fix DNS de khong bi sap mang khi cai WARP
    chattr -i /etc/resolv.conf 2>/dev/null
    rm -f /etc/resolv.conf
    cat > /etc/resolv.conf <<EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
EOF

    # 4.2 Cai dat WARP qua fscarmen script (Tu dong hoa 100%, khong can go tay)
    mkdir -p /etc/wireguard
    echo "E" > /etc/wireguard/language

    if [ "$warp_mode" == "c" ]; then
      echo "   Tien hanh go bo phien ban WARP/WireProxy cu (neu co) de cai moi..."
      wget -N https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh
      printf "1\n" | bash menu.sh u >/dev/null 2>&1
      
      echo "   Tien hanh cai dat warp-cli (Tu dong chon Tieng Anh, Port 40000)..."
      printf "1\n40000\n\n" | bash menu.sh c
      
      if [ -n "$warp_plus_key" ]; then
        echo "   Dang add Key WARP+..."
        # Disconnect truoc khi doi key de tranh mat mang
        warp-cli --accept-tos disconnect >/dev/null 2>&1
        sleep 3
        
        # Doi key
        warp-cli --accept-tos set-license "$warp_plus_key" >/dev/null 2>&1 || \
        warp-cli --accept-tos registration license "$warp_plus_key" >/dev/null 2>&1 || \
        warp-cli --accept-tos account license "$warp_plus_key" >/dev/null 2>&1
        
        sleep 3
        warp-cli --accept-tos connect >/dev/null 2>&1
        sleep 5
        
        # Kiem tra SOCKS5 co thuc su hoat dong voi key WARP+ khong
        WARP_TEST=$(curl -s --max-time 10 -x socks5://127.0.0.1:40000 https://ifconfig.me 2>/dev/null)
        if [ -n "$WARP_TEST" ]; then
          echo "   Da add Key WARP+ thanh cong! IP WARP: $WARP_TEST"
        else
          echo "   CANH BAO: WARP+ khong hoat dong, dang quay lai ban Free..."
          warp-cli --accept-tos disconnect >/dev/null 2>&1
          sleep 2
          # Xoa key WARP+, quay ve Free
          warp-cli --accept-tos set-license "" >/dev/null 2>&1 || \
          warp-cli --accept-tos registration license "" >/dev/null 2>&1 || true
          sleep 2
          warp-cli --accept-tos connect >/dev/null 2>&1
          sleep 5
          echo "   Da quay lai WARP Free. Hay add Key WARP+ thu cong sau bang lenh:"
          echo "   warp-cli --accept-tos disconnect && sleep 3 && warp-cli --accept-tos set-license \"KEY\" && sleep 3 && warp-cli --accept-tos connect"
        fi
      fi

      # Cai dat cronjob tu dong restart warp-svc moi 1 tieng de chong nghen (i/o timeout)
      (crontab -l 2>/dev/null | grep -v "warp-svc"; echo "0 * * * * systemctl restart warp-svc") | crontab -
      echo "   Da cai dat Auto-Restart warp-svc moi 1 tieng de chong treo mang!"
    elif [ "$warp_mode" == "w" ]; then
      echo "   Dang cai dat WireProxy (Khoi chay truc tiep, khong bi treo)..."
      export DEBIAN_FRONTEND=noninteractive
      apt-get purge -y needrestart >/dev/null 2>&1 || true

      # 1. Tai binary WireProxy v1.1.3 (windtf) truc tiep
      echo "   Dang tai goi WireProxy v1.1.3..."
      local arch=$(uname -m)
      local wp_arch="amd64"
      [ "$arch" = "aarch64" ] || [ "$arch" = "arm64" ] && wp_arch="arm64"
      wget -qO /tmp/wp.tar.gz "https://github.com/windtf/wireproxy/releases/download/v1.1.3/wireproxy_linux_${wp_arch}.tar.gz" 2>/dev/null || \
      wget -qO /tmp/wp.tar.gz "https://gitlab.com/fscarmen/warp/-/raw/main/wireproxy/wireproxy_linux_${wp_arch}.tar.gz" 2>/dev/null
      if [ -s /tmp/wp.tar.gz ]; then
        tar -xzf /tmp/wp.tar.gz -C /tmp/ 2>/dev/null
        cp -f /tmp/wireproxy /usr/bin/wireproxy 2>/dev/null
        chmod +x /usr/bin/wireproxy 2>/dev/null
        rm -f /tmp/wp.tar.gz /tmp/wireproxy
      fi

      # 2. Dang ky tai khoan Cloudflare WARP chinh quy qua api.sh (chay non-interactive)
      echo "   Dang dang ky tai khoan Cloudflare WARP chinh quy..."
      mkdir -p /etc/wireguard
      rm -f /etc/wireguard/warp-account.conf
      bash <(curl -sSL --connect-timeout 8 --max-time 15 "https://gitlab.com/fscarmen/warp/-/raw/main/api.sh") -r -f /etc/wireguard/warp-account.conf >/dev/null 2>&1

      # Trich xuat PrivateKey va IPv6 tu warp-account.conf
      local warp_priv=""
      local warp_ipv6=""
      if [ -s /etc/wireguard/warp-account.conf ]; then
        warp_priv=$(awk -F'"' '/"private_key"/ {print $4; exit}' /etc/wireguard/warp-account.conf)
        warp_ipv6=$(awk -F'"' '/"v6"[[:space:]]*:/ && $4 !~ /^\[/ {print $4; exit}' /etc/wireguard/warp-account.conf)
      fi

      # Fallback neu api.sh chua tra ve (dung wgcf dang ky)
      if [ -z "$warp_priv" ] || [ -z "$warp_ipv6" ]; then
        echo "   (Fallback) Dang dang ky qua wgcf..."
        local wgcf_arch="amd64"
        [ "$arch" = "aarch64" ] || [ "$arch" = "arm64" ] && wgcf_arch="arm64"
        wget -qO /usr/local/bin/wgcf "https://github.com/ViRb3/wgcf/releases/download/v2.2.22/wgcf_2.2.22_linux_${wgcf_arch}" 2>/dev/null
        chmod +x /usr/local/bin/wgcf 2>/dev/null
        if [ -x /usr/local/bin/wgcf ]; then
          mkdir -p /tmp/wgcf_reg && cd /tmp/wgcf_reg
          /usr/local/bin/wgcf register --accept-tos >/dev/null 2>&1
          /usr/local/bin/wgcf generate >/dev/null 2>&1
          if [ -s wgcf-profile.conf ]; then
            warp_priv=$(grep -i "PrivateKey" wgcf-profile.conf | head -n 1 | awk '{print $3}' | tr -d '\r\n')
            warp_ipv6=$(grep -i "Address" wgcf-profile.conf | grep ":" | head -n 1 | awk '{print $3}' | cut -d'/' -f1 | tr -d '\r\n')
          fi
          cd /root && rm -rf /tmp/wgcf_reg
        fi
      fi

      # 3. Tao file cau hinh /etc/wireguard/proxy.conf
      echo "   Dang tao cau hinh /etc/wireguard/proxy.conf (SOCKS5 127.0.0.1:40000)..."
      cat > /etc/wireguard/proxy.conf <<WPEOF
[Interface]
Address = 172.16.0.2/32, ${warp_ipv6}/128
MTU = 1280
PrivateKey = ${warp_priv}
DNS = 1.1.1.1, 8.8.8.8, 8.8.4.4

[Peer]
PublicKey = bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = 162.159.192.1:500
PersistentKeepalive = 25

[Socks5]
BindAddress = 127.0.0.1:40000
WPEOF

      # 4. Tao systemd service cho wireproxy
      cat > /lib/systemd/system/wireproxy.service <<WPEOF
[Unit]
Description=WireProxy for WARP
After=network.target
Documentation=https://github.com/windtf/wireproxy

[Service]
Type=simple
ExecStart=/usr/bin/wireproxy -c /etc/wireguard/proxy.conf
Restart=always
RestartSec=3s
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
WPEOF

      # 5. Cai dat phien ban menu.sh lam shortcut warp (warp y, warp n)
      wget -qO /etc/wireguard/menu.sh "https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh" 2>/dev/null
      chmod +x /etc/wireguard/menu.sh 2>/dev/null
      ln -sf /etc/wireguard/menu.sh /usr/bin/warp 2>/dev/null
      echo "E" > /etc/wireguard/language

      # 6. Khoi dong dich vu wireproxy
      systemctl daemon-reload
      systemctl enable wireproxy >/dev/null 2>&1
      systemctl restart wireproxy >/dev/null 2>&1
      sleep 3

      # 7. Kiem tra ket noi SOCKS5 40000
      local test_ip=$(curl -s --socks5 127.0.0.1:40000 --max-time 5 https://api.ipify.org 2>/dev/null)
      if [ -n "$test_ip" ]; then
        echo "   Da khoi chay WireProxy thanh cong! IP WARP: $test_ip (Lenh 'warp y' san sang)"
      else
        echo "   WireProxy da duoc bat tren cong 40000 (Dang ket noi Cloudflare WARP...)"
      fi
    elif [ "$warp_mode" == "g" ]; then
      echo "   Tien hanh go bo phien ban WARP cu (neu co) de cai moi..."
      wget -N https://raw.githubusercontent.com/fscarmen/warp/main/warp-go.sh
      yes | bash warp-go.sh u >/dev/null 2>&1
      
      echo "   Tien hanh cai dat warp-go..."
      printf "1\n" | bash warp-go.sh
    fi
  fi

  # 3. Tu dong sinh cau hinh Outbound
  # Neu enable_warp=true, them Outbound SOCKS5. Neu false, bo qua SOCKS5.
  if [ "$enable_warp" = true ]; then
    cat > /etc/XrayR/custom_outbound.json <<EOF
[
  {
    "tag": "WARP",
    "protocol": "socks",
    "settings": {
      "servers": [
        {
          "address": "127.0.0.1",
          "port": 40000
        }
      ]
    }
  },
  {
    "protocol": "freedom",
    "tag": "direct"
  },
  {
    "protocol": "blackhole",
    "tag": "block"
  }
]
EOF
  else
    cat > /etc/XrayR/custom_outbound.json <<EOF
[
  {
    "protocol": "freedom",
    "tag": "direct"
  },
  {
    "protocol": "blackhole",
    "tag": "block"
  }
]
EOF
  fi

  # 3. Tu dong sinh cau hinh Route (Gom het vao WARP hoac Direct)
  # Khoa chet cong UDP 53 va 443 de chong DDoS DNS Amplification
  if [ "$enable_warp" = true ]; then
    TCP_OUT="WARP"
    if [ "$warp_udp" = true ]; then
      UDP_OUT="WARP"
    else
      UDP_OUT="direct"
    fi
  else
    TCP_OUT="direct"
    UDP_OUT="direct"
  fi

  cat > /etc/XrayR/custom_route.json <<EOF
{
  "domainStrategy": "AsIs",
  "rules": [
    {
      "type": "field",
      "outboundTag": "block",
      "ip": [
        "geoip:private"
      ]
    },
    {
      "type": "field",
      "outboundTag": "block",
      "protocol": [
        "bittorrent"
      ]
    },
    {
      "type": "field",
      "outboundTag": "block",
      "network": "udp",
      "port": "443"
    },
    {
      "type": "field",
      "outboundTag": "$UDP_OUT",
      "network": "udp"
    },
    {
      "type": "field",
      "outboundTag": "$TCP_OUT",
      "network": "tcp"
    }
  ]
}
EOF
  echo "   Da tao cau hinh custom_route.json va custom_outbound.json (Kem khien chong DDoS)"
}

function vmessx2(){
check_api_config
read -p " NODE ID 80 VMESS: " node_id1
node_id1=$(echo "$node_id1" | sed 's/[^0-9]//g')
  [ -z "${node_id1}" ] && node_id1=0

read -p " NODE ID 443 VMESS: " node_id2
node_id2=$(echo "$node_id2" | sed 's/[^0-9]//g')
  [ -z "${node_id2}" ] && node_id2=0

ask_cert_config
ask_warp
obtain_cert
run_install
install_warp
cd /etc/XrayR

cat >config.yml <<EOF
Log:
  Level: none
  AccessPath: 
  ErrorPath: 
DnsConfigPath: 
InboundConfigPath: 
RouteConfigPath: ${route_config_path}
OutboundConfigPath: ${outbound_config_path}
ConnetionConfig:
  Handshake: 4 
  ConnIdle: 30 
  UplinkOnly: 2 
  DownlinkOnly: 4 
  BufferSize: 64
Nodes:
  -
    PanelType: "NewV2board"
    ApiConfig:
      ApiHost: "${API_HOST}"
      ApiKey: "${API_KEY}"
      NodeID: $node_id1
      NodeType: V2ray
      Timeout: 30
      EnableVless: false
      EnableXTLS: false
      RuleListPath: 
    ControllerConfig:
      DisableSniffing: True
      ListenIP: 0.0.0.0 
      SendIP: 0.0.0.0 
      UpdatePeriodic: 60 
      EnableDNS: false 
      DNSType: AsIs 
      EnableProxyProtocol: false 
      EnableFallback: false 
      FallBackConfigs:  
        -
          SNI: 
          Path: 
          Dest: 80 
          ProxyProtocolVer: 0 
      CertConfig:
        CertMode: $cert_mode 
        CertDomain: "$cert_domain" 
        CertFile: $cert_file 
        KeyFile: $key_file
        Provider: alidns 
        Email: example@gmail.com
        DNSEnv: 
          ALICLOUD_ACCESS_KEY: aaa
          ALICLOUD_SECRET_KEY: bbb
  -
    PanelType: "NewV2board"
    ApiConfig:
      ApiHost: "${API_HOST}"
      ApiKey: "${API_KEY}"
      NodeID: $node_id2
      NodeType: V2ray
      Timeout: 30
      EnableVless: false
      EnableXTLS: false
      RuleListPath: 
    ControllerConfig:
      DisableSniffing: True
      ListenIP: 0.0.0.0 
      SendIP: 0.0.0.0 
      UpdatePeriodic: 60 
      EnableDNS: false 
      DNSType: AsIs 
      EnableProxyProtocol: false 
      EnableFallback: false 
      FallBackConfigs:  
        -
          SNI: 
          Path: 
          Dest: 80 
          ProxyProtocolVer: 0 
      CertConfig:
        CertMode: $cert_mode 
        CertDomain: "$cert_domain" 
        CertFile: $cert_file 
        KeyFile: $key_file
        Provider: alidns 
        Email: example@gmail.com
        DNSEnv: 
          ALICLOUD_ACCESS_KEY: aaa
          ALICLOUD_SECRET_KEY: bbb
EOF
cd /root && xrayr restart && clear && echo "   Cai Dat Hoan Tat!"
}

function vlessx2(){
check_api_config
read -p " NODE ID 80 VLESS: " node_id1
node_id1=$(echo "$node_id1" | sed 's/[^0-9]//g')
  [ -z "${node_id1}" ] && node_id1=0

read -p " NODE ID 443 VLESS: " node_id2
node_id2=$(echo "$node_id2" | sed 's/[^0-9]//g')
  [ -z "${node_id2}" ] && node_id2=0

ask_cert_config
ask_warp
obtain_cert
run_install
install_warp
cd /etc/XrayR

cat >config.yml <<EOF
Log:
  Level: none
  AccessPath: 
  ErrorPath: 
DnsConfigPath: 
InboundConfigPath: 
RouteConfigPath: ${route_config_path}
OutboundConfigPath: ${outbound_config_path}
ConnetionConfig:
  Handshake: 4 
  ConnIdle: 30 
  UplinkOnly: 2 
  DownlinkOnly: 4 
  BufferSize: 64
Nodes:
  -
    PanelType: "NewV2board"
    ApiConfig:
      ApiHost: "${API_HOST}"
      ApiKey: "${API_KEY}"
      NodeID: $node_id1
      NodeType: V2ray
      Timeout: 30
      EnableVless: true
      EnableXTLS: false
      RuleListPath: 
    ControllerConfig:
      DisableSniffing: True
      ListenIP: 0.0.0.0 
      SendIP: 0.0.0.0 
      UpdatePeriodic: 60 
      EnableDNS: false 
      DNSType: AsIs 
      EnableProxyProtocol: false 
      EnableFallback: false 
      FallBackConfigs:  
        -
          SNI: 
          Path: 
          Dest: 80 
          ProxyProtocolVer: 0 
      CertConfig:
        CertMode: $cert_mode 
        CertDomain: "$cert_domain" 
        CertFile: $cert_file 
        KeyFile: $key_file
        Provider: alidns 
        Email: example@gmail.com
        DNSEnv: 
          ALICLOUD_ACCESS_KEY: aaa
          ALICLOUD_SECRET_KEY: bbb
  -
    PanelType: "NewV2board"
    ApiConfig:
      ApiHost: "${API_HOST}"
      ApiKey: "${API_KEY}"
      NodeID: $node_id2
      NodeType: V2ray
      Timeout: 30
      EnableVless: true
      EnableXTLS: false
      RuleListPath: 
    ControllerConfig:
      DisableSniffing: True
      ListenIP: 0.0.0.0 
      SendIP: 0.0.0.0 
      UpdatePeriodic: 60 
      EnableDNS: false 
      DNSType: AsIs 
      EnableProxyProtocol: false 
      EnableFallback: false 
      FallBackConfigs:  
        -
          SNI: 
          Path: 
          Dest: 80 
          ProxyProtocolVer: 0 
      CertConfig:
        CertMode: $cert_mode 
        CertDomain: "$cert_domain" 
        CertFile: $cert_file 
        KeyFile: $key_file
        Provider: alidns 
        Email: example@gmail.com
        DNSEnv: 
          ALICLOUD_ACCESS_KEY: aaa
          ALICLOUD_SECRET_KEY: bbb
EOF
cd /root && xrayr restart && clear && echo "   Cai Dat Hoan Tat!"
}

function vmesstrojan(){
check_api_config
read -p " NODE ID 80 VMESS: " node_id1
node_id1=$(echo "$node_id1" | sed 's/[^0-9]//g')
  [ -z "${node_id1}" ] && node_id1=0

read -p " NODE ID 443 TROJAN: " node_id2
node_id2=$(echo "$node_id2" | sed 's/[^0-9]//g')
  [ -z "${node_id2}" ] && node_id2=0

ask_cert_config
ask_warp
obtain_cert
run_install
install_warp
cd /etc/XrayR

cat >config.yml <<EOF
Log:
  Level: none
  AccessPath: 
  ErrorPath: 
DnsConfigPath: 
InboundConfigPath: 
RouteConfigPath: ${route_config_path}
OutboundConfigPath: ${outbound_config_path}
ConnetionConfig:
  Handshake: 4 
  ConnIdle: 30 
  UplinkOnly: 2 
  DownlinkOnly: 4 
  BufferSize: 64
Nodes:
  -
    PanelType: "NewV2board"
    ApiConfig:
      ApiHost: "${API_HOST}"
      ApiKey: "${API_KEY}"
      NodeID: $node_id1
      NodeType: V2ray
      Timeout: 30
      EnableVless: false
      EnableXTLS: false
      RuleListPath: 
    ControllerConfig:
      DisableSniffing: True
      ListenIP: 0.0.0.0 
      SendIP: 0.0.0.0 
      UpdatePeriodic: 60 
      EnableDNS: false 
      DNSType: AsIs 
      EnableProxyProtocol: false 
      EnableFallback: false 
      FallBackConfigs:  
        -
          SNI: 
          Path: 
          Dest: 80 
          ProxyProtocolVer: 0 
      CertConfig:
        CertMode: $cert_mode 
        CertDomain: "$cert_domain" 
        CertFile: $cert_file 
        KeyFile: $key_file
        Provider: alidns 
        Email: example@gmail.com
        DNSEnv: 
          ALICLOUD_ACCESS_KEY: aaa
          ALICLOUD_SECRET_KEY: bbb
  -
    PanelType: "NewV2board"
    ApiConfig:
      ApiHost: "${API_HOST}"
      ApiKey: "${API_KEY}"
      NodeID: $node_id2
      NodeType: Trojan
      Timeout: 30
      EnableVless: false
      EnableXTLS: false
      RuleListPath: 
    ControllerConfig:
      DisableSniffing: True
      ListenIP: 0.0.0.0 
      SendIP: 0.0.0.0 
      UpdatePeriodic: 60 
      EnableDNS: false 
      DNSType: AsIs 
      EnableProxyProtocol: false 
      EnableFallback: false 
      FallBackConfigs:  
        -
          SNI: 
          Path: 
          Dest: 80 
          ProxyProtocolVer: 0 
      CertConfig:
        CertMode: $cert_mode 
        CertDomain: "$cert_domain" 
        CertFile: $cert_file 
        KeyFile: $key_file
        Provider: alidns 
        Email: example@gmail.com
        DNSEnv: 
          ALICLOUD_ACCESS_KEY: aaa
          ALICLOUD_SECRET_KEY: bbb
EOF
cd /root && xrayr restart && clear && echo "   Cai Dat Hoan Tat!"
}

function vlesstrojan(){
check_api_config
read -p " NODE ID 80 VLESS: " node_id1
node_id1=$(echo "$node_id1" | sed 's/[^0-9]//g')
  [ -z "${node_id1}" ] && node_id1=0

read -p " NODE ID 443 TROJAN: " node_id2
node_id2=$(echo "$node_id2" | sed 's/[^0-9]//g')
  [ -z "${node_id2}" ] && node_id2=0

ask_cert_config
ask_warp
obtain_cert
run_install
install_warp
cd /etc/XrayR

cat >config.yml <<EOF
Log:
  Level: none
  AccessPath: 
  ErrorPath: 
DnsConfigPath: 
InboundConfigPath: 
RouteConfigPath: ${route_config_path}
OutboundConfigPath: ${outbound_config_path}
ConnetionConfig:
  Handshake: 4 
  ConnIdle: 30 
  UplinkOnly: 2 
  DownlinkOnly: 4 
  BufferSize: 64
Nodes:
  -
    PanelType: "NewV2board"
    ApiConfig:
      ApiHost: "${API_HOST}"
      ApiKey: "${API_KEY}"
      NodeID: $node_id1
      NodeType: V2ray
      Timeout: 30
      EnableVless: true
      EnableXTLS: false
      RuleListPath: 
    ControllerConfig:
      DisableSniffing: True
      ListenIP: 0.0.0.0 
      SendIP: 0.0.0.0 
      UpdatePeriodic: 60 
      EnableDNS: false 
      DNSType: AsIs 
      EnableProxyProtocol: false 
      EnableFallback: false 
      FallBackConfigs:  
        -
          SNI: 
          Path: 
          Dest: 80 
          ProxyProtocolVer: 0 
      CertConfig:
        CertMode: $cert_mode 
        CertDomain: "$cert_domain" 
        CertFile: $cert_file 
        KeyFile: $key_file
        Provider: alidns 
        Email: example@gmail.com
        DNSEnv: 
          ALICLOUD_ACCESS_KEY: aaa
          ALICLOUD_SECRET_KEY: bbb
  -
    PanelType: "NewV2board"
    ApiConfig:
      ApiHost: "${API_HOST}"
      ApiKey: "${API_KEY}"
      NodeID: $node_id2
      NodeType: Trojan
      Timeout: 30
      EnableVless: false
      EnableXTLS: false
      RuleListPath: 
    ControllerConfig:
      DisableSniffing: True
      ListenIP: 0.0.0.0 
      SendIP: 0.0.0.0 
      UpdatePeriodic: 60 
      EnableDNS: false 
      DNSType: AsIs 
      EnableProxyProtocol: false 
      EnableFallback: false 
      FallBackConfigs:  
        -
          SNI: 
          Path: 
          Dest: 80 
          ProxyProtocolVer: 0 
      CertConfig:
        CertMode: $cert_mode 
        CertDomain: "$cert_domain" 
        CertFile: $cert_file 
        KeyFile: $key_file
        Provider: alidns 
        Email: example@gmail.com
        DNSEnv: 
          ALICLOUD_ACCESS_KEY: aaa
          ALICLOUD_SECRET_KEY: bbb
EOF
cd /root && xrayr restart && clear && echo "   Cai Dat Hoan Tat!"
}
function vmess(){
check_api_config
read -p " NODE ID VMESS: " node_id1
node_id1=$(echo "$node_id1" | sed 's/[^0-9]//g')
  [ -z "${node_id1}" ] && node_id1=0

ask_cert_config
ask_warp
obtain_cert
run_install
install_warp
cd /etc/XrayR

cat >config.yml <<EOF
Log:
  Level: none
  AccessPath: 
  ErrorPath: 
DnsConfigPath: 
InboundConfigPath: 
RouteConfigPath: ${route_config_path}
OutboundConfigPath: ${outbound_config_path}
ConnetionConfig:
  Handshake: 4 
  ConnIdle: 30 
  UplinkOnly: 2 
  DownlinkOnly: 4 
  BufferSize: 64
Nodes:
  -
    PanelType: "NewV2board"
    ApiConfig:
      ApiHost: "${API_HOST}"
      ApiKey: "${API_KEY}"
      NodeID: $node_id1
      NodeType: V2ray
      Timeout: 30
      EnableVless: false
      EnableXTLS: false
      RuleListPath: 
    ControllerConfig:
      DisableSniffing: True
      ListenIP: 0.0.0.0 
      SendIP: 0.0.0.0 
      UpdatePeriodic: 60 
      EnableDNS: false 
      DNSType: AsIs 
      EnableProxyProtocol: false 
      EnableFallback: false 
      FallBackConfigs:  
        -
          SNI: 
          Path: 
          Dest: 80 
          ProxyProtocolVer: 0 
      CertConfig:
        CertMode: $cert_mode 
        CertDomain: "$cert_domain" 
        CertFile: $cert_file 
        KeyFile: $key_file
        Provider: alidns 
        Email: example@gmail.com
        DNSEnv: 
          ALICLOUD_ACCESS_KEY: aaa
          ALICLOUD_SECRET_KEY: bbb
EOF
cd /root && xrayr restart && clear && echo "   Cai Dat Hoan Tat!"
}
function vless(){
check_api_config
read -p " NODE ID VLESS: " node_id1
node_id1=$(echo "$node_id1" | sed 's/[^0-9]//g')
  [ -z "${node_id1}" ] && node_id1=0

ask_cert_config
ask_warp
obtain_cert
run_install
install_warp
cd /etc/XrayR

cat >config.yml <<EOF
Log:
  Level: none
  AccessPath: 
  ErrorPath: 
DnsConfigPath: 
InboundConfigPath: 
RouteConfigPath: ${route_config_path}
OutboundConfigPath: ${outbound_config_path}
ConnetionConfig:
  Handshake: 4 
  ConnIdle: 30 
  UplinkOnly: 2 
  DownlinkOnly: 4 
  BufferSize: 64
Nodes:
  -
    PanelType: "NewV2board"
    ApiConfig:
      ApiHost: "${API_HOST}"
      ApiKey: "${API_KEY}"
      NodeID: $node_id1
      NodeType: V2ray
      Timeout: 30
      EnableVless: true
      EnableXTLS: false
      RuleListPath: 
    ControllerConfig:
      DisableSniffing: True
      ListenIP: 0.0.0.0 
      SendIP: 0.0.0.0 
      UpdatePeriodic: 60 
      EnableDNS: false 
      DNSType: AsIs 
      EnableProxyProtocol: false 
      EnableFallback: false 
      FallBackConfigs:  
        -
          SNI: 
          Path: 
          Dest: 80 
          ProxyProtocolVer: 0 
      CertConfig:
        CertMode: $cert_mode 
        CertDomain: "$cert_domain" 
        CertFile: $cert_file 
        KeyFile: $key_file
        Provider: alidns 
        Email: example@gmail.com
        DNSEnv: 
          ALICLOUD_ACCESS_KEY: aaa
          ALICLOUD_SECRET_KEY: bbb
EOF
cd /root && xrayr restart && clear && echo "   Cai Dat Hoan Tat!"
}
function trojan(){
check_api_config
read -p " NODE ID TROJAN: " node_id1
node_id1=$(echo "$node_id1" | sed 's/[^0-9]//g')
  [ -z "${node_id1}" ] && node_id1=0

ask_cert_config
ask_warp
obtain_cert
run_install
install_warp
cd /etc/XrayR

cat >config.yml <<EOF
Log:
  Level: none
  AccessPath: 
  ErrorPath: 
DnsConfigPath: 
InboundConfigPath: 
RouteConfigPath: ${route_config_path}
OutboundConfigPath: ${outbound_config_path}
ConnetionConfig:
  Handshake: 4 
  ConnIdle: 30 
  UplinkOnly: 2 
  DownlinkOnly: 4 
  BufferSize: 64
Nodes:
  -
    PanelType: "NewV2board"
    ApiConfig:
      ApiHost: "${API_HOST}"
      ApiKey: "${API_KEY}"
      NodeID: $node_id1
      NodeType: Trojan
      Timeout: 30
      EnableVless: false
      EnableXTLS: false
      RuleListPath: 
    ControllerConfig:
      DisableSniffing: True
      ListenIP: 0.0.0.0 
      SendIP: 0.0.0.0 
      UpdatePeriodic: 60 
      EnableDNS: false 
      DNSType: AsIs 
      EnableProxyProtocol: false 
      EnableFallback: false 
      FallBackConfigs:  
        -
          SNI: 
          Path: 
          Dest: 80 
          ProxyProtocolVer: 0 
      CertConfig:
        CertMode: $cert_mode 
        CertDomain: "$cert_domain" 
        CertFile: $cert_file 
        KeyFile: $key_file
        Provider: alidns 
        Email: example@gmail.com
        DNSEnv: 
          ALICLOUD_ACCESS_KEY: aaa
          ALICLOUD_SECRET_KEY: bbb
EOF
cd /root && xrayr restart && clear && echo "   Cai Dat Hoan Tat!"
}
function start_menu(){
    clear
    echo "  He Thong Cai Dat Nhanh May Chu:"
    echo "   1. 80 VMESS + 443 VMESS"
    echo "   2. 80 VLESS + 443 VLESS"
    echo "   3. 80 VMESS + 443 TROJAN"
    echo "   4. 80 VLESS + 443 TROJAN"
    echo "   5. 80 VMESS OR 443 VMESS"
    echo "   6. 80 VLESS OR 443 VLESS"
    echo "   7. 443 TROJAN"
    read -p "Vui Long Chon: " numrun
    numrun=$(echo "$numrun" | sed 's/[^0-9]//g')
    case "$numrun" in
        1 )
           vmessx2
	    ;;
        2 )
           vlessx2
        ;;
        3 )
           vmesstrojan
        ;;
        4 )
           vlesstrojan
        ;;
        5 )
           vmess
        ;;
        6 )
           vless
        ;;
        7 )
           trojan
        ;;
        * )
           echo "   Nhap Sai !"
        ;;
    esac
}
start_menu "first"
