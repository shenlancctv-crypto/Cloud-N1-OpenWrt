#!/bin/bash
# ==============================================================================
# N1 OpenWrt 云编译 — config.sh
# 在 feeds install 后运行，生成 .config 种子配置
# ==============================================================================

cd openwrt

echo ""
echo "======================================"
echo "  N1 OpenWrt config.sh 开始执行"
echo "======================================"
echo ""

# ==============================================================================
# 步骤 0：架构锁定（armsr_armv8_generic）
# ==============================================================================
# Lean's LEDE master 已删除 armvirt target，改名为 armsr
# 映射关系：
#   armvirt                          → armsr
#   armvirt_64                       → armsr_armv8
#   armvirt_64_DEVICE_generic        → armsr_armv8_DEVICE_generic
# 产物路径：bin/targets/armsr/armv8/
# ==============================================================================

echo ">>> [步骤 0] 架构锁定：清理残留 target，强制写入 armsr_armv8_generic"

if [ -f ".config" ]; then
    echo "    检测到已有 .config，清理所有 target 相关行..."
    sed -i '/^CONFIG_TARGET_/d' .config
    sed -i '/^# CONFIG_TARGET_/d' .config
    if grep -q "CONFIG_TARGET_" .config; then
        echo "    ⚠️ 仍有 target 残留，全文重新清理"
        > .config
    fi
fi

cat >> .config <<'ARCHEOF'

# ==============================================================================
# === 架构锁定（N1 = Amlogic S905D = ARM64）===
# ==============================================================================
# LEDE master 已用 armsr 替代 armvirt
# Target System: ARM System Profile (armsr)
# Subtarget: ARMv8 / 64-bit ARM machines (armv8)
# Target Profile: Generic
# 产物路径: bin/targets/armsr/armv8/
# ==============================================================================
CONFIG_TARGET_armsr=y
CONFIG_TARGET_armsr_armv8=y
CONFIG_TARGET_armsr_armv8_DEVICE_generic=y
# CONFIG_TARGET_x86 is not set
# CONFIG_TARGET_MULTI_PROFILE is not set

# 输出格式：tar.gz（Flippy 打包需要）
CONFIG_TARGET_ROOTFS_TARGZ=y
# CONFIG_TARGET_ROOTFS_EXT4FS is not set
# CONFIG_TARGET_ROOTFS_SQUASHFS is not set

# rootfs 分区大小（MB）
CONFIG_TARGET_ROOTFS_PARTSIZE=512

ARCHEOF

echo "    架构已锁定为 armsr_armv8_generic"

# ==============================================================================
# 步骤 1：禁用 ksmbd
# ==============================================================================

echo ">>> [步骤 1] 禁用 ksmbd"

cat >> .config <<'KSMBDEOF'

# 禁用 ksmbd（与内核 6.12+ 不兼容）
CONFIG_KMOD_FS_KSMBD=n
CONFIG_PACKAGE_kmod-fs-ksmbd=n
CONFIG_PACKAGE_ksmbd-server=n
CONFIG_PACKAGE_autosamba=n
KSMBDEOF

echo "    ksmbd 已禁用"

# ==============================================================================
# 步骤 2：LuCI 基础 + 中文
# ==============================================================================

echo ">>> [步骤 2] LuCI 基础组件 + 中文包"

cat >> .config <<'LUCIBASEEOF'

# LuCI Web 管理界面
# 注意：用 luci-ssl 而非 luci-ssl-openssl（后者与某些包冲突）
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-base=y
CONFIG_PACKAGE_luci-compat=y
CONFIG_PACKAGE_luci-ssl=y
CONFIG_PACKAGE_luci-mod-admin-full=y
# 显式排除会冲突的 openssl ustream
# CONFIG_PACKAGE_libustream-openssl is not set

# 中文语言包
CONFIG_PACKAGE_luci-i18n-base-zh-cn=y
CONFIG_PACKAGE_luci-i18n-opkg-zh-cn=y
CONFIG_PACKAGE_luci-i18n-firewall-zh-cn=y
LUCIBASEEOF

echo "    LuCI 基础组件已写入"

# ==============================================================================
# 步骤 3：主题
# ==============================================================================

echo ">>> [步骤 3] Argon 主题"

cat >> .config <<'THEMEEOF'

# Argon 主题 + 配置工具
CONFIG_PACKAGE_luci-theme-argon=y
CONFIG_PACKAGE_luci-app-argon-config=y
# CONFIG_PACKAGE_luci-theme-bootstrap is not set
THEMEEOF

echo "    Argon 主题已写入"

# ==============================================================================
# 步骤 4：防检测套件
# ==============================================================================

echo ">>> [步骤 4] 防检测套件"

cat >> .config <<'ANTIDETECTEOF'

# 校园网防检测套件
# TTL → nftables 规则（script.sh 已预置）
# UA → UA2F（Zxilly/UA2F，script.sh 已 clone）
# IPID → kmod-rkp-ipid（EOYOHOO/rkp-ipid，script.sh 已 clone）
# NTP → dnsmasq 截获（刷机后 LuCI 开启）

CONFIG_PACKAGE_ua2f=y
CONFIG_PACKAGE_luci-app-ua2f=y
CONFIG_PACKAGE_kmod-rkp-ipid=y
ANTIDETECTEOF

echo "    防检测套件已写入"

# ==============================================================================
# 步骤 5：PassWall 全组件
# ==============================================================================

echo ">>> [步骤 5] PassWall 全组件"

cat >> .config <<'PASSWALLEOF'

# PassWall 全协议
CONFIG_PACKAGE_luci-app-passwall=y
CONFIG_PACKAGE_luci-app-passwall_Iptables_Transparent_Proxy=y
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Shadowsocks_Libev_Client=y
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Shadowsocks_Libev_Server=y
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Shadowsocks_Rust_Client=y
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Trojan_GO=y
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Trojan_Plus=y
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Xray=y
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Hysteria=y
PASSWALLEOF

echo "    PassWall 已写入"

# ==============================================================================
# 步骤 6：DNS 优化
# ==============================================================================

echo ">>> [步骤 6] DNS 优化"

cat >> .config <<'DNSEOF'

# MosDNS + AdGuardHome
CONFIG_PACKAGE_luci-app-mosdns=y
CONFIG_PACKAGE_luci-app-adguardhome=y
# dnsmasq-full 替代基础版
CONFIG_PACKAGE_dnsmasq-full=y
# CONFIG_PACKAGE_dnsmasq is not set
DNSEOF

echo "    DNS 优化已写入"

# ==============================================================================
# 步骤 7：Turbo ACC
# ==============================================================================

echo ">>> [步骤 7] Turbo ACC"

cat >> .config <<'TURBOACCEOF'

# Turbo ACC（刷机后只开 BBR，关闭 SFE 以免与 UA2F 冲突）
CONFIG_PACKAGE_luci-app-turboacc=y
CONFIG_PACKAGE_kmod-ipt-offload=y
CONFIG_PACKAGE_kmod-nf-flow=y
TURBOACCEOF

echo "    Turbo ACC 已写入"

# ==============================================================================
# 步骤 8：Docker
# ==============================================================================

echo ">>> [步骤 8] Docker"

cat >> .config <<'DOCKEREOF'

# Docker 全家桶（使用 feeds 自带版，script.sh 已删 kenzok8 版以避免冲突）
CONFIG_PACKAGE_docker=y
CONFIG_PACKAGE_dockerd=y
CONFIG_PACKAGE_containerd=y
CONFIG_PACKAGE_runc=y
CONFIG_PACKAGE_tini=y
CONFIG_PACKAGE_cgroupfs-mount=y
CONFIG_DOCKER_CGROUP_OPTIONS=y
CONFIG_DOCKER_NET_MACVLAN=y
CONFIG_DOCKER_STO_EXT4=y

# Docker 管理界面
CONFIG_PACKAGE_luci-app-dockerman=y

# 内核 CGROUP 配置
CONFIG_KERNEL_ARM_PMU=y
CONFIG_KERNEL_PERF_EVENTS=y
CONFIG_KERNEL_CGROUP_FREEZER=y
CONFIG_KERNEL_CGROUP_DEVICE=y
CONFIG_KERNEL_CGROUP_NET_PRIO=y
CONFIG_KERNEL_CGROUP_PERF=y
CONFIG_KERNEL_NET_CLS_CGROUP=y
CONFIG_KERNEL_FS_POSIX_ACL=y
CONFIG_KERNEL_EXT4_FS_POSIX_ACL=y
CONFIG_KERNEL_EXT4_FS_SECURITY=y
CONFIG_KERNEL_MEMCG_SWAP_ENABLED=y
CONFIG_CGROUPFS_MOUNT_KERNEL_CGROUPS=y

# 文件系统工具
CONFIG_PACKAGE_btrfs-progs=y
CONFIG_PACKAGE_f2fs-tools=y
CONFIG_PACKAGE_f2fsck=y
CONFIG_PACKAGE_xfs-fsck=y
CONFIG_PACKAGE_xfs-mkfs=y
CONFIG_PACKAGE_dosfstools=y
DOCKEREOF

echo "    Docker 已写入"

# ==============================================================================
# 步骤 9：WiFi 驱动
# ==============================================================================

echo ">>> [步骤 9] WiFi 驱动包"

cat >> .config <<'WIFIEOF'

# WiFi 驱动（N1 板载 RTL8189ES SDIO，驱动支持不稳定，尽量覆盖）
CONFIG_PACKAGE_kmod-cfg80211=y
CONFIG_PACKAGE_kmod-mac80211=y
CONFIG_PACKAGE_kmod-rtl8xxxu=y

# Broadcom SDIO/USB（部分 N1 版本）
CONFIG_PACKAGE_kmod-brcmfmac=y
CONFIG_PACKAGE_brcmfmac-firmware-43430-sdio=y
CONFIG_PACKAGE_brcmfmac-firmware-43455-sdio=y
CONFIG_PACKAGE_brcmfmac-firmware-usb=y
CONFIG_PACKAGE_kmod-brcmutil=y

# USB WiFi 适配器（方案 B 备选）
CONFIG_PACKAGE_kmod-rtl8821cu=y
CONFIG_PACKAGE_kmod-rtl8822bu=y
CONFIG_PACKAGE_kmod-rtl8822ce=y

# AP + Client 守护进程
CONFIG_PACKAGE_wpad=y
CONFIG_PACKAGE_hostapd=y
CONFIG_PACKAGE_hostapd-common=y

# 无线工具
CONFIG_PACKAGE_wireless-tools=y
CONFIG_PACKAGE_iw=y
CONFIG_PACKAGE_iwinfo=y
WIFIEOF

echo "    WiFi 驱动已写入"

# ==============================================================================
# 步骤 10：内核模块 + 网络工具
# ==============================================================================

echo ">>> [步骤 10] 内核模块 + 网络工具"

cat >> .config <<'KERNELEOF'

# USB 驱动
CONFIG_PACKAGE_kmod-usb-core=y
CONFIG_PACKAGE_kmod-usb-ohci=y
CONFIG_PACKAGE_kmod-usb-storage=y
CONFIG_PACKAGE_kmod-usb-storage-extras=y
CONFIG_PACKAGE_kmod-usb2=y
CONFIG_PACKAGE_kmod-usb3=y

# 文件系统
CONFIG_PACKAGE_kmod-fs-ext4=y
CONFIG_PACKAGE_kmod-fs-ntfs=y
CONFIG_PACKAGE_kmod-fs-vfat=y
CONFIG_PACKAGE_kmod-fs-exfat=y
CONFIG_PACKAGE_kmod-nls-cp437=y
CONFIG_PACKAGE_kmod-nls-cp936=y
CONFIG_PACKAGE_kmod-nls-iso8859-1=y
CONFIG_PACKAGE_kmod-nls-utf8=y

# 网络内核模块
CONFIG_PACKAGE_kmod-ipt-nat=y
CONFIG_PACKAGE_kmod-ipt-nat6=y
CONFIG_PACKAGE_kmod-nf-nathelper=y
CONFIG_PACKAGE_kmod-nf-nathelper-extra=y
CONFIG_PACKAGE_kmod-nft-core=y
CONFIG_PACKAGE_kmod-nft-nat=y
CONFIG_PACKAGE_kmod-tun=y
CONFIG_PACKAGE_kmod-bridge=y
CONFIG_PACKAGE_kmod-tcp-bbr=y

# 网络工具
CONFIG_PACKAGE_iptables-mod-extra=y
CONFIG_PACKAGE_iptables-mod-tproxy=y
CONFIG_PACKAGE_ip-full=y
CONFIG_PACKAGE_ipset=y
CONFIG_PACKAGE_ip6tables=y
CONFIG_PACKAGE_ipv6helper=y
CONFIG_PACKAGE_nftables=y

# ── miniupnpd（luci-app-upnp 的实际后端，新版 LEDE 不自动补）──
CONFIG_PACKAGE_miniupnpd=y
CONFIG_PACKAGE_luci-app-upnp=y

# WireGuard
CONFIG_PACKAGE_wireguard-tools=y
CONFIG_PACKAGE_kmod-wireguard=y
KERNELEOF

echo "    内核模块已写入"

# ==============================================================================
# 步骤 11：实用工具 + LuCI 插件
# ==============================================================================

echo ">>> [步骤 11] 实用工具 + LuCI 插件"

cat >> .config <<'APPSEOF'

# 晶晨宝盒
CONFIG_PACKAGE_luci-app-amlogic=y

# DDNS-Go
CONFIG_PACKAGE_luci-app-ddns-go=y

# 网页终端
CONFIG_PACKAGE_luci-app-ttyd=y

# 网络唤醒
CONFIG_PACKAGE_luci-app-wol=y

# 定时重启
CONFIG_PACKAGE_luci-app-autoreboot=y

# 流量统计
CONFIG_PACKAGE_luci-app-nlbwmon=y

# Web 文件管理
CONFIG_PACKAGE_luci-app-filetransfer=y

# 基础工具
CONFIG_PACKAGE_bash=y
CONFIG_PACKAGE_curl=y
CONFIG_PACKAGE_htop=y
CONFIG_PACKAGE_unzip=y
CONFIG_PACKAGE_coreutils=y
CONFIG_PACKAGE_coreutils-nohup=y
CONFIG_PACKAGE_block-mount=y
CONFIG_PACKAGE_ca-certificates=y
CONFIG_PACKAGE_tar=y
CONFIG_PACKAGE_xz=y
CONFIG_PACKAGE_bzip2=y
CONFIG_PACKAGE_pigz=y
CONFIG_PACKAGE_jq=y

# 磁盘工具
CONFIG_PACKAGE_lsblk=y
CONFIG_PACKAGE_blkid=y
CONFIG_PACKAGE_fdisk=y
CONFIG_PACKAGE_pv=y

# 文件系统
CONFIG_PACKAGE_e2fsprogs=y
CONFIG_PACKAGE_resize2fs=y
CONFIG_PACKAGE_opkg=y
APPSEOF

echo "    实用工具已写入"

# ==============================================================================
# 步骤 12：编译优化
# ==============================================================================

echo ">>> [步骤 12] 编译优化"

cat >> .config <<'BUILDEOF'

CONFIG_ZSTD_OPTIMIZE_O3=y
CONFIG_WPA_MSG_MIN_PRIORITY=3
BUILDEOF

echo "    编译优化已写入"

# ==============================================================================
# 完成
# ==============================================================================

echo ""
echo "======================================"
echo "  config.sh 执行完成"
echo "======================================"
echo ""
echo "  架构：armsr_armv8_generic（Amlogic S905D / N1）"
echo "  产物路径：bin/targets/armsr/armv8/"
echo "  主题：Argon"
echo ""
echo "  防检测：UA2F + kmod-rkp-ipid + TTL nftables"
echo "  科学上网：PassWall（SS + Trojan + Xray + Hysteria）"
echo "  DNS：MosDNS + AdGuardHome"
echo "  Docker：全组件（feeds 自带版）"
echo "  WiFi：尝试驱动板载"
echo ""
echo "  默认 IP：192.168.2.10"
echo "  默认模式：主路由（DHCP 开 + WiFi AP 开）"
echo "  默认密码：password"
echo ""
