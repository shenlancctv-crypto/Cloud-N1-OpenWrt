#!/bin/bash
# ==============================================================================
# N1 OpenWrt 云编译 — script.sh
# 在 feeds 更新前运行，负责拉取外部插件和做系统级定制
# ==============================================================================
# 作用：
#   1. 拉取所有不在 Lean's LEDE 默认 feeds 里的外部插件
#   2. 删除与外部插件冲突的重复包
#   3. 修改默认 IP、主机名、主题等系统配置
#   4. 移除 ksmbd（与内核 6.12+ 不兼容）
# ==============================================================================

cd openwrt

echo ""
echo "======================================"
echo "  N1 OpenWrt script.sh 开始执行"
echo "======================================"
echo ""

# ==============================================================================
# 第一部分：拉取外部插件
# 所有插件通过 git clone 直接放到 package/ 目录
# 不走 feeds 方式，避免 feeds 更新覆盖本地修改
# ==============================================================================

echo ">>> [1/8] 拉取 kenzok8 插件合集（PassWall 等）"
git clone --depth 1 https://github.com/kenzok8/small-package package/small-package

echo ">>> [2/8] 拉取 Argon 主题"
git clone --depth 1 https://github.com/jerrykuku/luci-theme-argon.git package/luci-theme-argon
git clone --depth 1 https://github.com/jerrykuku/luci-app-argon-config.git package/luci-app-argon-config

echo ">>> [3/8] 拉取晶晨宝盒（N1 专属管理）"
git clone --depth 1 https://github.com/ophub/luci-app-amlogic.git package/luci-app-amlogic

echo ">>> [4/8] 拉取 AdGuardHome"
git clone --depth 1 https://github.com/rufengsuixing/luci-app-adguardhome.git package/luci-app-adguardhome

echo ">>> [5/8] 拉取 MosDNS 及其依赖"
# 先删除 feeds 里可能残留的旧版 mosdns 和 geodata Makefile
find ./ -name "Makefile" | grep -E "v2ray-geodata|mosdns" | xargs rm -f 2>/dev/null || true
git clone --depth 1 https://github.com/sbwml/luci-app-mosdns package/mosdns
git clone --depth 1 https://github.com/sbwml/v2ray-geodata package/geodata

echo ">>> [6/8] 拉取校园网防检测插件"
# ⚠️ UA2F 必须用 Zxilly/UA2F，绝对不用 SunBK201/UA2F（后者落后 286 commit，已废弃）
git clone --depth 1 https://github.com/Zxilly/UA2F.git package/UA2F
git clone --depth 1 https://github.com/EOYOHOO/rkp-ipid.git package/rkp-ipid

echo ">>> [7/8] 拉取 Golang 版本修复（MosDNS 依赖）"
# Lean's LEDE 自带的 golang 版本可能偏旧，sbwml 维护了一个修复版
rm -rf feeds/packages/lang/golang 2>/dev/null || true
git clone --depth 1 https://github.com/sbwml/packages_lang_golang feeds/packages/lang/golang

echo ">>> [8/8] 拉取 DDNS-Go"
# ddns-go 比 luci-app-ddns 更好用，支持阿里云/腾讯云/Cloudflare
git clone --depth 1 https://github.com/kenzok8/small-package package/small-package-ddns 2>/dev/null || true

# ==============================================================================
# 第二部分：删除冲突包
# kenzok8/small-package 里有些包和我们单独 clone 的重复
# 重复包会导致编译时 Makefile 冲突，必须删干净
# ==============================================================================

echo ""
echo ">>> 删除 kenzok8 中的重复包（防止编译冲突）"

# 主题相关：我们用 jerrykuku 的版本
rm -rf package/small-package/luci-app-argon*
rm -rf package/small-package/luci-theme-argon*

# 管理工具：我们用 ophub 的版本
rm -rf package/small-package/luci-app-amlogic

# 广告过滤：我们用 rufengsuixing 的版本
rm -rf package/small-package/luci-app-adguardhome

# DNS 分流：我们用 sbwml 的版本
rm -rf package/small-package/luci-app-mosdns

# 防火墙包：避免与系统防火墙冲突
rm -rf package/small-package/firewall*

# opkg：避免与系统 opkg 冲突
rm -rf package/small-package/opkg

# 可能存在的其他冲突包
rm -rf package/small-package/luci-app-wechatpush 2>/dev/null || true

# ==============================================================================
# 第三部分：移除 ksmbd
# ksmbd 3.5.4 与内核 6.12+ 不兼容，编译时会报错
# 即使当前 Lean 源码可能还在 6.1.y 系列内核，提前移除不影响功能
# ==============================================================================

echo ""
echo ">>> 移除 ksmbd（避免内核兼容性问题）"
rm -rf package/kernel/ksmbd 2>/dev/null || true

# ==============================================================================
# 第四部分：系统配置修改
# ==============================================================================

echo ""
echo ">>> 修改系统配置"

# ---- 4.1 默认 IP：192.168.1.1 → 192.168.2.10 ----
# N1 作为主路由运行，IP 设为 192.168.2.10
# 主路由假设为 192.168.2.1（如后续切旁路由，网关指向它）
# 注意：只改 config_generate 这一个文件，不动 Makefile 和 image-config.in
# 因为 Makefile 和 image-config.in 里 192.168.1. 可能出现在非 IP 上下文
sed -i 's/192\.168\.1\.1/192.168.2.10/g' package/base-files/files/bin/config_generate

# ---- 4.2 修改主机名 ----
sed -i 's/OpenWrt/OpenWrt-N1/g' package/base-files/files/bin/config_generate

# ---- 4.3 设置版本号 ----
VERSION_STR="N1-Campus $(TZ=UTC-8 date "+%Y.%m.%d") @ OpenWrt"
# Lean's LEDE 的默认设置脚本在不同位置，都处理一下
if [ -f "package/lean/default-settings/files/zzz-default-settings" ]; then
    sed -i "s/OpenWrt /${VERSION_STR} /g" package/lean/default-settings/files/zzz-default-settings
fi

# ---- 4.4 设置默认主题为 Argon ----
# 把 LuCI 默认的 bootstrap 主题替换为 Argon
if [ -d "feeds/luci/modules/luci-base/root/etc/config" ]; then
    sed -i 's/bootstrap/argon/g' feeds/luci/modules/luci-base/root/etc/config/luci
fi

# ---- 4.5 修复插件自启动脚本权限 ----
if [ -f "package/lean/default-settings/files/zzz-default-settings" ]; then
    sed -i '/exit 0/i\chmod +x /etc/init.d/*' package/lean/default-settings/files/zzz-default-settings
fi

# ---- 4.6 清除默认密码 ----
# 删除 Lean 源码中硬编码的默认密码哈希
if [ -f "package/lean/default-settings/files/zzz-default-settings" ]; then
    sed -i '/CYXluq4wUazHjmCDBCqXF/d' package/lean/default-settings/files/zzz-default-settings
fi

# ==============================================================================
# 第五部分：设置默认主路由模式
# 固件默认以"主路由模式"启动：
#   - DHCP 开启（由 N1 给局域网设备分配 IP）
#   - WiFi AP 开启（如果板载 WiFi 被驱动识别）
#   - 防火墙保护开启（WAN 入站拒绝）
# 切旁路由时在 LuCI 界面手动调整三处即可
# ==============================================================================

echo ""
echo ">>> 设置默认主路由模式（DHCP 开 + WiFi AP 开 + 防火墙保护开）"
echo "    切旁路由时在 LuCI 里手动调整即可，无需重刷固件"

# 通过 uci-defaults 脚本在首次启动时配置默认行为
# uci-defaults 目录下的脚本只在首次启动执行一次，比直接改配置文件干净
mkdir -p package/base-files/files/etc/uci-defaults

cat > package/base-files/files/etc/uci-defaults/99-n1-campus-setup <<'UCIEOF'
#!/bin/sh

# N1 校园网固件首次启动配置脚本
# 默认主路由模式：DHCP 开、防火墙保护开

# ---- LAN 口：静态 IP 192.168.2.10 ----
uci set network.lan.ipaddr='192.168.2.10'
uci set network.lan.netmask='255.255.255.0'
# 主路由模式：不设网关（N1 自己就是网关）
uci -q delete network.lan.gateway
# DNS 指向自己（MosDNS / AdGuardHome 会接管）
uci set network.lan.dns='192.168.2.10'
uci commit network

# ---- DHCP：开启（主路由负责 IP 分配）----
uci set dhcp.lan.ignore='0'
# 分配范围 192.168.2.100 - 192.168.2.250
uci set dhcp.lan.start='100'
uci set dhcp.lan.limit='150'
uci set dhcp.lan.leasetime='12h'
# DHCP 下发选项：网关和 DNS 都指向 N1
uci -q delete dhcp.lan.dhcp_option
uci add_list dhcp.lan.dhcp_option='3,192.168.2.10'
uci add_list dhcp.lan.dhcp_option='6,192.168.2.10'
uci commit dhcp

# ---- 防火墙：主路由保护模式 ----
# WAN 入站拒绝，LAN 之间接受
uci set firewall.@zone[0].input='ACCEPT'    # lan
uci set firewall.@zone[0].output='ACCEPT'
uci set firewall.@zone[0].forward='ACCEPT'
if [ -n "$(uci -q get firewall.@zone[1])" ]; then
    uci set firewall.@zone[1].input='DROP'   # wan
    uci set firewall.@zone[1].output='ACCEPT'
    uci set firewall.@zone[1].forward='REJECT'
    uci set firewall.@zone[1].masq='1'
    uci set firewall.@zone[1].mtu_fix='1'
fi
uci commit firewall

# ---- WiFi：尝试启用 AP 模式 ----
# N1 板载 WiFi 芯片（通常为 RTL8189ES，SDIO 接口）在 OpenWrt 上驱动支持不稳定
# 固件里已包含可能的驱动包，如果被识别到 radio 设备，就配置默认 AP
# 如果板载 WiFi 没被驱动识别，这段配置不会生效，需要插 USB WiFi 网卡
for radio in $(uci -q show wireless | grep '=wifi-device' | cut -d. -f2 | cut -d= -f1); do
    uci -q set wireless.${radio}.disabled='0'
    uci -q set wireless.${radio}.channel='auto'
    uci -q set wireless.${radio}.hwmode='11g'
    uci -q set wireless.${radio}.htmode='HT20'

    # 查找该 radio 下是否已有 wifi-iface，没有就创建一个
    iface=$(uci -q show wireless | grep "device='${radio}'" | cut -d. -f2 | head -1)
    if [ -z "$iface" ]; then
        iface="default_radio_$(echo $radio | sed 's/radio//')"
        uci -q set wireless.${iface}=wifi-iface
        uci -q set wireless.${iface}.device="${radio}"
    fi
    uci -q set wireless.${iface}.network='lan'
    uci -q set wireless.${iface}.mode='ap'
    uci -q set wireless.${iface}.ssid='N1-OpenWrt'
    uci -q set wireless.${iface}.encryption='psk2'
    uci -q set wireless.${iface}.key='n1campus2026'
    uci commit wireless
done

echo "N1-Campus 首次启动配置完成"
echo "默认 IP: 192.168.2.10  账号: root  密码: password"
echo "WiFi SSID: N1-OpenWrt  WiFi 密码: n1campus2026"
echo "如需切旁路由：LAN 网关设为 192.168.2.1，DHCP 关闭，防火墙全接受"

UCIEOF
chmod +x package/base-files/files/etc/uci-defaults/99-n1-campus-setup

# ==============================================================================
# 第六部分：预置 TTL 统一 nftables 规则
# 防检测第一层：统一出口 TTL=128，消除多设备 TTL 指纹差异
# 刷机后到 LuCI→网络→防火墙确认规则是否加载
# ==============================================================================

echo ""
echo ">>> 预置 TTL 统一 nftables 规则（TTL=128，伪装 Windows 单设备）"

mkdir -p package/base-files/files/etc/nftables.d

cat > package/base-files/files/etc/nftables.d/12-mangle-ttl-128.nft <<'NFTEOF'
# TTL 统一规则：所有出口数据包 TTL 设为 128
# 消除 Windows(128) / Linux(64) / Android(64) / iOS(64) 的差异
# ⚠️ 注意：
#   1. eth0 需替换为你的 WAN 口实际接口名（在 LuCI→网络→接口中查看）
#      旁路由模式 WAN 口名可能不同
#   2. 如果使用 PPPoE 拨号，接口名可能是 pppoe-wan
#   3. 此规则在 fw4/nftables 架构下生效（Lean's LEDE 默认使用 fw4）

chain custom_ttl_set {
    type filter hook postrouting priority 300; policy accept;

    # IPv4 TTL 统一为 128（伪装 Windows）
    oifname "eth0" ip ttl set 128

    # IPv6 Hop Limit 统一为 128
    oifname "eth0" ip6 hoplimit set 128
}
NFTEOF

echo "    规则文件：/etc/nftables.d/12-mangle-ttl-128.nft"
echo "    刷机后确认接口名是否正确（eth0 可能要改）"

# ==============================================================================
# 第七部分：打印当前内核版本信息（编译日志参考）
# ==============================================================================

echo ""
echo "======================================"
echo "  当前源码内核版本信息："
echo "======================================"
if [ -f "include/kernel-default.mk" ]; then
    grep -E "LINUX_VERSION|LINUX_KERNEL" include/kernel-default.mk 2>/dev/null || true
fi
# OpenWrt 新版可能用不同的文件存内核版本
grep -rE "LINUX_VERSION|LINUX_KERNEL_HASH" target/linux/armvirt/ 2>/dev/null | head -5 || true
echo "======================================"

echo ""
echo ">>> script.sh 执行完成"
echo ""
