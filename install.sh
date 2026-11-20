#!/usr/bin/env bash

# ==============================================================================
# Script Cài Đặt Tự Động XrayR v0.9.6-VN (Bản Việt Hóa - Phương Liên 4G)
# Hỗ trợ: VLESS, VMess, Trojan, Shadowsocks, MLKEM768X25519PLUS (Hậu lượng tử)
# Repo: https://github.com/hqp1310/XrayR
# ==============================================================================

# Tự sửa lỗi CRLF (Windows line endings) nếu file bị convert
sed -i 's/\r$//' "$0" 2>/dev/null

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
SKYBLUE='\033[0;36m'
PLAIN='\033[0m'

# Kiểm tra quyền root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[LỖI]${PLAIN} Bạn cần chạy script này bằng quyền root (sudo)!"
    exit 1
fi

# Kiểm tra kiến trúc CPU (Chỉ hỗ trợ 64-bit AMD64/x86_64)
ARCH=$(uname -m)
if [[ "$ARCH" != "x86_64" && "$ARCH" != "amd64" && "$ARCH" != "x64" ]]; then
    echo -e "${RED}[LỖI]${PLAIN} Bản dựng XrayR này hiện tối ưu cho kiến trúc Linux 64-bit (x86_64 / amd64). Kiến trúc hiện tại ($ARCH) không được hỗ trợ."
    exit 1
fi

# Phân tích tham số dòng lệnh (CLI Flags)
API_HOST=""
API_KEY=""
NODE_ID=""
NODE_TYPE="vless"
FORCE_OVERWRITE=false
ONLY_BINARY=false

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
        --node-id|-n)
            NODE_ID="$2"
            shift 2
            ;;
        --node-type|-t)
            NODE_TYPE="$2"
            shift 2
            ;;
        --only-binary|-b)
            ONLY_BINARY=true
            shift
            ;;
        --force|-f)
            FORCE_OVERWRITE=true
            shift
            ;;
        --help)
            echo "Cách sử dụng:"
            echo "  bash install.sh --api-host <URL> --api-key <TOKEN> --node-id <ID> [--node-type <TYPE>]"
            echo "Ví dụ:"
            echo "  bash install.sh --api-host 'https://global.phuonglien4g.com' --api-key 'secret_token' --node-id 1 --node-type 'vless'"
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

echo -e "${GREEN}================================================================${PLAIN}"
echo -e "${GREEN}       BẮT ĐẦU CÀI ĐẶT XRAYR v0.9.6-VN (BẢN VIỆT HÓA)           ${PLAIN}"
echo -e "${GREEN}================================================================${PLAIN}"

# Cài đặt các gói phụ trợ cơ bản & giải phóng apt lock
install_dependencies() {
    echo -e "${SKYBLUE}[1/5] Kiểm tra và cập nhật các gói phụ trợ hệ thống...${PLAIN}"
    export DEBIAN_FRONTEND=noninteractive
    
    if command -v apt-get >/dev/null 2>&1; then
        # Vô hiệu hóa needrestart gây treo mạng SSH
        apt-get purge -y needrestart 2>/dev/null || true
        mkdir -p /etc/needrestart/conf.d 2>/dev/null
        echo '$nrconf{restart} = "l";' > /etc/needrestart/conf.d/no-restart.conf 2>/dev/null

        # Tắt cập nhật ngầm nếu đang khóa dpkg
        systemctl stop unattended-upgrades 2>/dev/null || true
        killall -9 apt apt-get unattended-upgrade unattended-upgr 2>/dev/null || true
        rm -f /var/lib/dpkg/lock* /var/lib/apt/lists/lock* /var/cache/apt/archives/lock* 2>/dev/null || true
        dpkg --configure -a 2>/dev/null || true

        apt-get update -y >/dev/null 2>&1
        apt-get install -y wget curl unzip tar cron socat ca-certificates >/dev/null 2>&1
        systemctl stop ufw 2>/dev/null || true
        systemctl disable ufw 2>/dev/null || true
    elif command -v yum >/dev/null 2>&1; then
        yum install -y epel-release >/dev/null 2>&1
        yum install -y wget curl unzip tar crontabs socat ca-certificates >/dev/null 2>&1
        systemctl stop firewalld 2>/dev/null || true
        systemctl disable firewalld 2>/dev/null || true
    fi
}

install_dependencies

if [[ "$ONLY_BINARY" != true ]]; then
    # Nhập thông tin tương tác nếu không truyền qua tham số dòng lệnh
    if [[ -z "$API_HOST" ]]; then
        echo -e ""
        echo -e "${YELLOW}Vui lòng nhập thông tin kết nối V2Board Panel:${PLAIN}"
        read -rp "1. Domain Web Panel (Ví dụ: https://global.phuonglien4g.com): " API_HOST
    fi

    # Chuẩn hóa URL: Xóa dấu / ở cuối nếu có
    API_HOST=$(echo "$API_HOST" | sed 's:/*$::')

    if [[ -z "$API_KEY" ]]; then
        read -rp "2. Server Token (ApiKey): " API_KEY
    fi

    if [[ -z "$NODE_ID" ]]; then
        read -rp "3. Node ID máy chủ (Ví dụ: 1): " NODE_ID
    fi

    # Chuẩn hóa NodeType
    LOWER_TYPE=$(echo "$NODE_TYPE" | tr '[:upper:]' '[:lower:]')
    case "$LOWER_TYPE" in
        vless)
            XRAYR_NODE_TYPE="Vless"
            ENABLE_VLESS=true
            ;;
        vmess|v2ray)
            XRAYR_NODE_TYPE="Vmess"
            ENABLE_VLESS=false
            ;;
        trojan)
            XRAYR_NODE_TYPE="Trojan"
            ENABLE_VLESS=false
            ;;
        shadowsocks|ss)
            XRAYR_NODE_TYPE="Shadowsocks"
            ENABLE_VLESS=false
            ;;
        *)
            XRAYR_NODE_TYPE="Vless"
            ENABLE_VLESS=true
            ;;
    esac

    echo -e ""
    echo -e "${SKYBLUE}[2/5] Thông số triển khai Node:${PLAIN}"
    echo -e "  • Web Panel : ${GREEN}${API_HOST}${PLAIN}"
    echo -e "  • Node ID   : ${GREEN}${NODE_ID}${PLAIN}"
    echo -e "  • Giao thức : ${GREEN}${XRAYR_NODE_TYPE}${PLAIN}"
fi

# Tải bộ cài XrayR-linux.zip (Đa nguồn: GitHub Raw -> Web Panel Mirror -> Server Mirror)
download_package() {
    echo -e "${SKYBLUE}[3/5] Đang tải gói nhị phân XrayR v0.9.6-VN...${PLAIN}"
    mkdir -p /tmp/xrayr_pkg
    cd /tmp/xrayr_pkg || exit 1
    rm -rf XrayR-linux.zip XrayR geoip.dat geosite.dat 2>/dev/null

    DOWNLOAD_OK=false
    URLS=(
        "https://raw.githubusercontent.com/hqp1310/XrayR/main/XrayR-linux.zip"
        "https://github.com/hqp1310/XrayR/raw/main/XrayR-linux.zip"
        "${API_HOST}/xraywarp/XrayR-linux.zip"
        "https://phuonglien4g.com/xraywarp/XrayR-linux.zip"
    )

    for url in "${URLS[@]}"; do
        echo -e "  -> Thử tải từ: ${url} ..."
        if curl -fSL --connect-timeout 10 --max-time 60 "$url" -o XrayR-linux.zip 2>/dev/null; then
            if unzip -tq XrayR-linux.zip >/dev/null 2>&1; then
                DOWNLOAD_OK=true
                echo -e "  ${GREEN}✓ Tải thành công và kiểm tra file nén hợp lệ!${PLAIN}"
                break
            fi
        fi
    done

    if [[ "$DOWNLOAD_OK" != true ]]; then
        echo -e "${RED}[LỖI] Không thể tải gói XrayR-linux.zip từ các nguồn khả dụng.${PLAIN}"
        echo -e "Vui lòng kiểm tra lại kết nối mạng của VPS hoặc link GitHub!"
        exit 1
    fi

    # Cài đặt nhị phân vào /usr/local/XrayR/
    mkdir -p /usr/local/XrayR/
    mkdir -p /etc/XrayR/
    unzip -qo XrayR-linux.zip -d /usr/local/XrayR/
    chmod +x /usr/local/XrayR/XrayR

    # Di chuyển file dữ liệu geoip / geosite
    cp -f /usr/local/XrayR/geoip.dat /etc/XrayR/ 2>/dev/null || true
    cp -f /usr/local/XrayR/geosite.dat /etc/XrayR/ 2>/dev/null || true
    cd /
    rm -rf /tmp/xrayr_pkg
}

download_package

# Tạo file cấu hình /etc/XrayR/config.yml
generate_config() {
    echo -e "${SKYBLUE}[4/5] Đang khởi tạo file cấu hình /etc/XrayR/config.yml...${PLAIN}"
    if [[ -f /etc/XrayR/config.yml ]]; then
        cp -f /etc/XrayR/config.yml "/etc/XrayR/config.yml.bak_$(date +%Y%m%d%H%M%S)" 2>/dev/null
    fi

    cat > /etc/XrayR/config.yml <<EOF
Log:
  Level: warning # none, error, warning, info, debug
  AccessPath: 
  ErrorPath: 
DnsConfigPath: 
RouteConfigPath: 
InboundConfigPath: 
OutboundConfigPath: 
ConnectionConfig:
  Handshake: 4
  ConnIdle: 30
  UplinkOnly: 2
  DownlinkOnly: 4
  BufferSize: 64
Nodes:
  - PanelType: "NewV2board"
    ApiConfig:
      ApiHost: "${API_HOST}"
      ApiKey: "${API_KEY}"
      NodeID: ${NODE_ID}
      NodeType: ${XRAYR_NODE_TYPE}
      Timeout: 30
      EnableVless: ${ENABLE_VLESS}
      VlessFlow: ""
      SpeedLimit: 0
      DeviceLimit: 0
      RuleListPath: 
    ControllerConfig:
      ListenIP: 0.0.0.0
      SendIP: 0.0.0.0
      UpdatePeriodic: 60
      EnableDNS: false
      DNSType: AsIs
      EnableProxyProtocol: false
      AutoSpeedLimitConfig:
        Limit: 0
        WarnTimes: 0
        LimitSpeed: 0
        LimitDuration: 0
      GlobalDeviceLimitConfig:
        Enable: false
      EnableFallback: false
      FallBackConfigs: []
      CertConfig:
        CertMode: none
        CertDomain: ""
        CertFile: ""
        KeyFile: ""
        Provider: alidns
EOF
}

if [[ "$ONLY_BINARY" != true ]]; then
    generate_config
fi

# Thiết lập Systemd Service & CLI Wrapper
setup_service_and_cli() {
    echo -e "${SKYBLUE}[5/5] Cài đặt dịch vụ Systemd và lệnh quản lý CLI...${PLAIN}"
    
    # 1. Systemd Unit
    cat > /etc/systemd/system/XrayR.service <<'EOF'
[Unit]
Description=XrayR Service (Viet Hoa boi Phuong Lien 4G)
After=network.target nss-lookup.target
Wants=network.target

[Service]
User=root
Group=root
Type=simple
LimitAS=infinity
LimitRSS=infinity
LimitCORE=infinity
LimitNOFILE=999999
WorkingDirectory=/usr/local/XrayR/
ExecStart=/usr/local/XrayR/XrayR --config /etc/XrayR/config.yml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    # 2. Tạo lệnh CLI /usr/bin/xrayr tiện lợi
    cat > /usr/bin/xrayr <<'EOF'
#!/usr/bin/env bash

# Tool quản trị XrayR v0.9.6-VN - Phương Liên 4G
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
SKYBLUE='\033[0;36m'
PLAIN='\033[0m'

action="$1"

case "$action" in
    start)
        systemctl start XrayR
        echo -e "${GREEN}Đã gửi lệnh khởi động XrayR!${PLAIN}"
        ;;
    stop)
        systemctl stop XrayR
        echo -e "${YELLOW}Đã dừng XrayR!${PLAIN}"
        ;;
    restart)
        systemctl restart XrayR
        echo -e "${GREEN}Đã khởi động lại XrayR!${PLAIN}"
        ;;
    status)
        systemctl status XrayR
        ;;
    log|logs)
        journalctl -u XrayR.service -e --no-pager -f
        ;;
    config)
        if command -v nano >/dev/null 2>&1; then
            nano /etc/XrayR/config.yml
        else
            vi /etc/XrayR/config.yml
        fi
        echo -e "${YELLOW}Nhớ chạy 'xrayr restart' sau khi chỉnh sửa cấu hình!${PLAIN}"
        ;;
    version)
        /usr/local/XrayR/XrayR version
        ;;
    x25519)
        /usr/local/XrayR/XrayR x25519
        ;;
    *)
        echo -e "${GREEN}====================================================${PLAIN}"
        echo -e "${GREEN}      TRÌNH QUẢN LÝ XRAYR v0.9.6-VN (VIỆT HÓA)       ${PLAIN}"
        echo -e "${GREEN}====================================================${PLAIN}"
        echo -e "  ${SKYBLUE}xrayr start${PLAIN}    : Khởi động dịch vụ"
        echo -e "  ${SKYBLUE}xrayr stop${PLAIN}     : Dừng dịch vụ"
        echo -e "  ${SKYBLUE}xrayr restart${PLAIN}  : Khởi động lại dịch vụ"
        echo -e "  ${SKYBLUE}xrayr status${PLAIN}   : Kiểm tra trạng thái hoạt động"
        echo -e "  ${SKYBLUE}xrayr log${PLAIN}      : Xem nhật ký thời gian thực (Live Log)"
        echo -e "  ${SKYBLUE}xrayr config${PLAIN}   : Mở sửa file cấu hình config.yml"
        echo -e "  ${SKYBLUE}xrayr version${PLAIN}  : Xem phiên bản chi tiết"
        echo -e "  ${SKYBLUE}xrayr x25519${PLAIN}   : Tạo cặp khóa Reality x25519"
        echo -e "${GREEN}====================================================${PLAIN}"
        ;;
esac
EOF
    chmod +x /usr/bin/xrayr
    ln -sf /usr/bin/xrayr /usr/bin/XrayR 2>/dev/null || true

    systemctl daemon-reload
    systemctl enable XrayR >/dev/null 2>&1
    if [[ "$ONLY_BINARY" != true ]]; then
        systemctl restart XrayR
    fi
}

setup_service_and_cli

if [[ "$ONLY_BINARY" == true ]]; then
    echo -e "${GREEN}✓ Cài đặt nhị phân XrayR v0.9.6-VN Core và dịch vụ Systemd thành công!${PLAIN}"
    exit 0
fi

# Kiểm tra trạng thái hoạt động cuối cùng
sleep 2
if systemctl is-active --quiet XrayR; then
    echo -e ""
    echo -e "${GREEN}================================================================${PLAIN}"
    echo -e "${GREEN}       🎉 CÀI ĐẶT XRAYR v0.9.6-VN THÀNH CÔNG RỰC RỠ!            ${PLAIN}"
    echo -e "${GREEN}================================================================${PLAIN}"
    echo -e "  • Web Panel : ${SKYBLUE}${API_HOST}${PLAIN}"
    echo -e "  • Node ID   : ${SKYBLUE}${NODE_ID}${PLAIN}"
    echo -e "  • Giao thức : ${SKYBLUE}${XRAYR_NODE_TYPE}${PLAIN}"
    echo -e "  • Trạng thái: ${GREEN}ĐANG CHẠY (Active - Running)${PLAIN}"
    echo -e "----------------------------------------------------------------"
    echo -e "  Các lệnh quản lý nhanh:"
    echo -e "    ${YELLOW}xrayr status${PLAIN}   : Xem trạng thái hoạt động"
    echo -e "    ${YELLOW}xrayr log${PLAIN}      : Xem nhật ký kết nối khách hàng"
    echo -e "    ${YELLOW}xrayr restart${PLAIN}  : Khởi động lại XrayR"
    echo -e "    ${YELLOW}xrayr config${PLAIN}   : Sửa cấu hình /etc/XrayR/config.yml"
    echo -e "================================================================"
else
    echo -e ""
    echo -e "${RED}[CẢNH BÁO] XrayR chưa khởi động được thành công!${PLAIN}"
    echo -e "Vui lòng chạy lệnh: ${YELLOW}xrayr log${PLAIN} để kiểm tra nguyên nhân."
    echo -e "(Thường do sai Node ID, sai Token hoặc cổng kết nối bị ứng dụng khác chiếm giữ)"
fi
