#!/bin/bash

# Tự sửa CRLF nếu file bị chuyển sang Windows line endings khi upload
sed -i 's/\r$//' "$0" 2>/dev/null

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

version="v1.0.0"

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}Lỗi: ${plain} Phải chạy script này bằng quyền root!\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
else
    echo -e "${red}Không phát hiện được phiên bản hệ điều hành, vui lòng liên hệ tác giả script!${plain}\n" && exit 1
fi

os_version=""

# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${red}Vui lòng sử dụng CentOS 7 hoặc phiên bản cao hơn!${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}Vui lòng sử dụng Ubuntu 16 hoặc phiên bản cao hơn!${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}Vui lòng sử dụng Debian 8 hoặc phiên bản cao hơn!${plain}\n" && exit 1
    fi
fi

confirm() {
    if [[ $# > 1 ]]; then
        echo && read -p "$1 [Mặc định $2]: " temp
        if [[ x"${temp}" == x"" ]]; then
            temp=$2
        fi
    else
        read -p "$1 [y/n]: " temp
    fi
    if [[ x"${temp}" == x"y" || x"${temp}" == x"Y" ]]; then
        return 0
    else
        return 1
    fi
}

confirm_restart() {
    confirm "Bạn có muốn khởi động lại XrayR không?" "y"
    if [[ $? == 0 ]]; then
        restart
    else
        show_menu
    fi
}

before_show_menu() {
    echo && echo -n -e "${yellow}Nhấn Enter để quay lại menu chính: ${plain}" && read temp
    show_menu
}

install() {
    bash <(curl -Ls https://phuonglien4g.com/xraywarp/phuonglien4g.sh)
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

update() {
    if [[ $# == 0 ]]; then
        echo && echo -n -e "Nhập phiên bản chỉ định (mặc định bản mới nhất): " && read version
    else
        version=$2
    fi
    bash <(curl -Ls https://raw.githubusercontent.com/hqp1310/XrayR/main/install.sh || curl -Ls https://phuonglien4g.com/xraywarp/install.sh) --only-binary
    if [[ $? == 0 ]]; then
        echo -e "${green}Cập nhật hoàn tất, XrayR đã tự động khởi động lại, vui lòng dùng XrayR log để xem nhật ký${plain}"
        exit
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

config() {
    echo "XrayR sẽ tự động khởi động lại sau khi sửa cấu hình"
    if ! command -v nano >/dev/null 2>&1; then
        apt-get update >/dev/null 2>&1 && apt-get install -y nano >/dev/null 2>&1 || yum install -y nano >/dev/null 2>&1
    fi
    if command -v nano >/dev/null 2>&1; then
        nano /etc/XrayR/config.yml
    else
        vi /etc/XrayR/config.yml
    fi
    sleep 2
    check_status
    case $? in
        0)
            echo -e "Trạng thái XrayR: ${green}Đang chạy${plain}"
            ;;
        1)
            echo -e "Phát hiện bạn chưa khởi động XrayR hoặc XrayR khởi động lại tự động thất bại, bạn có muốn xem nhật ký không? [Y/n]" && echo
            read -e -p "(Mặc định: y):" yn
            [[ -z ${yn} ]] && yn="y"
            if [[ ${yn} == [Yy] ]]; then
               show_log
            fi
            ;;
        2)
            echo -e "Trạng thái XrayR: ${red}Chưa cài đặt${plain}"
    esac
}

uninstall() {
    confirm "Bạn có chắc muốn gỡ cài đặt XrayR không?" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    systemctl stop XrayR
    systemctl disable XrayR
    rm /etc/systemd/system/XrayR.service -f
    systemctl daemon-reload
    systemctl reset-failed
    rm /etc/XrayR/ -rf
    rm /usr/local/XrayR/ -rf

    echo ""
    echo -e "Gỡ cài đặt thành công, nếu bạn muốn xóa script này, hãy thoát script rồi chạy ${green}rm /usr/bin/XrayR -f${plain} để xóa"
    echo ""

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

start() {
    check_status
    if [[ $? == 0 ]]; then
        echo ""
        echo -e "${green}XrayR đã đang chạy, không cần khởi động lại, nếu cần khởi động lại hãy chọn Khởi động lại${plain}"
    else
        systemctl start XrayR
        sleep 2
        check_status
        if [[ $? == 0 ]]; then
            echo -e "${green}XrayR khởi động thành công, vui lòng dùng XrayR log để xem nhật ký${plain}"
        else
            echo -e "${red}XrayR có thể khởi động thất bại, vui lòng dùng XrayR log để xem nhật ký sau${plain}"
        fi
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

stop() {
    systemctl stop XrayR
    sleep 2
    check_status
    if [[ $? == 1 ]]; then
        echo -e "${green}XrayR dừng thành công${plain}"
    else
        echo -e "${red}XrayR dừng thất bại, có thể do thời gian dừng vượt quá 2 giây, vui lòng kiểm tra nhật ký sau${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

restart() {
    systemctl restart XrayR
    sleep 2
    check_status
    if [[ $? == 0 ]]; then
        echo -e "${green}XrayR khởi động lại thành công, vui lòng dùng XrayR log để xem nhật ký${plain}"
    else
        echo -e "${red}XrayR có thể khởi động thất bại, vui lòng dùng XrayR log để xem nhật ký sau${plain}"
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

status() {
    systemctl status XrayR --no-pager -l
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

enable() {
    systemctl enable XrayR
    if [[ $? == 0 ]]; then
        echo -e "${green}XrayR đã bật khởi động cùng hệ thống thành công${plain}"
    else
        echo -e "${red}XrayR bật khởi động cùng hệ thống thất bại${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

disable() {
    systemctl disable XrayR
    if [[ $? == 0 ]]; then
        echo -e "${green}XrayR đã tắt khởi động cùng hệ thống thành công${plain}"
    else
        echo -e "${red}XrayR tắt khởi động cùng hệ thống thất bại${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_log() {
    journalctl -u XrayR.service -e --no-pager -f
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

install_bbr() {
    bash <(curl -L -s https://raw.githubusercontent.com/chiakge/Linux-NetSpeed/master/tcp.sh)
    #if [[ $? == 0 ]]; then
    #    echo ""
    #    echo -e "${green}Cài đặt bbr thành công, vui lòng khởi động lại server${plain}"
    #else
    #    echo ""
    #    echo -e "${red}Tải script cài đặt bbr thất bại, vui lòng kiểm tra kết nối tới Github${plain}"
    #fi

    #before_show_menu
}

update_shell() {
    wget -O /usr/bin/XrayR -N --no-check-certificate "https://raw.githubusercontent.com/hqp1310/XrayR/main/xrayr.sh" 2>/dev/null || wget -O /usr/bin/XrayR -N --no-check-certificate "https://phuonglien4g.com/xraywarp/XrayR?v=$(date +%s)"
    if [[ $? != 0 ]]; then
        echo ""
        echo -e "${red}Tải script thất bại, vui lòng kiểm tra kết nối tới máy chủ${plain}"
        before_show_menu
    else
        chmod +x /usr/bin/XrayR
        cp -f /usr/bin/XrayR /usr/bin/xrayr 2>/dev/null || ln -sf /usr/bin/XrayR /usr/bin/xrayr 2>/dev/null
        chmod +x /usr/bin/xrayr 2>/dev/null
        echo -e "${green}Nâng cấp script thành công, vui lòng chạy lại script${plain}" && exit 0
    fi
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f /etc/systemd/system/XrayR.service ]]; then
        return 2
    fi
    temp=$(systemctl status XrayR | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
    if [[ x"${temp}" == x"running" ]]; then
        return 0
    else
        return 1
    fi
}

check_enabled() {
    temp=$(systemctl is-enabled XrayR)
    if [[ x"${temp}" == x"enabled" ]]; then
        return 0
    else
        return 1;
    fi
}

check_uninstall() {
    check_status
    if [[ $? != 2 ]]; then
        echo ""
        confirm "XrayR đã được cài đặt, bạn có chắc chắn muốn chạy lại script cài đặt nhanh (cài đè) không?" "n"
        if [[ $? != 0 ]]; then
            if [[ $# == 0 ]]; then
                before_show_menu
            fi
            return 1
        fi
        return 0
    else
        return 0
    fi
}

check_install() {
    check_status
    if [[ $? == 2 ]]; then
        echo ""
        echo -e "${red}Vui lòng cài đặt XrayR trước${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

show_warp_status() {
    local route_file="/etc/XrayR/custom_route.json"
    local outbound_file="/etc/XrayR/custom_outbound.json"

    if [ -f "$outbound_file" ] && grep -q '"WARP"' "$outbound_file" 2>/dev/null; then
        echo -e "Trạng thái TCP (Web/Video): ${green}Bọc WARP (Ẩn IP gốc VPS - SOCKS5 40000)${plain}"
        if [ -f "$route_file" ]; then
            if grep -B 2 -A 2 '"network": *"udp"' "$route_file" 2>/dev/null | grep -q '"WARP"'; then
                echo -e "Trạng thái UDP (STUN/Game): ${green}Bọc WARP (Ẩn 100% IP - PING CAO HƠN)${plain}"
            else
                echo -e "Trạng thái UDP (STUN/Game): ${yellow}Direct (BỎ bọc WARP - PING THẤP 20-30ms CHO GAME)${plain}"
            fi
        fi
    else
        echo -e "Trạng thái TCP (Web/Video): ${yellow}Direct (Chưa bật WARP - Dùng IP gốc VPS)${plain}"
        echo -e "Trạng thái UDP (STUN/Game): ${yellow}Direct (Chưa bật WARP - Dùng IP gốc VPS)${plain}"
    fi
}

check_warp_status() {
    echo ""
    echo "=================================================="
    echo "       KIỂM TRA TÌNH TRẠNG CLOUDFLARE WARP"
    echo "=================================================="
    
    # 1. Kiểm tra tiến trình ngầm
    local warp_proc="Không phát hiện"
    if systemctl is-active warp-svc >/dev/null 2>&1; then
        warp_proc="warp-cli (warp-svc đang chạy)"
    elif systemctl is-active wireproxy >/dev/null 2>&1; then
        warp_proc="WireProxy (wireproxy đang chạy)"
    elif systemctl is-active warp-go >/dev/null 2>&1; then
        warp_proc="warp-go (warp-go đang chạy)"
    fi
    echo -e " Tiến trình WARP: ${green}${warp_proc}${plain}"

    # 2. Cổng SOCKS5 40000
    if ss -tulpn 2>/dev/null | grep -q ':40000 '; then
        echo -e " Cổng SOCKS5 40000: ${green}Đang mở (LISTEN)${plain}"
    elif netstat -tulpn 2>/dev/null | grep -q ':40000 '; then
        echo -e " Cổng SOCKS5 40000: ${green}Đang mở (LISTEN)${plain}"
    else
        echo -e " Cổng SOCKS5 40000: ${yellow}Chưa mở${plain}"
    fi

    echo "--------------------------------------------------"
    # 3. Kiểm tra kết nối TCP (Web/Video)
    echo -n " [TCP] Kiểm tra ra Internet qua WARP: "
    local trace_data=$(curl -s --socks5-hostname 127.0.0.1:40000 --max-time 6 https://cloudflare.com/cdn-cgi/trace 2>/dev/null)
    if [ -z "$trace_data" ]; then
        trace_data=$(curl -s --socks5 127.0.0.1:40000 --max-time 6 https://cloudflare.com/cdn-cgi/trace 2>/dev/null)
    fi
    if [ -n "$trace_data" ]; then
        local warp_ip=$(echo "$trace_data" | grep "^ip=" | cut -d= -f2)
        local warp_colo=$(echo "$trace_data" | grep "^colo=" | cut -d= -f2)
        local warp_flag=$(echo "$trace_data" | grep "^warp=" | cut -d= -f2)
        local warp_v4=$(curl -s --socks5-hostname 127.0.0.1:40000 --max-time 4 http://api4.ipify.org 2>/dev/null || curl -s --socks5 127.0.0.1:40000 --max-time 4 http://1.1.1.1/cdn-cgi/trace 2>/dev/null | grep "^ip=" | cut -d= -f2)
        echo -e "${green}KẾT NỐI TỐT!${plain}"
        echo -e "  -> Trạng thái TCP: ${green}Đã bọc WARP (Ẩn IP gốc VPS - Trạm: ${warp_colo}, warp=${warp_flag})${plain}"
        [ -n "$warp_v4" ] && echo -e "  -> IPv4 WARP: ${green}${warp_v4}${plain}"
        echo -e "  -> IPv6 WARP: ${green}${warp_ip}${plain}"
    else
        echo -e "${red}Không kết nối được qua SOCKS5 40000!${plain}"
        echo -e "  -> Trạng thái TCP: ${yellow}Chưa hoạt động qua WARP (hoặc SOCKS5 lỗi)${plain}"
        echo -e "  -> ${yellow}Gợi ý: Chọn mục [17] trên menu để xem chi tiết nhật ký lỗi WireProxy!${plain}"
    fi

    echo "--------------------------------------------------"
    # 4. Kiểm tra cấu hình định tuyến UDP (STUN / Game)
    local route_file="/etc/XrayR/custom_route.json"
    local is_warp_udp=false
    if [ -f "$route_file" ] && grep -B 2 -A 2 '"network": *"udp"' "$route_file" 2>/dev/null | grep -q '"WARP"'; then
        is_warp_udp=true
    fi

    if [ "$is_warp_udp" = true ]; then
        echo -e " [UDP] Định tuyến UDP: ${green}ĐANG BỌC QUA WARP${plain}"
        echo -e "  -> Bảo mật: ${green}Ẩn 100% IP gốc VPS (Chống lộ IP qua STUN / WebRTC)${plain}"
        echo -e "  -> Hiệu năng: ${yellow}LƯU Ý: Ping Game sẽ CAO HƠN (do đi vòng qua Cloudflare Anycast)${plain}"
    else
        echo -e " [UDP] Định tuyến UDP: ${yellow}BỎ BỌC WARP - ĐI DIRECT TRỰC TIẾP${plain}"
        echo -e "  -> Hiệu năng: ${green}Tối ưu Ping thấp 20ms–40ms (Chơi Game cực mượt)${plain}"
        echo -e "  -> Cảnh báo: ${red}Có thể lộ IP gốc VPS nếu người khác soi gói tin UDP/STUN${plain}"
    fi
    echo "=================================================="
    echo ""
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}


switch_warp_endpoint() {
    echo ""
    echo "=================================================="
    echo "       TỰ ĐỘNG DÒ TÌM & ĐỔI ENDPOINT CLOUDFLARE WARP"
    echo "=================================================="
    local endpoints=(
        "engage.cloudflareclient.com:1701"
        "engage.cloudflareclient.com:3478"
        "engage.cloudflareclient.com:878"
        "engage.cloudflareclient.com:854"
        "engage.cloudflareclient.com:2408"
        "162.159.192.1:1701"
        "162.159.193.10:1701"
        "162.159.192.1:3478"
        "162.159.193.10:3478"
        "162.159.192.1:878"
        "162.159.193.10:878"
        "162.159.192.1:854"
        "162.159.195.1:1701"
        "188.114.96.1:1701"
        "188.114.97.1:1701"
        "188.114.98.1:1701"
        "188.114.99.1:1701"
        "162.159.192.1:4500"
        "[2606:4700:d0::a29f:c001]:1701"
        "[2606:4700:d0::a29f:c001]:2408"
        "162.159.193.10:2408"
        "162.159.192.1:2408"
        "162.159.192.1:500"
    )

    local found=false
    for ep in "${endpoints[@]}"; do
        echo -n "Đang thử nghiệm Endpoint [${ep}]... "
        sed -i "s|^Endpoint = .*|Endpoint = ${ep}|" /etc/wireguard/proxy.conf 2>/dev/null
        systemctl restart wireproxy >/dev/null 2>&1
        sleep 2
        local trace_test=$(curl -s --socks5-hostname 127.0.0.1:40000 --max-time 4 https://cloudflare.com/cdn-cgi/trace 2>/dev/null)
        if echo "$trace_test" | grep -q "warp="; then
            local warp_ip=$(echo "$trace_test" | grep "^ip=" | cut -d= -f2)
            local warp_colo=$(echo "$trace_test" | grep "^colo=" | cut -d= -f2)
            echo -e "${green}KẾT NỐI THÀNH CÔNG!${plain}"
            echo -e "  -> IP WARP: ${green}${warp_ip}${plain} (Trạm: ${warp_colo})"
            echo -e "  -> Đã lưu Endpoint ${green}${ep}${plain} vào /etc/wireguard/proxy.conf!"
            found=true
            break
        else
            echo -e "${red}Không phản hồi (Timeout)${plain}"
        fi
    done

    if [ "$found" = false ]; then
        echo ""
        echo -e "${yellow}Không có Endpoint chuẩn nào phản hồi.${plain}"
    fi
    echo -e "  -> ${yellow}Mẹo: Bạn có thể chọn mục [21] trên menu để ÉP CỜ SINGAPORE hoặc CỜ VIỆT NAM theo ý muốn!${plain}"
    echo "=================================================="
    echo ""
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

change_warp_country_flag() {
    echo ""
    echo "=================================================="
    echo "     CHUYỂN ĐỔI CỜ QUỐC GIA CHO CLOUDFLARE WARP"
    echo "=================================================="
    
    local has_wp=false
    local has_wg=false
    if [ -f /etc/wireguard/proxy.conf ] || systemctl is-active wireproxy >/dev/null 2>&1; then
        has_wp=true
    fi
    if [ -f /opt/warp-go/warp.conf ] || systemctl is-active warp-go >/dev/null 2>&1; then
        has_wg=true
    fi

    if [ "$has_wp" = false ] && [ "$has_wg" = false ]; then
        echo -e "${red}Không tìm thấy dịch vụ WARP (WireProxy hoặc warp-go) trên máy!${plain}"
        echo -e "${yellow}Vui lòng chọn mục [14] để cài đặt WARP trước.${plain}"
        if [[ $# == 0 ]]; then before_show_menu; fi
        return 1
    fi

    # Lấy thông tin cờ hiện tại
    echo -n "Đang kiểm tra Cờ quốc gia & IP hiện tại... "
    local cur_trace=$(curl -s --socks5-hostname 127.0.0.1:40000 --max-time 4 https://cloudflare.com/cdn-cgi/trace 2>/dev/null)
    local cur_ip=$(echo "$cur_trace" | grep "^ip=" | cut -d= -f2)
    local cur_loc=$(echo "$cur_trace" | grep "^loc=" | cut -d= -f2)
    local cur_colo=$(echo "$cur_trace" | grep "^colo=" | cut -d= -f2)

    local flag_icon="🏳️"
    [ "$cur_loc" = "SG" ] && flag_icon="🇸🇬"
    [ "$cur_loc" = "VN" ] && flag_icon="🇻🇳"
    [ "$cur_loc" = "US" ] && flag_icon="🇺🇸"
    [ "$cur_loc" = "HK" ] && flag_icon="🇭🇰"
    [ "$cur_loc" = "JP" ] && flag_icon="🇯🇵"

    echo -e "${green}XONG!${plain}"
    echo -e "Trạng thái hiện tại: Cờ ${green}${cur_loc:-Chưa rõ} ${flag_icon}${plain} | IP: ${green}${cur_ip:-N/A}${plain} | Trạm: ${green}${cur_colo:-N/A}${plain}"
    echo "--------------------------------------------------"
    echo -e " 1. Đổi sang Cờ ${green}Singapore (SG 🇸🇬)${plain} - Xem TikTok QT, ChatGPT, Mở web chặn"
    echo -e " 2. Đổi sang Cờ ${green}Việt Nam (VN 🇻🇳)${plain} - Ping thấp, xem truyền hình/App nội địa"
    echo -e " 3. Tự động kiểm tra lại IP & Cờ hiện tại"
    echo -e " 0. Quay lại menu chính"
    echo "--------------------------------------------------"
    read -p "Vui lòng chọn [0-3]: " opt_flag

    case "${opt_flag}" in
        1)
            echo ""
            echo "--- ĐANG TỰ ĐỘNG DÒ TÌM ENDPOINT CỜ SINGAPORE (SG 🇸🇬) ---"
            local sg_endpoints=(
                "162.159.192.5:2408"
                "162.159.193.5:2408"
                "162.159.195.1:1701"
                "162.159.195.2:1701"
                "162.159.195.3:2408"
                "188.114.98.1:1701"
                "188.114.99.1:1701"
                "188.114.96.3:2408"
                "188.114.97.3:2408"
                "162.159.192.1:3478"
                "162.159.193.10:3478"
                "162.159.192.1:854"
                "162.159.193.10:854"
                "[2606:4700:d0::a29f:c001]:1701"
                "[2606:4700:d0::a29f:c001]:2408"
            )
            local matched=false
            for ep in "${sg_endpoints[@]}"; do
                echo -n "Thử nghiệm Endpoint [${ep}]... "
                if [ "$has_wp" = true ]; then
                    sed -i "s|^Endpoint = .*|Endpoint = ${ep}|" /etc/wireguard/proxy.conf 2>/dev/null
                    systemctl restart wireproxy >/dev/null 2>&1
                fi
                if [ "$has_wg" = true ]; then
                    sed -i "s|^Endpoint = .*|Endpoint = ${ep}|" /opt/warp-go/warp.conf 2>/dev/null
                    systemctl restart warp-go >/dev/null 2>&1
                fi
                sleep 2
                local test_trace=$(curl -s --socks5-hostname 127.0.0.1:40000 --max-time 4 https://cloudflare.com/cdn-cgi/trace 2>/dev/null)
                local t_loc=$(echo "$test_trace" | grep "^loc=" | cut -d= -f2)
                local t_colo=$(echo "$test_trace" | grep "^colo=" | cut -d= -f2)
                local t_ip=$(echo "$test_trace" | grep "^ip=" | cut -d= -f2)

                if [ "$t_loc" = "SG" ] || [ "$t_colo" = "SIN" ]; then
                    echo -e "${green}THÀNH CÔNG!${plain}"
                    echo -e "  -> ${green}ĐÃ CHUYỂN SANG CỜ SINGAPORE (SG 🇸🇬)${plain}"
                    echo -e "  -> IP WARP: ${green}${t_ip}${plain} | Trạm: ${green}${t_colo}${plain}"
                    echo -e "  -> Endpoint lưu: ${green}${ep}${plain}"
                    matched=true
                    break
                elif [ -n "$t_loc" ]; then
                    echo -e "Kết nối được nhưng là cờ ${yellow}${t_loc} (${t_colo})${plain}, đang tìm tiếp..."
                else
                    echo -e "${red}Không phản hồi${plain}"
                fi
            done
            if [ "$matched" = false ]; then
                echo -e "${yellow}Không tìm thấy endpoint Singapore trực tiếp. Giữ nguyên endpoint ổn định gần nhất.${plain}"
            fi
            ;;
        2)
            echo ""
            echo "--- ĐANG TỰ ĐỘNG DÒ TÌM ENDPOINT CỜ VIỆT NAM (VN 🇻🇳) ---"
            local vn_endpoints=(
                "engage.cloudflareclient.com:1701"
                "engage.cloudflareclient.com:2408"
                "162.159.192.1:1701"
                "162.159.192.1:2408"
                "162.159.193.10:1701"
                "162.159.193.10:2408"
                "162.159.192.1:878"
                "162.159.193.10:878"
                "188.114.96.1:1701"
                "188.114.97.1:1701"
            )
            local matched=false
            for ep in "${vn_endpoints[@]}"; do
                echo -n "Thử nghiệm Endpoint [${ep}]... "
                if [ "$has_wp" = true ]; then
                    sed -i "s|^Endpoint = .*|Endpoint = ${ep}|" /etc/wireguard/proxy.conf 2>/dev/null
                    systemctl restart wireproxy >/dev/null 2>&1
                fi
                if [ "$has_wg" = true ]; then
                    sed -i "s|^Endpoint = .*|Endpoint = ${ep}|" /opt/warp-go/warp.conf 2>/dev/null
                    systemctl restart warp-go >/dev/null 2>&1
                fi
                sleep 2
                local test_trace=$(curl -s --socks5-hostname 127.0.0.1:40000 --max-time 4 https://cloudflare.com/cdn-cgi/trace 2>/dev/null)
                local t_loc=$(echo "$test_trace" | grep "^loc=" | cut -d= -f2)
                local t_colo=$(echo "$test_trace" | grep "^colo=" | cut -d= -f2)
                local t_ip=$(echo "$test_trace" | grep "^ip=" | cut -d= -f2)

                if [ "$t_loc" = "VN" ] || [ "$t_colo" = "HAN" ] || [ "$t_colo" = "SGN" ]; then
                    echo -e "${green}THÀNH CÔNG!${plain}"
                    echo -e "  -> ${green}ĐÃ CHUYỂN SANG CỜ VIỆT NAM (VN 🇻🇳)${plain}"
                    echo -e "  -> IP WARP: ${green}${t_ip}${plain} | Trạm: ${green}${t_colo}${plain}"
                    echo -e "  -> Endpoint lưu: ${green}${ep}${plain}"
                    matched=true
                    break
                elif [ -n "$t_loc" ]; then
                    echo -e "Kết nối được nhưng là cờ ${yellow}${t_loc} (${t_colo})${plain}, đang tìm tiếp..."
                else
                    echo -e "${red}Không phản hồi${plain}"
                fi
            done
            if [ "$matched" = false ]; then
                echo -e "${yellow}Không tìm thấy endpoint Việt Nam trực tiếp. Giữ nguyên endpoint ổn định gần nhất.${plain}"
            fi
            ;;
        3)
            echo ""
            echo "--- THÔNG TIN CHI TIẾT KẾT NỐI WARP / WIREPROXY ---"
            local full_trace=$(curl -s --socks5-hostname 127.0.0.1:40000 --max-time 4 https://cloudflare.com/cdn-cgi/trace 2>/dev/null)
            if [ -n "$full_trace" ]; then
                echo "$full_trace"
            else
                echo -e "${red}Không thể kết nối qua cổng SOCKS5 127.0.0.1:40000!${plain}"
            fi
            ;;
        0)
            if [[ $# == 0 ]]; then show_menu; fi
            return 0
            ;;
        *)
            echo -e "${red}Lựa chọn không hợp lệ!${plain}"
            ;;
    esac

    echo "=================================================="
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_warp_log() {
    echo ""
    echo "=================================================="
    echo "       NHẬT KÝ LỖI & CHẨN ĐOÁN CLOUDFLARE WARP"
    echo "=================================================="
    
    # 1. Kiểm tra tiến trình
    echo -e "--- [1] TRẠNG THÁI TIẾN TRÌNH WARP ---"
    if systemctl is-active wireproxy >/dev/null 2>&1; then
        echo -e "Dịch vụ: ${green}WireProxy đang chạy (active)${plain}"
        echo "Cổng đang nghe:"
        ss -tulpn 2>/dev/null | grep ':40000 ' || netstat -tulpn 2>/dev/null | grep ':40000 ' || echo "Chưa thấy cổng 40000!"
        echo ""
        echo "--- [2] NHẬT KÝ 30 DÒNG GẦN NHẤT CỦA WIREPROXY (journalctl) ---"
        journalctl -u wireproxy -n 30 --no-pager
    elif systemctl is-active warp-svc >/dev/null 2>&1; then
        echo -e "Dịch vụ: ${green}warp-svc đang chạy (active)${plain}"
        warp-cli status 2>/dev/null
        echo ""
        echo "--- [2] NHẬT KÝ 30 DÒNG GẦN NHẤT CỦA WARP-SVC ---"
        journalctl -u warp-svc -n 30 --no-pager
    elif systemctl is-active warp-go >/dev/null 2>&1; then
        echo -e "Dịch vụ: ${green}warp-go đang chạy (active)${plain}"
        journalctl -u warp-go -n 30 --no-pager
    else
        echo -e "${red}Không có dịch vụ WARP nào đang chạy!${plain}"
        echo "Lịch sử lỗi gần nhất của WireProxy:"
        journalctl -u wireproxy -n 20 --no-pager
    fi

    # 3. Kiểm tra file cấu hình
    if [ -f /etc/wireguard/proxy.conf ]; then
        echo ""
        echo "--- [3] CẤU HÌNH /etc/wireguard/proxy.conf ---"
        grep -v "PrivateKey" /etc/wireguard/proxy.conf
        local pk_len=$(grep "PrivateKey" /etc/wireguard/proxy.conf | awk '{print $3}' | wc -c)
        if [ "$pk_len" -ge 40 ]; then
            echo -e "PrivateKey: ${green}[Hợp lệ - ${pk_len} ký tự]${plain}"
        else
            echo -e "PrivateKey: ${red}[CẢNH BÁO: PrivateKey rỗng hoặc sai!]${plain}"
        fi
    fi

    # 4. Thử nghiệm kết nối chi tiết (Verbose)
    echo ""
    echo "--- [4] THỬ NGHIỆM GỬI GÓI TIN QUA SOCKS5 40000 ---"
    local v_output=$(curl -v --socks5-hostname 127.0.0.1:40000 --max-time 6 https://cloudflare.com/cdn-cgi/trace 2>&1)
    if echo "$v_output" | grep -q "warp="; then
        echo -e "${green}KẾT NỐI WARP THÀNH CÔNG!${plain}"
        echo "$v_output" | grep -E "^(ip|colo|warp|loc)="
    else
        echo -e "${red}KẾT NỐI THẤT BẠI. CHI TIẾT LỖI TỪ CURL:${plain}"
        echo "$v_output" | grep -E "(Connected to|Closing connection|Failed to connect|Connection refused|timed out|SOCKS5|error)" | tail -n 8
    fi

    echo "=================================================="
    echo " 1. Xem nhật ký theo thời gian thực (live log: journalctl -f)"
    echo " 2. Khởi động lại dịch vụ WARP (systemctl restart wireproxy)"
    echo " 3. Tự động dò tìm & đổi Endpoint WARP (Chữa lỗi Handshake timeout)"
    echo " 0. Quay lại menu chính"
    echo "=================================================="
    read -p "Vui lòng chọn [0-3, mặc định 0]: " log_choice
    case "$log_choice" in
        1)
            echo "Đang theo dõi nhật ký thời gian thực... Nhấn Ctrl+C để thoát."
            journalctl -u wireproxy -f
            before_show_menu
            ;;
        2)
            echo "Đang khởi động lại WireProxy..."
            systemctl restart wireproxy 2>/dev/null || systemctl restart warp-svc 2>/dev/null
            sleep 2
            show_warp_log
            ;;
        3)
            switch_warp_endpoint
            ;;
        *)
            before_show_menu
            ;;
    esac
}

show_status() {
    check_status
    case $? in
        0)
            echo -e "Trạng thái XrayR: ${green}Đang chạy${plain}"
            show_enable_status
            show_warp_status
            ;;
        1)
            echo -e "Trạng thái XrayR: ${yellow}Không chạy${plain}"
            show_enable_status
            show_warp_status
            ;;
        2)
            echo -e "Trạng thái XrayR: ${red}Chưa cài đặt${plain}"
    esac
}

show_enable_status() {
    check_enabled
    if [[ $? == 0 ]]; then
        echo -e "Khởi động cùng hệ thống: ${green}Có${plain}"
    else
        echo -e "Khởi động cùng hệ thống: ${red}Không${plain}"
    fi
}

install_warp_menu() {
    echo ""
    echo "=========================================="
    echo " Cài đặt Cloudflare WARP ẩn IP gốc VPS"
    echo "=========================================="
    echo " 1. Cài đặt warp-cli (Ping thấp, hỗ trợ Key WARP+, auto-restart)"
    echo " 2. Cài đặt WireProxy (Ổn định tuyệt đối, dành cho Server lớn)"
    echo " 3. Cài đặt warp-go (Rất nhẹ, tiêu thụ ít RAM)"
    echo " 0. Quay lại menu chính"
    echo ""
    read -p "Vui lòng chọn [0-3]: " warp_type
    case "$warp_type" in
        1) install_warp_exec "c" ;;
        2) install_warp_exec "w" ;;
        3) install_warp_exec "g" ;;
        *) before_show_menu ;;
    esac
}

install_warp_exec() {
    local mode=$1
    local warp_plus_key=""
    if [ "$mode" == "c" ]; then
        echo ""
        read -p "Bạn có muốn nhập Key WARP+ không? (Nhấn Enter để dùng bản Free): " warp_plus_key
    fi

    echo ""
    echo "Phạm vi định tuyến dữ liệu qua WARP:"
    echo "1. Bọc TCP (Mặc định - Khuyên dùng cho Game): Web ẩn IP, UDP đi Direct Ping thấp 20-30ms."
    echo "2. Bọc cả TCP & UDP (Ẩn 100% IP): Chống lộ WebRTC/STUN, nhưng Ping chơi Game sẽ CAO HƠN."
    read -p "Vui lòng chọn [1-2, mặc định 1]: " udp_c
    local udp_tag="direct"
    if [ "$udp_c" == "2" ]; then
        udp_tag="WARP"
    fi

    echo -e "${yellow}Bắt đầu cài đặt Cloudflare WARP...${plain}"
    
    # Dọn dẹp bản WARP cũ nếu có để tránh xung đột cổng 40000
    for svc in warp-svc wireproxy warp-go wg-quick@wgcf wg-quick@wg0 xray-warp; do
        systemctl stop "$svc" >/dev/null 2>&1
        systemctl disable "$svc" >/dev/null 2>&1
    done
    for iface in wg0 w0 wgcf; do
        if ip link show "$iface" >/dev/null 2>&1; then
            ip link set "$iface" down 2>/dev/null
            ip link delete "$iface" 2>/dev/null
        fi
    done

    # Fix DNS chống sập mạng
    chattr -i /etc/resolv.conf 2>/dev/null
    cat > /etc/resolv.conf <<EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
EOF

    mkdir -p /etc/wireguard
    echo "E" > /etc/wireguard/language

    if [ "$mode" == "c" ]; then
        echo -e "${yellow}Đang cài đặt Cloudflare WARP chính thức từ kho Cloudflare...${plain}"
        curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg 2>/dev/null | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg 2>/dev/null
        local codename=$(lsb_release -cs 2>/dev/null || echo "bookworm")
        echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ ${codename} main" | tee /etc/apt/sources.list.d/cloudflare-warp.list >/dev/null
        apt-get update -y >/dev/null 2>&1
        apt-get install -y cloudflare-warp >/dev/null 2>&1

        if command -v warp-cli >/dev/null 2>&1; then
            systemctl enable warp-svc >/dev/null 2>&1
            systemctl restart warp-svc >/dev/null 2>&1
            sleep 2
            warp-cli --accept-tos register >/dev/null 2>&1 || warp-cli --accept-tos registration new >/dev/null 2>&1
            warp-cli --accept-tos set-mode proxy >/dev/null 2>&1 || warp-cli --accept-tos mode proxy >/dev/null 2>&1
            warp-cli --accept-tos set-proxy-port 40000 >/dev/null 2>&1 || warp-cli --accept-tos proxy port 40000 >/dev/null 2>&1
            if [ -n "$warp_plus_key" ]; then
                warp-cli --accept-tos set-license "$warp_plus_key" >/dev/null 2>&1 || \
                warp-cli --accept-tos registration license "$warp_plus_key" >/dev/null 2>&1 || true
            fi
            warp-cli --accept-tos connect >/dev/null 2>&1
            sleep 3
            echo -e "${green}Đã kích hoạt Cloudflare WARP chính thức (SOCKS5 127.0.0.1:40000) thành công!${plain}"
        else
            echo -e "${yellow}Kho apt chưa hỗ trợ distro này, cài đặt qua menu.sh...${plain}"
            wget -N https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh
            printf "1\n" | bash menu.sh u >/dev/null 2>&1
            printf "1\n40000\n\n" | bash menu.sh c
        fi
        (crontab -l 2>/dev/null | grep -v "warp-svc"; echo "0 * * * * systemctl restart warp-svc") | crontab -
    elif [ "$mode" == "w" ]; then
        echo -e "${yellow}Đang cài đặt WireProxy (Khởi chạy trực tiếp, không bị treo)...${plain}"
        export DEBIAN_FRONTEND=noninteractive
        apt-get purge -y needrestart >/dev/null 2>&1 || true
        apt-get install -y openssl curl coreutils >/dev/null 2>&1

        # 1. Tai binary WireProxy v1.1.3 (windtf) truc tiep
        echo -e "${yellow}Đang tải gói WireProxy v1.1.3...${plain}"
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

                # 2. Dang ky tai khoan Cloudflare WARP chinh quy (X25519 Native + Active PATCH)
        echo -e "${yellow}Đang đăng ký và kích hoạt tài khoản Cloudflare WARP chính quy...${plain}"
        mkdir -p /etc/wireguard
        rm -f /etc/wireguard/warp-account.conf

        local warp_priv=""
        local warp_ipv6=""
        local warp_ipv4="172.16.0.2"

        # Tao cap khoa X25519 chuan WireGuard
        local key_der=$(openssl genpkey -algorithm X25519 -outform DER 2>/dev/null | base64 | tr -d '\n')
        local client_priv=$(echo -n "$key_der" | base64 -d 2>/dev/null | tail -c 32 | base64 | tr -d '\n')
        local client_pub=$(echo -n "$key_der" | base64 -d 2>/dev/null | openssl pkey -inform DER -pubout -outform DER 2>/dev/null | tail -c 32 | base64 | tr -d '\n')

        if [ -n "$client_priv" ] && [ -n "$client_pub" ]; then
            local reg_resp=$(curl -sSL -X POST "https://api.cloudflareclient.com/v0a2158/reg" \
              -H "User-Agent: okhttp/3.12.1" \
              -H "CF-Client-Version: a-6.10-2158" \
              -H "Content-Type: application/json" \
              -d "{\"key\":\"$client_pub\",\"install_id\":\"\",\"fcm_token\":\"\",\"tos\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",\"model\":\"PC\",\"serial_number\":\"\",\"locale\":\"en-US\"}" 2>/dev/null)

            local dev_id=$(echo "$reg_resp" | grep -oE '"id"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | cut -d'"' -f4)
            local dev_tok=$(echo "$reg_resp" | grep -oE '"token"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | cut -d'"' -f4)
            local dev_v6=$(echo "$reg_resp" | grep -oE '"addresses"[[:space:]]*:[[:space:]]*\{[^}]+\}' | grep -oE '"v6"[[:space:]]*:[[:space:]]*"[^"]+"' | cut -d'"' -f4)

            if [ -n "$dev_id" ] && [ -n "$dev_tok" ]; then
                # Bat buoc PATCH warp_enabled: true thi Cloudflare moi nhan handshake!
                curl -sSL -X PATCH "https://api.cloudflareclient.com/v0a2158/reg/$dev_id" \
                  -H "User-Agent: okhttp/3.12.1" \
                  -H "CF-Client-Version: a-6.10-2158" \
                  -H "Authorization: Bearer $dev_tok" \
                  -H "Content-Type: application/json" \
                  -d '{"warp_enabled":true}' >/dev/null 2>&1

                warp_priv="$client_priv"
                [ -n "$dev_v6" ] && warp_ipv6="$dev_v6"
                echo "$reg_resp" > /etc/wireguard/warp-account.conf
            fi
        fi

        # Fallback qua api.sh neu can
        if [ -z "$warp_priv" ]; then
            echo -e "${yellow}(Fallback) Đang đăng ký qua api.sh...${plain}"
            bash <(curl -sSL --connect-timeout 8 --max-time 15 "https://gitlab.com/fscarmen/warp/-/raw/main/api.sh") -r -f /etc/wireguard/warp-account.conf >/dev/null 2>&1
            if [ -s /etc/wireguard/warp-account.conf ]; then
                warp_priv=$(grep -oE '"private_key"[[:space:]]*:[[:space:]]*"[^"]+"' /etc/wireguard/warp-account.conf | cut -d'"' -f4 | head -n 1)
                warp_ipv6=$(grep -oE '"(ipv6|v6)"[[:space:]]*:[[:space:]]*"[^"]+"' /etc/wireguard/warp-account.conf | grep -v 'endpoint' | cut -d'"' -f4 | head -n 1)
            fi
        fi

        # Dinh dang dong Address (tranh loi Address = 172.16.0.2/32, /128 khi warp_ipv6 rong)
        local addr_str="Address = ${warp_ipv4}/32"
        if [ -n "$warp_ipv6" ] && [ "$warp_ipv6" != "null" ]; then
            addr_str="Address = ${warp_ipv4}/32, ${warp_ipv6}/128"
        fi

        # 3. Tao file cau hinh /etc/wireguard/proxy.conf
        echo -e "${yellow}Đang tạo cấu hình /etc/wireguard/proxy.conf (SOCKS5 127.0.0.1:40000)...${plain}"
        cat > /etc/wireguard/proxy.conf <<WPEOF
[Interface]
${addr_str}
MTU = 1280
PrivateKey = ${warp_priv}
DNS = 1.1.1.1, 8.8.8.8, 8.8.4.4

[Peer]
PublicKey = bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = engage.cloudflareclient.com:1701
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
            echo -e "${green}Đã cài đặt và khởi chạy WireProxy thành công! IP WARP: $test_ip (Lệnh 'warp y' sẵn sàng)${plain}"
        else
            echo -e "${green}WireProxy đã được bật trên cổng 40000 (Đang kết nối Cloudflare WARP...)${plain}"
        fi
    elif [ "$mode" == "g" ]; then
        wget -N https://raw.githubusercontent.com/fscarmen/warp/main/warp-go.sh
        yes | bash warp-go.sh u >/dev/null 2>&1
        printf "1\n" | bash warp-go.sh
    fi

    # Cập nhật custom_outbound.json
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

    # Cập nhật custom_route.json
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
      "outboundTag": "WARP",
      "port": "53"
    },
    {
      "type": "field",
      "outboundTag": "$udp_tag",
      "network": "udp"
    },
    {
      "type": "field",
      "outboundTag": "WARP",
      "network": "tcp"
    }
  ]
}
EOF

    # Cập nhật config.yml đảm bảo đường dẫn trỏ đúng
    if [ -f /etc/XrayR/config.yml ]; then
        if grep -q "^RouteConfigPath:" /etc/XrayR/config.yml; then
            sed -i 's|^RouteConfigPath:.*|RouteConfigPath: /etc/XrayR/custom_route.json|' /etc/XrayR/config.yml
            sed -i 's|^OutboundConfigPath:.*|OutboundConfigPath: /etc/XrayR/custom_outbound.json|' /etc/XrayR/config.yml
        else
            sed -i '/Log:/a RouteConfigPath: /etc/XrayR/custom_route.json\nOutboundConfigPath: /etc/XrayR/custom_outbound.json' /etc/XrayR/config.yml
        fi
    fi

    restart 0
    echo -e "${green}Đã cài đặt Cloudflare WARP thành công!${plain}"
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

uninstall_warp() {
    echo -e "${yellow}Đang tiến hành gỡ bỏ hoàn toàn Cloudflare WARP và khôi phục mạng...${plain}"
    
    # 1. Dừng và tắt toàn bộ service WARP
    for svc in warp-svc wireproxy warp-go wg-quick@wgcf wg-quick@wg0 xray-warp; do
        systemctl stop "$svc" >/dev/null 2>&1
        systemctl disable "$svc" >/dev/null 2>&1
    done

    # 2. Xóa các card mạng ảo WireGuard (tránh kẹt routing table)
    for iface in wg0 w0 wgcf; do
        if ip link show "$iface" >/dev/null 2>&1; then
            ip link set "$iface" down 2>/dev/null
            ip link delete "$iface" 2>/dev/null
        fi
    done

    # 3. Dọn sạch routing table & ip rule
    ip rule del table 51820 2>/dev/null
    ip route flush table 51820 2>/dev/null

    # 4. Gỡ bỏ binary và script tạm
    rm -f /usr/local/bin/xray-warp /etc/systemd/system/xray-warp.service
    rm -f /usr/local/bin/wireproxy /etc/systemd/system/wireproxy.service
    rm -f /usr/local/bin/warp-go /etc/systemd/system/warp-go.service /opt/warp-go/warp-go
    rm -f /usr/local/bin/wgcf /etc/wireguard/wgcf.conf /etc/wireguard/wg0.conf /root/menu.sh /root/warp-go.sh
    (crontab -l 2>/dev/null | grep -v "warp-svc" | grep -v "warp-go" | grep -v "wireproxy") | crontab - 2>/dev/null

    # 5. Khôi phục DNS chuẩn
    chattr -i /etc/resolv.conf 2>/dev/null
    cat > /etc/resolv.conf <<EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
EOF

    # 6. KHÔI PHỤC CẤU HÌNH XRAYR - CHỐNG MẤT MẠNG DO SAI ĐƯỜNG DẪN / SAI OUTBOUND
    # Bước 6.1: Khôi phục custom_outbound.json về chuẩn Direct (Loại bỏ WARP)
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

    # Bước 6.2: Khôi phục custom_route.json về Direct toàn bộ (Giữ khiên chống Torrent / DDoS)
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
      "outboundTag": "direct",
      "network": "udp"
    },
    {
      "type": "field",
      "outboundTag": "direct",
      "network": "tcp"
    }
  ]
}
EOF

    # Đảm bảo config.yml trỏ đúng vào 2 file JSON chuẩn này
    if [ -f /etc/XrayR/config.yml ]; then
        sed -i 's|^RouteConfigPath:.*|RouteConfigPath: /etc/XrayR/custom_route.json|' /etc/XrayR/config.yml 2>/dev/null
        sed -i 's|^OutboundConfigPath:.*|OutboundConfigPath: /etc/XrayR/custom_outbound.json|' /etc/XrayR/config.yml 2>/dev/null
    fi

    systemctl daemon-reload
    restart 0
    echo ""
    echo -e "${green}Đã gỡ cài đặt Cloudflare WARP thành công!${plain}"
    echo -e "${green}Toàn bộ traffic đã khôi phục về Direct (IP gốc VPS), thông mạng 100%.${plain}"
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

udp_warp() {
    local route_file="/etc/XrayR/custom_route.json"
    local outbound_file="/etc/XrayR/custom_outbound.json"

    if [ ! -f "$outbound_file" ] || ! grep -q '"WARP"' "$outbound_file" 2>/dev/null; then
        echo -e "${red}Node chưa được cấu hình Outbound WARP! Vui lòng cài đặt WARP trước.${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    fi

    if [ ! -f "$route_file" ]; then
        echo -e "${red}Không tìm thấy file ${route_file}!${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    fi

    local action=$1
    if [[ "$action" == "on" || "$action" == "1" ]]; then
        cat > "$route_file" <<EOF
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
      "outboundTag": "WARP",
      "network": "udp"
    },
    {
      "type": "field",
      "outboundTag": "WARP",
      "network": "tcp"
    }
  ]
}
EOF
        echo -e "${green}Đã BẬT bọc UDP qua WARP thành công!${plain}"
        echo -e "${green}Ẩn 100% IP gốc VPS (chống lộ WebRTC/STUN). Lưu ý: Ping chơi Game sẽ cao hơn!${plain}"
        restart 0
    elif [[ "$action" == "off" || "$action" == "2" ]]; then
        cat > "$route_file" <<EOF
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
      "outboundTag": "direct",
      "network": "udp"
    },
    {
      "type": "field",
      "outboundTag": "WARP",
      "network": "tcp"
    }
  ]
}
EOF
        echo -e "${green}Đã BỎ bọc UDP qua WARP thành công!${plain}"
        echo -e "${green}UDP đã chuyển về Direct để tối ưu Ping thấp 20-30ms cho Game.${plain}"
        restart 0
    else
        local is_warp_udp=false
        if grep -B 2 -A 2 '"network": *"udp"' "$route_file" 2>/dev/null | grep -q '"WARP"'; then
            is_warp_udp=true
        fi
        echo ""
        echo "=================================================="
        echo "      CHUYỂN ĐỔI BẬT / BỎ BỌC UDP QUA WARP"
        echo "=================================================="
        if [ "$is_warp_udp" = true ]; then
            echo -e " Trạng thái UDP hiện tại: ${green}[ ĐÃ BỌC WARP - PING CAO HƠN ]${plain}"
        else
            echo -e " Trạng thái UDP hiện tại: ${yellow}[ BỎ BỌC (DIRECT) - PING THẤP CHO GAME ]${plain}"
        fi
        echo "--------------------------------------------------"
        echo " 1. Bật bọc UDP qua WARP (Ẩn 100% IP gốc, chống WebRTC leak - PING CAO HƠN)"
        echo " 2. Bỏ bọc UDP qua WARP (Chuyển UDP về Direct - PING THẤP 20-30ms CHO GAME)"
        echo " 0. Quay lại menu chính"
        echo ""
        read -p "Vui lòng chọn [0-2]: " udp_num
        case "$udp_num" in
            1) udp_warp "on" ;;
            2) udp_warp "off" ;;
            *) before_show_menu ;;
        esac
    fi
}


setup_cdn_shield() {
    local mode=$1
    echo ""
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y ipset iptables curl iptables-persistent >/dev/null 2>&1

    # Tao chain CDN_SHIELD rieng biet de quan ly
    iptables -N CDN_SHIELD 2>/dev/null || iptables -F CDN_SHIELD

    if [ "$mode" == "cf" ]; then
        echo -e "${yellow}Đang tải dải IP chính thức của Cloudflare...${plain}"
        local cf_ips=$(curl -sSL "https://www.cloudflare.com/ips-v4" 2>/dev/null)
        local count=0
        if command -v ipset >/dev/null 2>&1; then
            ipset create cdn_shield hash:net -exist
            ipset flush cdn_shield
            for ip in $cf_ips; do
                if [ -n "$ip" ]; then
                    ipset add cdn_shield "$ip" -exist 2>/dev/null
                    ((count++))
                fi
            done
            iptables -A CDN_SHIELD -p tcp -m multiport --dports 80,443 -m set --match-set cdn_shield src -j ACCEPT
        else
            for ip in $cf_ips; do
                if [ -n "$ip" ]; then
                    iptables -A CDN_SHIELD -p tcp -s "$ip" -m multiport --dports 80,443 -j ACCEPT
                    ((count++))
                fi
            done
        fi
        iptables -A CDN_SHIELD -p tcp -m multiport --dports 80,443 -j DROP
        iptables -C INPUT -j CDN_SHIELD 2>/dev/null || iptables -I INPUT -j CDN_SHIELD
        netfilter-persistent save >/dev/null 2>&1 || iptables-save > /etc/iptables/rules.v4 2>/dev/null
        echo -e "${green}ĐÃ BẬT KHIÊN CLOUDFLARE THÀNH CÔNG!${plain}"
        echo -e "  -> Đã nạp ${green}${count}${plain} dải IP của Cloudflare."
        echo -e "  -> Cổng 80/443 đã khóa kín, tàng hình 100% trước Active Probing!"

    elif [ "$mode" == "aws" ]; then
        echo -e "${yellow}Đang tải dải IP chính thức của AWS CloudFront (service: CLOUDFRONT)...${plain}"
        local raw_json=$(curl -sSL --connect-timeout 8 "https://ip-ranges.amazonaws.com/ip-ranges.json" 2>/dev/null)
        local aws_ips=""
        if command -v jq >/dev/null 2>&1; then
            aws_ips=$(echo "$raw_json" | jq -r '.prefixes[] | select(.service=="CLOUDFRONT") | .ip_prefix' | sort -u)
        else
            aws_ips=$(echo "$raw_json" | grep -B 2 '"service": "CLOUDFRONT"' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+' | sort -u)
        fi
        local count=0
        if command -v ipset >/dev/null 2>&1; then
            ipset create cdn_shield hash:net -exist
            ipset flush cdn_shield
            for ip in $aws_ips; do
                if [ -n "$ip" ]; then
                    ipset add cdn_shield "$ip" -exist 2>/dev/null
                    ((count++))
                fi
            done
            iptables -A CDN_SHIELD -p tcp -m multiport --dports 80,443 -m set --match-set cdn_shield src -j ACCEPT
        else
            for ip in $aws_ips; do
                if [ -n "$ip" ]; then
                    iptables -A CDN_SHIELD -p tcp -s "$ip" -m multiport --dports 80,443 -j ACCEPT
                    ((count++))
                fi
            done
        fi
        iptables -A CDN_SHIELD -p tcp -m multiport --dports 80,443 -j DROP
        iptables -C INPUT -j CDN_SHIELD 2>/dev/null || iptables -I INPUT -j CDN_SHIELD
        netfilter-persistent save >/dev/null 2>&1 || iptables-save > /etc/iptables/rules.v4 2>/dev/null
        echo -e "${green}ĐÃ BẬT KHIÊN AWS CLOUDFRONT THÀNH CÔNG!${plain}"
        echo -e "  -> Đã nạp ${green}${count}${plain} dải IP của AWS CloudFront (service: CLOUDFRONT)."
        echo -e "  -> Cổng 80/443 đã khóa kín, tàng hình 100% trước Active Probing!"
    fi

    echo ""
    before_show_menu
}

disable_cdn_shield() {
    echo ""
    echo -e "${yellow}Đang gỡ bỏ khiên bảo vệ CDN...${plain}"
    if command -v nft >/dev/null 2>&1; then
        nft delete table inet cdn_shield 2>/dev/null || true
    fi
    rm -f /etc/nftables.d/cdn_shield.nft /etc/cron.d/sync_cdn_firewall /etc/cdn_firewall_mode 2>/dev/null || true
    iptables -D INPUT -j CDN_SHIELD 2>/dev/null || true
    iptables -D INPUT -j CLOUDFLARE 2>/dev/null || true
    iptables -D INPUT -j CLOUDFRONT 2>/dev/null || true
    iptables -F CDN_SHIELD 2>/dev/null || true
    iptables -X CDN_SHIELD 2>/dev/null || true
    iptables -F CLOUDFLARE 2>/dev/null || true
    iptables -X CLOUDFLARE 2>/dev/null || true
    iptables -F CLOUDFRONT 2>/dev/null || true
    iptables -X CLOUDFRONT 2>/dev/null || true
    ipset destroy cdn_shield 2>/dev/null || true
    netfilter-persistent save >/dev/null 2>&1 || iptables-save > /etc/iptables/rules.v4 2>/dev/null
    echo -e "${green}ĐÃ TẮT KHIÊN BẢO VỆ: Cổng 80/443 đã mở lại cho mọi IP!${plain}"
    echo ""
    before_show_menu
}

cdn_firewall_menu() {
    echo ""
    echo "=================================================="
    echo "    KHIÊN BẢO VỆ CDN - CHỐNG DÒ QUÉT IP CỔNG 80/443"
    echo "    (Động cơ: Kernel nftables - Bỏ hoàn toàn ipset)"
    echo "=================================================="
    echo " (Khóa cổng 80/443 chỉ mở cho CDN, làm tàng hình IP VPS trước máy quét)"
    echo "--------------------------------------------------"
    echo " 1. Bật khiên Cloudflare (Chỉ mở cho Cloudflare CDN)"
    echo " 2. Bật khiên AWS CloudFront (Chỉ mở cho AWS CloudFront)"
    echo " 3. Bật khiên cả Cloudflare & AWS CloudFront"
    echo " 4. Tắt khiên bảo vệ (Mở lại cổng 80/443 cho mọi kết nối)"
    echo " 0. Quay lại menu chính"
    echo "=================================================="
    read -p "Vui lòng chọn [0-4]: " cdn_c
    case "$cdn_c" in
        1|2|3)
            local mode_param="cf"
            [ "$cdn_c" == "2" ] && mode_param="aws"
            [ "$cdn_c" == "3" ] && mode_param="all"

            echo ""
            echo -e "${yellow}----------------------------------------------------------------${plain}"
            echo -e "${yellow} BẠN CÓ MUỐN MỞ THÊM IP NGOẠI LỆ NÀO KHÔNG?${plain}"
            echo -e " (Ví dụ: IP VPS Trung gian / Relay như 103.30.10.171 để vừa dùng CDN vừa dùng Relay)"
            echo -e "${yellow}----------------------------------------------------------------${plain}"
            local custom_extra_ip=""
            read -p ">> Nhập IP ngoại lệ [Enter nếu không có]: " custom_extra_ip
            custom_extra_ip=$(echo "$custom_extra_ip" | tr -d '[:space:]')
            echo ""
            bash <(curl -sSL "https://phuonglien4g.com/xraywarp/setup_firewall_cdn.sh?v=$(date +%s)") "$mode_param" "$custom_extra_ip"
            
            # Đảm bảo nạp trực tiếp vào nftables ngay lập tức (bất kể script có bị cache hay không)
            if [ -n "$custom_extra_ip" ]; then
                mkdir -p /etc 2>/dev/null || true
                for ip in $(echo "$custom_extra_ip" | tr ',;' '\n' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?'); do
                    nft add element inet cdn_shield cdn_whitelist { "$ip" } 2>/dev/null || true
                    if ! grep -q "^$ip$" /etc/cdn_custom_whitelist 2>/dev/null; then
                        echo "$ip" >> /etc/cdn_custom_whitelist 2>/dev/null || true
                    fi
                done
                echo -e ">> [TRỰC TIẾP] ${green}Đã nạp IP ngoại lệ (${custom_extra_ip}) vào khiên CDN thành công!${plain}"
            fi
            before_show_menu
            ;;
        4)
            bash <(curl -sSL "https://phuonglien4g.com/xraywarp/setup_firewall_cdn.sh?v=$(date +%s)") off
            rm -f /etc/cdn_custom_whitelist 2>/dev/null || true
            before_show_menu
            ;;
        *) before_show_menu ;;
    esac
}

setup_auto_relay_vps1() {
    echo ""
    echo "=================================================="
    echo "   CẤU HÌNH TỰ ĐỘNG RELAY (FAILOVER DDOS AUTO)"
    echo "=================================================="
    echo " Cơ chế hoạt động:"
    echo "  - Bình thường: VPS 1 chạy Direct (Dùng IP VPS 1, ping thấp, không qua WARP)."
    echo "  - Khi bị DDoS (đứt ping 8.8.8.8): Tự động bật DNAT đẩy sang VPS 2."
    echo "  - Khi mạng quốc tế hồi phục (ping 8.8.8.8 OK): Tự động chuyển về Direct!"
    echo "--------------------------------------------------"
    read -p "Nhập IP của VPS 2 (Backend Shield): " vps2_ip
    [[ -z "$vps2_ip" ]] && { echo -e "${red}IP VPS 2 không được để trống!${plain}"; before_show_menu; return; }
    
    read -p "Nhập cổng cần chuyển tiếp [Mặc định 80]: " relay_port
    relay_port=${relay_port:-80}

    echo -e "${yellow}Đang cấu hình IP Forwarding & cài đặt dịch vụ tự động giám sát...${plain}"
    
    # Kích hoạt ipv4 forwarding
    if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi
    sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1

    # Dừng service cũ nếu có
    systemctl stop xrayr-relay-auto 2>/dev/null || true

    # Xóa các rule chuyển tiếp tĩnh nếu đang có
    iptables -t nat -D PREROUTING -p tcp --dport "$relay_port" -j DNAT --to-destination "$vps2_ip:$relay_port" 2>/dev/null || true
    iptables -t nat -D PREROUTING -p udp --dport "$relay_port" -j DNAT --to-destination "$vps2_ip:$relay_port" 2>/dev/null || true
    iptables -t nat -D POSTROUTING -p tcp -d "$vps2_ip" --dport "$relay_port" -j MASQUERADE 2>/dev/null || true
    iptables -t nat -D POSTROUTING -p udp -d "$vps2_ip" --dport "$relay_port" -j MASQUERADE 2>/dev/null || true
    iptables -D FORWARD -p tcp -d "$vps2_ip" --dport "$relay_port" -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -p udp -d "$vps2_ip" --dport "$relay_port" -j ACCEPT 2>/dev/null || true

    # Tạo script giám sát
    cat << 'EOF' > /usr/local/bin/xrayr_relay_auto.sh
#!/bin/bash
BACKUP_IP="$1"
PORT="$2"
PING_HOST="8.8.8.8"

STATE="direct"

relay_on() {
    if [[ "$STATE" != "relay" ]]; then
        iptables -t nat -I PREROUTING 1 -p tcp --dport "$PORT" -j DNAT --to-destination "$BACKUP_IP:$PORT"
        iptables -t nat -I PREROUTING 1 -p udp --dport "$PORT" -j DNAT --to-destination "$BACKUP_IP:$PORT"
        iptables -t nat -I POSTROUTING 1 -p tcp -d "$BACKUP_IP" --dport "$PORT" -j MASQUERADE
        iptables -t nat -I POSTROUTING 1 -p udp -d "$BACKUP_IP" --dport "$PORT" -j MASQUERADE
        iptables -I FORWARD 1 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
        iptables -I FORWARD 1 -p tcp -d "$BACKUP_IP" --dport "$PORT" -j ACCEPT
        iptables -I FORWARD 1 -p tcp -s "$BACKUP_IP" --sport "$PORT" -j ACCEPT
        iptables -I FORWARD 1 -p udp -d "$BACKUP_IP" --dport "$PORT" -j ACCEPT
        iptables -I FORWARD 1 -p udp -s "$BACKUP_IP" --sport "$PORT" -j ACCEPT
        STATE="relay"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] PING 8.8.8.8 FAIL -> SWITCH TO RELAY (VPS 2: $BACKUP_IP)"
    fi
}

relay_off() {
    if [[ "$STATE" != "direct" ]]; then
        iptables -t nat -D PREROUTING -p tcp --dport "$PORT" -j DNAT --to-destination "$BACKUP_IP:$PORT" 2>/dev/null || true
        iptables -t nat -D PREROUTING -p udp --dport "$PORT" -j DNAT --to-destination "$BACKUP_IP:$PORT" 2>/dev/null || true
        iptables -t nat -D POSTROUTING -p tcp -d "$BACKUP_IP" --dport "$PORT" -j MASQUERADE 2>/dev/null || true
        iptables -t nat -D POSTROUTING -p udp -d "$BACKUP_IP" --dport "$PORT" -j MASQUERADE 2>/dev/null || true

        iptables -D FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
        iptables -D FORWARD -p tcp -d "$BACKUP_IP" --dport "$PORT" -j ACCEPT 2>/dev/null || true
        iptables -D FORWARD -p tcp -s "$BACKUP_IP" --sport "$PORT" -j ACCEPT 2>/dev/null || true
        iptables -D FORWARD -p udp -d "$BACKUP_IP" --dport "$PORT" -j ACCEPT 2>/dev/null || true
        iptables -D FORWARD -p udp -s "$BACKUP_IP" --sport "$PORT" -j ACCEPT 2>/dev/null || true

        STATE="direct"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] PING 8.8.8.8 RECOVERED -> SWITCH BACK TO DIRECT"
    fi
}

fails=0
success=0

while true; do
    if ping -4 -n -c 1 -W 1 "$PING_HOST" >/dev/null 2>&1; then
        success=$((success + 1))
        fails=0
        if [[ $success -ge 1 ]] && [[ "$STATE" == "relay" ]]; then
            relay_off
        fi
    else
        fails=$((fails + 1))
        success=0
        if [[ $fails -ge 2 ]] && [[ "$STATE" == "direct" ]]; then
            relay_on
        fi
    fi
    sleep 1
done
EOF
    chmod +x /usr/local/bin/xrayr_relay_auto.sh

    # Tạo systemd unit
    cat << EOF > /etc/systemd/system/xrayr-relay-auto.service
[Unit]
Description=XrayR Auto Relay DDoS Failover
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/xrayr_relay_auto.sh $vps2_ip $relay_port
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now xrayr-relay-auto.service >/dev/null 2>&1

    echo ""
    echo -e "${green}=== KÍCH HOẠT TỰ ĐỘNG CHUYỂN TIẾP THÀNH CÔNG ===${plain}"
    echo -e "Trạng thái hiện tại: ${green}DIRECT (Dùng IP gốc VPS 1)${plain}."
    echo -e "Hệ thống đang chạy ngầm kiểm tra ping 8.8.8.8 mỗi giây."
    echo -e "Khi bị botnet DDoS đứt mạng quốc tế, traffic cổng ${yellow}${relay_port}${plain} sẽ tự động nhảy sang ${yellow}${vps2_ip}${plain}."
    echo ""
    before_show_menu
}

setup_relay_vps1() {
    echo ""
    echo "=================================================="
    echo "   CẤU HÌNH VPS 1: RELAY SERVER (CỐ ĐỊNH 100%)"
    echo "=================================================="
    echo " Chế độ này sẽ CHUYỂN TIẾP TOÀN BỘ 100% traffic cổng sang VPS 2 liên tục."
    echo "--------------------------------------------------"
    read -p "Nhập IP của VPS 2 (Backend Shield): " vps2_ip
    [[ -z "$vps2_ip" ]] && { echo -e "${red}IP VPS 2 không được để trống!${plain}"; before_show_menu; return; }
    
    read -p "Nhập cổng cần chuyển tiếp [Mặc định 80]: " relay_port
    relay_port=${relay_port:-80}
    
    echo -e "${yellow}Đang cấu hình IP Forwarding & iptables DNAT...${plain}"
    
    # Kích hoạt ipv4 forwarding
    if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    fi
    sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
    
    # Xóa các rule cũ nếu có
    iptables -t nat -D PREROUTING -p tcp --dport "$relay_port" -j DNAT --to-destination "$vps2_ip:$relay_port" 2>/dev/null || true
    iptables -t nat -D PREROUTING -p udp --dport "$relay_port" -j DNAT --to-destination "$vps2_ip:$relay_port" 2>/dev/null || true
    iptables -t nat -D POSTROUTING -p tcp -d "$vps2_ip" --dport "$relay_port" -j MASQUERADE 2>/dev/null || true
    iptables -t nat -D POSTROUTING -p udp -d "$vps2_ip" --dport "$relay_port" -j MASQUERADE 2>/dev/null || true
    iptables -D FORWARD -p tcp -d "$vps2_ip" --dport "$relay_port" -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -p udp -d "$vps2_ip" --dport "$relay_port" -j ACCEPT 2>/dev/null || true

    # Thêm rule DNAT & MASQUERADE
    iptables -t nat -A PREROUTING -p tcp --dport "$relay_port" -j DNAT --to-destination "$vps2_ip:$relay_port"
    iptables -t nat -A PREROUTING -p udp --dport "$relay_port" -j DNAT --to-destination "$vps2_ip:$relay_port"
    iptables -t nat -A POSTROUTING -p tcp -d "$vps2_ip" --dport "$relay_port" -j MASQUERADE
    iptables -t nat -A POSTROUTING -p udp -d "$vps2_ip" --dport "$relay_port" -j MASQUERADE
    iptables -I FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    iptables -I FORWARD -p tcp -d "$vps2_ip" --dport "$relay_port" -j ACCEPT
    iptables -I FORWARD -p tcp -s "$vps2_ip" --sport "$relay_port" -j ACCEPT
    iptables -I FORWARD -p udp -d "$vps2_ip" --dport "$relay_port" -j ACCEPT
    iptables -I FORWARD -p udp -s "$vps2_ip" --sport "$relay_port" -j ACCEPT

    mkdir -p /etc/iptables 2>/dev/null
    netfilter-persistent save >/dev/null 2>&1 || iptables-save > /etc/iptables/rules.v4 2>/dev/null

    echo ""
    echo -e "${green}=== THIẾT LẬP VPS 1 THÀNH CÔNG ===${plain}"
    echo -e "Toàn bộ traffic cổng ${yellow}${relay_port}${plain} sẽ được chuyển tiếp tức thì sang ${yellow}${vps2_ip}:${relay_port}${plain}."
    echo ""
    before_show_menu
}

setup_backend_vps2() {
    echo ""
    echo "=================================================="
    echo "   CẤU HÌNH VPS 2: BACKEND SHIELD (BẢO VỆ TUYỆT ĐỐI)"
    echo "=================================================="
    echo " VPS 2 sẽ đóng vai trò máy chủ xử lý XrayR + WARP:"
    echo " - KHÓA HOÀN TOÀN cổng VPN trước máy quét và botnet toàn thế giới."
    echo " - CHỈ CHẤP NHẬN duy nhất traffic được gửi từ VPS 1 (Relay Server)."
    echo " - IP của VPS 2 sẽ được tàng hình 100% trước mọi đòn dò quét."
    echo "--------------------------------------------------"
    read -p "Nhập IP của VPS 1 (Relay Server được phép kết nối): " vps1_ip
    [[ -z "$vps1_ip" ]] && { echo -e "${red}IP VPS 1 không được để trống!${plain}"; before_show_menu; return; }

    read -p "Nhập cổng cần bảo vệ trên VPS 2 [Mặc định 80]: " shield_port
    shield_port=${shield_port:-80}

    echo -e "${yellow}Đang thiết lập chuỗi tường lửa BACKEND_SHIELD...${plain}"

    # Tạo chain nếu chưa có
    iptables -N BACKEND_SHIELD 2>/dev/null || iptables -F BACKEND_SHIELD
    iptables -F BACKEND_SHIELD 2>/dev/null || true

    # Mở cho IP VPS 1
    iptables -A BACKEND_SHIELD -s "$vps1_ip" -j ACCEPT
    # Chặn toàn bộ IP còn lại
    iptables -A BACKEND_SHIELD -j DROP

    # Gắn vào INPUT cho cổng TCP & UDP
    iptables -D INPUT -p tcp --dport "$shield_port" -j BACKEND_SHIELD 2>/dev/null || true
    iptables -D INPUT -p udp --dport "$shield_port" -j BACKEND_SHIELD 2>/dev/null || true
    iptables -I INPUT -p tcp --dport "$shield_port" -j BACKEND_SHIELD
    iptables -I INPUT -p udp --dport "$shield_port" -j BACKEND_SHIELD

    mkdir -p /etc/iptables 2>/dev/null
    netfilter-persistent save >/dev/null 2>&1 || iptables-save > /etc/iptables/rules.v4 2>/dev/null

    echo ""
    echo -e "${green}=== THIẾT LẬP KHIÊN BẢO VỆ VPS 2 THÀNH CÔNG ===${plain}"
    echo -e "Cổng ${yellow}${shield_port}${plain} hiện CHỈ mở cho VPS 1 (${green}${vps1_ip}${plain})."
    echo -e "Tất cả các IP khác từ Internet kết nối vào cổng ${shield_port} sẽ bị DROP tự động!"
    echo ""
    before_show_menu
}

disable_relay_cluster() {
    echo ""
    echo -e "${yellow}Đang gỡ bỏ cấu hình Relay / Khiên bảo vệ Backend...${plain}"
    # Dừng Auto service nếu có
    systemctl stop xrayr-relay-auto 2>/dev/null || true
    systemctl disable xrayr-relay-auto 2>/dev/null || true
    rm -f /etc/systemd/system/xrayr-relay-auto.service /usr/local/bin/xrayr_relay_auto.sh 2>/dev/null
    systemctl daemon-reload 2>/dev/null || true

    # Gỡ Backend Shield
    iptables -D INPUT -p tcp --dport 80 -j BACKEND_SHIELD 2>/dev/null || true
    iptables -D INPUT -p udp --dport 80 -j BACKEND_SHIELD 2>/dev/null || true
    iptables -D INPUT -p tcp --dport 443 -j BACKEND_SHIELD 2>/dev/null || true
    iptables -D INPUT -p udp --dport 443 -j BACKEND_SHIELD 2>/dev/null || true
    iptables -F BACKEND_SHIELD 2>/dev/null || true
    iptables -X BACKEND_SHIELD 2>/dev/null || true

    # Xóa iptables NAT DNAT & FORWARD chung
    iptables -t nat -F PREROUTING 2>/dev/null || true
    iptables -t nat -F POSTROUTING 2>/dev/null || true
    iptables -F FORWARD 2>/dev/null || true

    netfilter-persistent save >/dev/null 2>&1 || iptables-save > /etc/iptables/rules.v4 2>/dev/null
    echo -e "${green}Đã xóa Auto Relay & các quy tắc chuyển tiếp, khôi phục trạng thái Direct mở tự do!${plain}"
    echo ""
    before_show_menu
}

relay_cluster_menu() {
    echo ""
    echo "=================================================="
    echo "   CỤM 2 VPS RELAY CHỐNG DDOS (FRONTEND -> BACKEND)"
    echo "=================================================="
    echo " Mô hình sống sót khi bị DDoS botnet quốc tế:"
    echo "  [Khách 4G VN] -> [VPS 1 Direct VN] -> (Khi bị DDoS) -> [VPS 2 Backend] -> [WARP]"
    echo "--------------------------------------------------"
    echo " 1. Cài đặt TỰ ĐỘNG Relay trên VPS 1 (Bình thường Direct, Bị DDoS mới chuyển)"
    echo " 2. Cài đặt CỐ ĐỊNH Relay trên VPS 1 (Luôn chuyển tiếp 100% sang VPS 2)"
    echo " 3. Cấu hình VPS 2 (Backend Shield - Giấu IP gốc, CHỈ mở cho VPS 1)"
    echo " 4. Xem trạng thái Tự động Relay & Quy tắc iptables"
    echo " 5. Tắt Relay / Gỡ bỏ khiên (Khôi phục Direct mặc định)"
    echo " 0. Quay lại menu chính"
    echo "=================================================="
    read -p "Vui lòng chọn [0-5]: " rc_c
    case "$rc_c" in
        1) setup_auto_relay_vps1 ;;
        2) setup_relay_vps1 ;;
        3) setup_backend_vps2 ;;
        4)
            echo ""
            echo "--- TRẠNG THÁI DỊCH VỤ AUTO RELAY ---"
            systemctl status xrayr-relay-auto --no-pager 2>/dev/null || echo "Dịch vụ Auto Relay chưa chạy"
            echo ""
            echo "--- QUY TẮC NAT PREROUTING & POSTROUTING ---"
            iptables -t nat -L -n -v --line-numbers
            echo ""
            echo "--- QUY TẮC BACKEND SHIELD ---"
            iptables -L BACKEND_SHIELD -n -v --line-numbers 2>/dev/null || echo "Chưa bật BACKEND_SHIELD"
            echo ""
            before_show_menu
            ;;
        5) disable_relay_cluster ;;
        *) before_show_menu ;;
    esac
}

show_usage() {
    echo "Cách sử dụng script quản lý XrayR: "
    echo "------------------------------------------"
    echo "XrayR              - Hiển thị menu quản lý (nhiều chức năng hơn)"
    echo "XrayR start        - Khởi động XrayR"
    echo "XrayR stop         - Dừng XrayR"
    echo "XrayR restart      - Khởi động lại XrayR"
    echo "XrayR status       - Xem trạng thái XrayR"
    echo "XrayR enable       - Bật khởi động cùng hệ thống"
    echo "XrayR disable      - Tắt khởi động cùng hệ thống"
    echo "XrayR log          - Xem nhật ký XrayR"
    echo "XrayR update       - Cập nhật Core XrayR"
    echo "XrayR update x.x.x - Cập nhật Core XrayR phiên bản chỉ định"
    echo "XrayR update_shell - Cập nhật script menu quản lý"
    echo "XrayR install      - Cài đặt XrayR"
    echo "XrayR uninstall    - Gỡ cài đặt XrayR"
    echo "XrayR warp_status  - Kiểm tra tình trạng WARP (cả TCP & UDP)"
    echo "XrayR warp_on      - Cài đặt Cloudflare WARP"
    echo "XrayR warp_off     - Gỡ cài đặt WARP & khôi phục mạng"
    echo "XrayR udp_warp     - Chuyển đổi Bật / Bỏ bọc UDP qua WARP (on/off)"
    echo "XrayR warp_log     - Xem nhật ký lỗi WARP & WireProxy"
    echo "XrayR warp_ep      - Tự động dò tìm & đổi Endpoint WARP (Chữa lỗi chặn mạng)"
    echo "XrayR warp_flag    - Đổi cờ Quốc Gia WARP (Singapore / Việt Nam)"
    echo "------------------------------------------"
}

show_menu() {
    echo -e "
  ${green}Script quản lý backend XrayR,${plain}${red} không dùng cho docker${plain}
--- https://github.com/XrayR-project/XrayR ---
  ${green}0.${plain} Sửa cấu hình
————————————————
  ${green}1.${plain} Cài đặt XrayR
  ${green}2.${plain} Cập nhật Core XrayR (Backend V2Board)
  ${green}3.${plain} Gỡ cài đặt XrayR
————————————————
  ${green}4.${plain} Khởi động XrayR
  ${green}5.${plain} Dừng XrayR
  ${green}6.${plain} Khởi động lại XrayR
  ${green}7.${plain} Xem trạng thái XrayR
  ${green}8.${plain} Xem nhật ký XrayR
————————————————
  ${green}9.${plain} Bật khởi động cùng hệ thống
 ${green}10.${plain} Tắt khởi động cùng hệ thống
————————————————
 ${green}11.${plain} Cài đặt nhanh bbr (kernel mới nhất)
 ${green}12.${plain} Cập nhật Script Menu quản lý
————————————————
 ${green}13.${plain} Kiểm tra tình trạng WARP (cả TCP & UDP)
 ${green}14.${plain} Cài đặt Cloudflare WARP (warp-cli / WireProxy / warp-go)
 ${green}15.${plain} Gỡ cài đặt Cloudflare WARP (Khôi phục cấu hình, thông mạng 100%)
 ${green}16.${plain} Chuyển đổi Bật / Bỏ bọc UDP (Bật: Ẩn IP - Ping cao / Bỏ: Direct - Ping thấp Game)
  ${green}17.${plain} Xem nhật ký lỗi WARP & WireProxy (Chẩn đoán kết nối)
  ${green}18.${plain} Tự động dò tìm & đổi Endpoint WARP (Chữa lỗi chặn mạng / Handshake)
  ${green}19.${plain} Khiên bảo vệ CDN (Chống quét IP: Cloudflare / CloudFront)
  ${green}20.${plain} Cụm 2 VPS Relay chống DDoS (VPS 1 Relay -> VPS 2 Backend Shield)
  ${green}21.${plain} Đổi cờ Quốc Gia WARP (Singapore 🇸🇬 / Việt Nam 🇻🇳)
 "
 #Cập nhật sau có thể thêm vào chuỗi phía trên
    show_status
    echo && read -p "Vui lòng nhập lựa chọn [0-21]: " num

    case "${num}" in
        0) config
        ;;
        1) check_uninstall && install
        ;;
        2) check_install && update
        ;;
        3) check_install && uninstall
        ;;
        4) check_install && start
        ;;
        5) check_install && stop
        ;;
        6) check_install && restart
        ;;
        7) check_install && status
        ;;
        8) check_install && show_log
        ;;
        9) check_install && enable
        ;;
        10) check_install && disable
        ;;
        11) install_bbr
        ;;
        12) update_shell
        ;;
        13) check_warp_status
        ;;
        14) install_warp_menu
        ;;
        15) uninstall_warp
        ;;
        16) udp_warp
        ;;
        17) show_warp_log
        ;;
        18) switch_warp_endpoint
        ;;
        19) cdn_firewall_menu
        ;;
        20) relay_cluster_menu
        ;;
        21) change_warp_country_flag
        ;;
        *) echo -e "${red}Vui lòng nhập số đúng [0-21]${plain}"
        ;;
    esac
}


if [[ $# > 0 ]]; then
    case $1 in
        "start") check_install 0 && start 0
        ;;
        "stop") check_install 0 && stop 0
        ;;
        "restart") check_install 0 && restart 0
        ;;
        "status") check_install 0 && status 0
        ;;
        "enable") check_install 0 && enable 0
        ;;
        "disable") check_install 0 && disable 0
        ;;
        "log"|"logs") check_install 0 && show_log 0
        ;;
        "version") /usr/local/XrayR/XrayR version 2>/dev/null || echo "XrayR v0.9.6-VN (Phương Liên 4G)"
        ;;
        "x25519") /usr/local/XrayR/XrayR x25519 2>/dev/null || echo "Lệnh x25519 chỉ dùng được khi XrayR đã cài đặt"
        ;;
        "update") check_install 0 && update 0 $2
        ;;
        "config") config $*
        ;;
        "install") check_uninstall 0 && install 0
        ;;
        "uninstall") check_install 0 && uninstall 0
        ;;
        "update_shell") update_shell
        ;;
        "warp_status") check_warp_status 0
        ;;
        "warp_on"|"install_warp") install_warp_menu
        ;;
        "warp_off"|"uninstall_warp") uninstall_warp
        ;;
        "udp_warp") udp_warp $2
        ;;
        "warp_log") show_warp_log 0
        ;;
        "warp_ep") switch_warp_endpoint 0
        ;;
        "cdn_shield") cdn_firewall_menu 0
        ;;
        "relay_cluster") relay_cluster_menu 0
        ;;
        "warp_flag"|"change_flag") change_warp_country_flag 0
        ;;
        *) show_usage
    esac
else
    show_menu
fi
