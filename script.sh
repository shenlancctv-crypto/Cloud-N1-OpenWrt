#!/bin/bash
# ==============================================================================
# N1 OpenWrt 云编译 — script.sh（修订版 v3）
# 修复 opkg host/compile 报错：按 kenzok8 官方推荐清理全套冲突包
# ==============================================================================

cd openwrt

echo ""
echo "======================================"
echo "  N1 OpenWrt script.sh 开始执行"
echo "======================================"
echo ""

# ==============================================================================
# 第一部分：拉取外部插件
# ==============================================================================

echo ">>> [1/7] 拉取 kenzok8 插件合集（PassWall 等）"
git clone --depth 1 https://github.com/kenzok8/small-package package/small-package

echo ">>> [2/7] 拉取 Argon 主题"
git clone --depth 1 https://github.com/jerrykuku/luci-theme-argon.git package/luci-theme-argon
git clone --depth 1 https://github.com/jerrykuku/luci-app-argon-config.git package/luci-app-argon-config

echo ">>> [3/7] 拉取晶晨宝盒（N1 专属管理）"
git clone --depth 1 https://github.com/ophub/luci-app-amlogic.git package/luci-app-amlogic

echo ">>> [4/7] 拉取 AdGuardHome"
git clone --depth 1 https://github.com/rufengsuixing/luci-app-adguardhome.git package/luci-app-adguardhome

echo ">>> [5/7] 拉取 MosDNS 及其依赖"
find ./ -name "Makefile" | grep -E "v2ray-geodata|mosdns" | xargs rm -f 2>/dev/null || true
git clone --depth 1 https://github.com/sbwml/luci-app-mosdns package/mosdns
git clone --depth 1 https://github.com/sbwml/v2ray-geodata package/geodata

echo ">>> [6/7] 拉取校园网防检测插件"
# 先删除 feeds 自带的 ua2f，防止两份 Makefile 并存形成递归依赖
rm -rf feeds/packages/net/ua2f 2>/dev/null || true
find ./ -path "./feeds/*" -name "Makefile" | xargs grep -l "ua2f" 2>/dev/null | xargs rm -f 2>/dev/null || true
git clone --depth 1 https://github.com/Zxilly/UA2F.git package/UA2F
git clone --depth 1 https://github.com/EOYOHOO/rkp-ipid.git package/rkp-ipid

echo ">>> [7/7] 拉取 Golang 版本修复（MosDNS 依赖）"
rm -rf feeds/packages/lang/golang 2>/dev/null || true
git clone --depth 1 https://github.com/sbwml/packages_lang_golang feeds/packages/lang/golang

# DDNS-Go 已包含在 small-package 中，不必重复 clone

# ==============================================================================
# 第二部分：删除冲突包
# ==============================================================================

echo ""
echo ">>> 删除 kenzok8 中的重复/冲突包"

# 主题：用 jerrykuku 版本
rm -rf package/small-package/luci-app-argon*
rm -rf package/small-package/luci-theme-argon*

# 管理工具
rm -rf package/small-package/luci-app-amlogic

# 广告过滤
rm -rf package/small-package/luci-app-adguardhome

# DNS 分流
rm -rf package/small-package/luci-app-mosdns

# ── kenzok8 官方推荐冲突包清理（issue #107）──
# kenzok8/small-package 自带与 LEDE 系统包同名的版本，
# feeds install 后会覆盖系统 Makefile，导致 host/compile 规则丢失
# kenzok8 本人推荐的修复（2023-09-29 评论）：
#   rm -rf feeds/smpackage/{base-files,dnsmasq,firewall*,fullconenat,
#     libnftnl,nftables,ppp,opkg,ucl,upx,vsftpd-alt,
#     miniupnpd-iptables,wireless-regdb}
# 我们在 feeds install 前直接删除源目录，效果相同
rm -rf package/small-package/base-files
rm -rf package/small-package/dnsmasq
rm -rf package/small-package/firewall*
rm -rf package/small-package/fullconenat
rm -rf package/small-package/libnftnl
rm -rf package/small-package/nftables
rm -rf package/small-package/ppp
rm -rf package/small-package/opkg
rm -rf package/small-package/ucl
rm -rf package/small-package/upx
rm -rf package/small-package/vsftpd-alt
rm -rf package/small-package/miniupnpd-iptables
rm -rf package/small-package/wireless-regdb

# ── Docker 全家桶冲突 ──
# 删除 kenzok8 自带 Docker，用 feeds 版
rm -rf package/small-package/docker
rm -rf package/small-package/dockerd
rm -rf package/small-package/containerd
rm -rf package/small-package/runc
rm -rf package/small-package/tini
rm -rf package/small-package/cgroupfs-mount
rm -rf package/small-package/luci-app-dockerman
rm -rf package/small-package/luci-app-docker

# ── tcping 编译失败修复 ──
rm -rf package/small-package/tcping

# ── 递归依赖问题包 ──
rm -rf package/small-package/natmap 2>/dev/null || true
rm -rf package/small-package/luci-app-fchomo 2>/dev/null || true
rm -rf package/small-package/luci-app-torbp 2>/dev/null || true
rm -rf package/small-package/clashoo 2>/dev/null || true

# 其他
rm -rf package/small-package/luci-app-wechatpush 2>/dev/null || true

# ==============================================================================
# 第三部分：移除 ksmbd
# ==============================================================================

echo ""
echo ">>> 移除 ksmbd（避免内核兼容性问题）"
rm -rf package/kernel/ksmbd 2>/dev/null || true

# ==============================================================================
# 第四部分：系统配置修改
# ==============================================================================

echo ""
echo ">>> 修改系统配置"

# 4.1 默认 IP
sed -i 's/192\.168\.1\.1/192.168.2.10/g' package/base-files/files/bin/config_generate

# 4.2 主机名
sed -i 's/OpenWrt/OpenWrt-N1/g' package/base-files/files/bin/config_generate

# 4.3 版本号
VERSION_STR="N1-Campus $(TZ=UTC-8 date "+%Y.%m.%d") @ OpenWrt"
if [ -f "package/lean/default-settings/files/zzz-default-settings" ]; then
    sed -i "s/OpenWrt /${VERSION_STR} /g" package/lean/default-settings/files/zzz-default-settings
fi

# 4.4 默认主题 Argon
if [ -d "feeds/luci/modules/luci-base/root/etc/config" ]; then
    sed -i 's/bootstrap/argon/g' feeds/luci/modules/luci-base/root/etc/config/luci
fi

# 4.5 修复插件自启动脚本权限
if [ -f "package/lean/default-settings/files/zzz-default-settings" ]; then
    sed -i '/exit 0/i\chmod +x /etc/init.d/*' package/lean/default-settings/files/zzz-default-settings
fi

# 4.6 清除默认密码哈希
if [ -f "package/lean/default-settings/files/zzz-default-settings" ]; then
    sed -i '/CYXluq4wUazHjmCDBCqXF/d' package/lean/default-settings/files/zzz-default-settings
fi

# ==============================================================================
# 第五部分：设置默认主路由模式 + 密码
# ==============================================================================

echo ""
echo ">>> 设置默认主路由模式 + 固定密码"

mkdir -p package/base-files/files/etc/uci-defaults

cat > package/base-files/files/etc/uci-defaults/99-n1-campus-setup <<'UCIEOF'
#!/bin/sh

# N1 校园网固件首次启动配置脚本
# 默认主路由模式：DHCP 开、WiFi AP 开、防火墙保护开

# LAN 口
uci set network.lan.ipaddr='192.168.2.10'
uci set network.lan.netmask='255.255.255.0'
uci -q delete network.lan.gateway
uci set network.lan.dns='192.168.2.10'
uci commit network

# DHCP：开启
uci set dhcp.lan.ignore='0'
uci set dhcp.lan.start='100'
uci set dhcp.lan.limit='150'
uci set dhcp.lan.leasetime='12h'
uci -q delete dhcp.lan.dhcp_option
uci add_list dhcp.lan.dhcp_option='3,192.168.2.10'
uci add_list dhcp.lan.dhcp_option='6,192.168.2.10'
uci commit dhcp

# 防火墙：主路由保护模式
uci set firewall.@zone[0].input='ACCEPT'
uci set firewall.@zone[0].output='ACCEPT'
uci set firewall.@zone[0].forward='ACCEPT'
if [ -n "$(uci -q get firewall.@zone[1])" ]; then
    uci set firewall.@zone[1].input='DROP'
    uci set firewall.@zone[1].output='ACCEPT'
    uci set firewall.@zone[1].forward='REJECT'
    uci set firewall.@zone[1].masq='1'
    uci set firewall.@zone[1].mtu_fix='1'
fi
uci commit firewall

# WiFi AP（如果板载 WiFi 被驱动识别到）
for radio in $(uci -q show wireless | grep '=wifi-device' | cut -d. -f2 | cut -d= -f1); do
    uci -q set wireless.${radio}.disabled='0'
    uci -q set wireless.${radio}.channel='auto'
    uci -q set wireless.${radio}.hwmode='11g'
    uci -q set wireless.${radio}.htmode='HT20'
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

# 设置 root 密码为 password
echo "root:password" | chpasswd 2>/dev/null || true

echo "N1-Campus 首次启动配置完成"
echo "默认 IP: 192.168.2.10  账号: root  密码: password"
echo "WiFi SSID: N1-OpenWrt  WiFi 密码: n1campus2026"

UCIEOF
chmod +x package/base-files/files/etc/uci-defaults/99-n1-campus-setup

# ==============================================================================
# 第六部分：TTL 统一 nftables 规则
# ==============================================================================

echo ""
echo ">>> 预置 TTL 统一 nftables 规则"

mkdir -p package/base-files/files/etc/nftables.d

cat > package/base-files/files/etc/nftables.d/12-mangle-ttl-128.nft <<'NFTEOF'
chain custom_ttl_set {
    type filter hook postrouting priority 300; policy accept;
    oifname "eth0" ip ttl set 128
    oifname "eth0" ip6 hoplimit set 128
}
NFTEOF

# ==============================================================================
# 第七部分：版本信息打印
# ==============================================================================

echo ""
echo "======================================"
echo "  当前源码内核版本信息："
echo "======================================"
if [ -f "include/kernel-default.mk" ]; then
    grep -E "LINUX_VERSION|LINUX_KERNEL" include/kernel-default.mk 2>/dev/null || true
fi
grep -rE "LINUX_VERSION|LINUX_KERNEL_HASH" target/linux/armsr/ 2>/dev/null | head -5 || true
echo "======================================"

echo ""
echo ">>> script.sh 执行完成"
echo ""
