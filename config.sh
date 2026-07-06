#!/bin/bash
# ==============================================================================
# N1 OpenWrt 云编译 — config.sh
# 在 feeds install 后运行，负责生成 .config 种子配置
# make defconfig 会根据此种子自动展开为完整配置
# ==============================================================================

cd openwrt

echo ""
echo "======================================"
echo "  N1 OpenWrt config.sh 开始执行"
echo "======================================"
echo ""

# ==============================================================================
# 第零部分：架构锁定（最重要的保险）
# ==============================================================================
# 为什么需要这段：
#   Lean's LEDE 的 make defconfig 在某些情况下会将 target fallback 到
#   编译环境宿主机的架构（ubuntu-22.04 = x86_64），导致编译出 x86 固件。
#   触发条件包括：.config 中 target 配置不完整、多 target 并存、
#   或 defconfig 检测到配置冲突时自动选择默认值。
#
#   此段在写入新配置前，先清理 .config 里所有可能残留的 target 行，
#   然后写入干净的 armvirt 配置。这是"强制转换回 ARM"的关键操作。
# ==============================================================================

echo ">>> [步骤 0] 架构锁定：清理残留 target，强制写入 armvirt_64_generic"

# 如果 .config 已存在（Lean's LEDE 默认会先生成一个空 .config）
# 先删除所有 target 相关行，防止多个 target 并存导致 defconfig 混乱
if [ -f ".config" ]; then
    echo "    检测到已有 .config，清理所有 target 相关行..."
    sed -i '/^CONFIG_TARGET_/d' .config
    sed -i '/^# CONFIG_TARGET_/d' .config
    # 再次确认：不应该有任何 target 残留
    if grep -q "CONFIG_TARGET_" .config; then
        echo "    ⚠️ 仍有 target 残留，全文重新清理"
        > .config
    fi
fi

# 写入干净的 armvirt target 配置
# 这三行是架构的绝对权威，defconfig 会以此为基础展开
cat >> .config <<'ARCHEOF'

# ==============================================================================
# === 架构锁定（N1 = Amlogic S905D = ARM64）===
# ==============================================================================
# Target System: QEMU ARM Virtual Machine
# Subtarget: ARMv8 multiplatform (64-bit ARM machines)
# Target Profile: Generic
#
# ⚠️ 不要改这三行！改了就会变成 x86 固件！
# ⚠️ 如果你看到编译日志里 target 变成了 x86/armsr，说明 defconfig 跑偏了
#    YML 里有第二道保险（defconfig 后验证 + 强制纠正）
# ==============================================================================
CONFIG_TARGET_armvirt=y
CONFIG_TARGET_armvirt_64=y
CONFIG_TARGET_armvirt_64_DEVICE_generic=y
# CONFIG_TARGET_x86 is not set
# CONFIG_TARGET_armsr is not set
# CONFIG_TARGET_armvirt_32 is not set
# CONFIG_TARGET_MULTI_PROFILE is not set

# === 输出格式：tar.gz ===
# Flippy 打包脚本需要 tar.gz 格式的 rootfs
CONFIG_TARGET_ROOTFS_TARGZ=y
# CONFIG_TARGET_ROOTFS_EXT4FS is not set
# CONFIG_TARGET_ROOTFS_SQUASHFS is not set

# === rootfs 分区大小（MB），512MB 足够装下所有插件 + Docker ===
CONFIG_TARGET_ROOTFS_PARTSIZE=512

ARCHEOF

echo "    ✓ 架构已锁定为 armvirt_64_generic"

# ==============================================================================
# 第一部分：禁用 ksmbd（与内核 6.12+ 不兼容）
# ==============================================================================

echo ">>> [步骤 1] 禁用 ksmbd（内核兼容性）"

cat >> .config <<'KSMBDEOF'

# === 禁用 ksmbd ===
# ksmbd 3.5.4 与内核 6.12+ 不兼容，提前禁用
# ksmbd-server 和 autosamba 依赖 kmod-fs-ksmbd，必须一起禁用
CONFIG_KMOD_FS_KSMBD=n
CONFIG_PACKAGE_kmod-fs-ksmbd=n
CONFIG_PACKAGE_ksmbd-server=n
CONFIG_PACKAGE_autosamba=n
KSMBDEOF

echo "    ✓ ksmbd 已禁用"

# ==============================================================================
# 第二部分：LuCI 基础组件 + 中文支持
# ==============================================================================

echo ">>> [步骤 2] 写入 LuCI 基础组件 + 中文包"

cat >> .config <<'LUCIBASEEOF'

# ==============================================================================
# === LuCI Web 管理界面基础 ===
# ==============================================================================
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-base=y
CONFIG_PACKAGE_luci-compat=y
CONFIG_PACKAGE_luci-ssl=y
CONFIG_PACKAGE_luci-ssl-openssl=y
CONFIG_PACKAGE_luci-mod-admin-full=y

# === 中文语言包 ===
CONFIG_PACKAGE_luci-i18n-base-zh-cn=y
CONFIG_PACKAGE_luci-i18n-opkg-zh-cn=y
CONFIG_PACKAGE_luci-i18n-firewall-zh-cn=y
LUCIBASEEOF

echo "    ✓ LuCI 基础组件已写入"

# ==============================================================================
# 第三部分：主题（Argon）
# ==============================================================================

echo ">>> [步骤 3] 写入主题（Argon）"

cat >> .config <<'THEMEEOF'

# ==============================================================================
# === 界面主题 ===
# ==============================================================================
# Argon：社区评价最高的现代化 OpenWrt 主题
# 支持暗色模式自动切换、自定义登录背景、流畅动画
# 备选主题（在线安装）：design / alpha / edge / material
CONFIG_PACKAGE_luci-theme-argon=y
CONFIG_PACKAGE_luci-app-argon-config=y
# CONFIG_PACKAGE_luci-theme-bootstrap is not set
THEMEEOF

echo "    ✓ Argon 主题已写入"

# ==============================================================================
# 第四部分：防检测套件（校园网核心需求）
# ==============================================================================

echo ">>> [步骤 4] 写入防检测套件（UA2F + kmod-rkp-ipid）"

cat >> .config <<'ANTIDETECTEOF'

# ==============================================================================
# === 校园网防检测套件（核心需求）===
# ==============================================================================
# 防检测四层架构：
#   1. TTL 统一   → nftables postrouting 规则（script.sh 已预置）→ 无需额外包
#   2. UA 伪装   → UA2F（NFQUEUE 劫持 HTTP 替换 UA）           → 本段配置
#   3. IPID 统一 → kmod-rkp-ipid（内核模块自动生效）            → 本段配置
#   4. NTP 劫持  → dnsmasq 截获 NTP 请求                        → 刷机后在 LuCI 开启
#
# ⚠️ UA2F 仓库必须是 Zxilly/UA2F（script.sh 已 clone），不是 SunBK201/UA2F
# ⚠️ UA2F 与 Turbo ACC 的 Shortcut-FE 冲突，刷机后只开 BBR，关闭 SFE
# ⚠️ UA2F 与流量卸载冲突，刷机后在防火墙中禁用"路由/NAT 卸载"
# ==============================================================================

# UA2F：统一 HTTP User-Agent，伪装单设备
CONFIG_PACKAGE_ua2f=y
CONFIG_PACKAGE_luci-app-ua2f=y

# kmod-rkp-ipid：统一 IP Identification 递增规律
CONFIG_PACKAGE_kmod-rkp-ipid=y

ANTIDETECTEOF

echo "    ✓ 防检测套件已写入"

# ==============================================================================
# 第五部分：科学上网（PassWall 全套）
# ==============================================================================

echo ">>> [步骤 5] 写入 PassWall 全组件"

cat >> .config <<'PASSWALLEOF'

# ==============================================================================
# === 科学上网（PassWall）===
# ==============================================================================
# 选择 PassWall 而非 OpenClash/SSR-Plus 的理由：
#   N1 只有 2GB RAM，PassWall 最轻量
#   PassWall 支持多协议（SS/Trojan/Xray/Hysteria）
#   OpenClash 基于 Clash 核心，资源占用更大

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

echo "    ✓ PassWall 全组件已写入"

# ==============================================================================
# 第六部分：DNS 优化与广告过滤
# ==============================================================================

echo ">>> [步骤 6] 写入 DNS 优化（MosDNS + AdGuardHome）"

cat >> .config <<'DNSEOF'

# ==============================================================================
# === DNS 优化与广告过滤 ===
# ==============================================================================
# MosDNS：国内外 DNS 分流核心，与 PassWall 配合成熟
# AdGuardHome：DNS 级广告过滤 + 追踪拦截
# 组合方式：AdGuardHome 监听 53 端口 → 转发到 MosDNS → MosDNS 分流上游

CONFIG_PACKAGE_luci-app-mosdns=y
CONFIG_PACKAGE_luci-app-adguardhome=y

# dnsmasq-full：完整版 dnsmasq（支持 ipset 等高级功能）
# Lean's LEDE 默认可能用 dnsmasq 基础版，需要显式指定 full
CONFIG_PACKAGE_dnsmasq-full=y
# CONFIG_PACKAGE_dnsmasq is not set

DNSEOF

echo "    ✓ DNS 优化已写入"

# ==============================================================================
# 第七部分：网络加速（Turbo ACC）
# ==============================================================================

echo ">>> [步骤 7] 写入 Turbo ACC（编译进固件，刷机后只开 BBR）"

cat >> .config <<'TURBOACCEOF'

# ==============================================================================
# === 网络加速（Turbo ACC）===
# ==============================================================================
# ⚠️ 重要冲突提醒：
#   Turbo ACC 包含三种加速引擎：
#     1. Shortcut-FE（SFE）— 流量卸载，与 UA2F/kmod-rkp-ipid 冲突
#     2. BBR — 拥塞控制算法，不冲突，推荐开启
#     3. FullCone NAT — NAT 类型优化，不冲突，推荐开启
#
#   固件编译进去以便刷机后选择使用，但刷机后务必：
#     ✅ 开启：BBR 拥塞控制
#     ✅ 开启：FullCone NAT
#     ❌ 关闭：Shortcut-FE 流加速（与 UA2F 冲突）

CONFIG_PACKAGE_luci-app-turboacc=y
CONFIG_PACKAGE_kmod-ipt-offload=y
CONFIG_PACKAGE_kmod-nf-flow=y

TURBOACCEOF

echo "    ✓ Turbo ACC 已写入（刷机后关闭 SFE）"

# ==============================================================================
# 第八部分：Docker 支持
# ==============================================================================

echo ">>> [步骤 8] 写入 Docker 全家桶"

cat >> .config <<'DOCKEREEOF'

# ==============================================================================
# === Docker 支持 ===
# ==============================================================================
# N1 有 2GB RAM 和 8GB eMMC，Docker 可用但空间有限
# 建议 Docker 数据目录挂载到外部 USB 存储
# 编译进固件可以省去后续手动安装的麻烦

CONFIG_PACKAGE_docker=y
CONFIG_PACKAGE_dockerd=y
CONFIG_PACKAGE_containerd=y
CONFIG_PACKAGE_runc=y
CONFIG_PACKAGE_tini=y
CONFIG_PACKAGE_cgroupfs-mount=y
CONFIG_DOCKER_CGROUP_OPTIONS=y
CONFIG_DOCKER_NET_MACVLAN=y
CONFIG_DOCKER_STO_EXT4=y

# Docker 管理界面（LuCI 可视化）
CONFIG_PACKAGE_luci-app-dockerman=y

# 内核 CGROUP 配置（Docker 依赖）
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

# 文件系统支持（Docker overlay2 需要）
CONFIG_PACKAGE_btrfs-progs=y
CONFIG_PACKAGE_f2fs-tools=y
CONFIG_PACKAGE_f2fsck=y
CONFIG_PACKAGE_xfs-fsck=y
CONFIG_PACKAGE_xfs-mkfs=y
CONFIG_PACKAGE_dosfstools=y

DOCKEREEOF

echo "    ✓ Docker 全家桶已写入"

# ==============================================================================
# 第九部分：WiFi 驱动（方案 A：板载 WiFi 尝试）
# ==============================================================================

echo ">>> [步骤 9] 写入 WiFi 驱动包（尝试驱动板载 WiFi）"

cat >> .config <<'WIFIEOF'

# ==============================================================================
# === WiFi 驱动包（方案 A）===
# ==============================================================================
# N1 板载 WiFi 芯片（通常为 RTL8189ES，SDIO 接口）
# 在 OpenWrt 上驱动支持不稳定，以下驱动包尽可能覆盖：
#   - rtl8xxxu：Realtek 通用 USB WiFi 驱动（覆盖部分 RTL8189）
#   - brcmfmac：Broadcom WiFi 驱动（部分 N1 版本使用 BCM 芯片）
#   - cfg80211 + mac80211：无线子系统基础
#   - wpad：完整的 AP + Client 守护进程（支持 WPA3）
#
# 刷机后在 LuCI→网络→无线 查看：
#   有 radio 设备 → 板载 WiFi 被识别，可配置 AP
#   无 radio 设备 → 板载 WiFi 未被驱动，插 USB WiFi 网卡

# 无线子系统基础
CONFIG_PACKAGE_kmod-cfg80211=y
CONFIG_PACKAGE_kmod-mac80211=y

# Realtek 通用驱动
CONFIG_PACKAGE_kmod-rtl8xxxu=y

# Broadcom SDIO/USB 驱动（部分 N1 版本使用）
CONFIG_PACKAGE_kmod-brcmfmac=y
CONFIG_PACKAGE_brcmfmac-firmware-43430-sdio=y
CONFIG_PACKAGE_brcmfmac-firmware-43455-sdio=y
CONFIG_PACKAGE_brcmfmac-firmware-usb=y
CONFIG_PACKAGE_kmod-brcmutil=y

# USB WiFi 适配器驱动（方案 B 备选）
CONFIG_PACKAGE_kmod-rtl8821cu=y
CONFIG_PACKAGE_kmod-rtl8822bu=y
CONFIG_PACKAGE_kmod-rtl8822ce=y

# AP + Client 守护进程（full 版本，支持 WPA3）
CONFIG_PACKAGE_wpad=y
CONFIG_PACKAGE_hostapd=y
CONFIG_PACKAGE_hostapd-common=y

# 无线工具
CONFIG_PACKAGE_wireless-tools=y
CONFIG_PACKAGE_iw=y
CONFIG_PACKAGE_iwinfo=y

WIFIEOF

echo "    ✓ WiFi 驱动包已写入"

# ==============================================================================
# 第十部分：网络工具与内核模块
# ==============================================================================

echo ">>> [步骤 10] 写入网络工具与内核模块"

cat >> .config <<'KERNELEOF'

# ==============================================================================
# === 内核模块（USB / 存储 / 网络）===
# ==============================================================================

# USB 驱动（N1 有两个 USB 口）
CONFIG_PACKAGE_kmod-usb-core=y
CONFIG_PACKAGE_kmod-usb-ohci=y
CONFIG_PACKAGE_kmod-usb-storage=y
CONFIG_PACKAGE_kmod-usb-storage-extras=y
CONFIG_PACKAGE_kmod-usb2=y
CONFIG_PACKAGE_kmod-usb3=y

# 文件系统支持
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

# ==============================================================================
# === 网络工具 ===
# ==============================================================================
CONFIG_PACKAGE_iptables-mod-extra=y
CONFIG_PACKAGE_iptables-mod-tproxy=y
CONFIG_PACKAGE_ip-full=y
CONFIG_PACKAGE_ipset=y
CONFIG_PACKAGE_ip6tables=y
CONFIG_PACKAGE_ipv6helper=y
CONFIG_PACKAGE_nftables=y

# WireGuard
CONFIG_PACKAGE_wireguard-tools=y
CONFIG_PACKAGE_kmod-wireguard=y

# TCP BBR 拥塞控制
CONFIG_PACKAGE_kmod-tcp-bbr=y

# NAT6 支持
CONFIG_PACKAGE_kmod-ipt-nat6=y
CONFIG_PACKAGE_ip6tables=y

KERNELEOF

echo "    ✓ 内核模块已写入"

# ==============================================================================
# 第十一部分：实用工具与 LuCI 插件
# ==============================================================================

echo ">>> [步骤 11] 写入实用工具与 LuCI 插件"

cat >> .config <<'APPSEOF'

# ==============================================================================
# === 实用 LuCI 插件 ===
# ==============================================================================

# 晶晨宝盒（N1 专属：安装到 eMMC、在线升级、备份恢复）
CONFIG_PACKAGE_luci-app-amlogic=y

# 动态 DNS（ddns-go：比旧版 luci-app-ddns 更好用）
CONFIG_PACKAGE_luci-app-ddns-go=y

# 网页终端（调试必备，浏览器内 SSH）
CONFIG_PACKAGE_luci-app-ttyd=y

# 网络唤醒
CONFIG_PACKAGE_luci-app-wol=y

# UPnP 自动端口映射
CONFIG_PACKAGE_luci-app-upnp=y

# 定时重启（每天凌晨自动重启保证稳定）
CONFIG_PACKAGE_luci-app-autoreboot=y

# 流量统计
CONFIG_PACKAGE_luci-app-nlbwmon=y

# Web 文件管理器
CONFIG_PACKAGE_luci-app-filetransfer=y

# 在线状态监控
CONFIG_PACKAGE_luci-app-watchcat=y

# ==============================================================================
# === 基础工具 ===
# ==============================================================================
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
CONFIG_PACKAGE_chattr=y
CONFIG_PACKAGE_attr=y
CONFIG_PACKAGE_getopt=y
CONFIG_PACKAGE_gawk=y

# 文件系统工具
CONFIG_PACKAGE_e2fsprogs=y
CONFIG_PACKAGE_resize2fs=y

# OpenWrt 包管理器
CONFIG_PACKAGE_opkg=y

APPSEOF

echo "    ✓ 实用工具已写入"

# ==============================================================================
# 第十二部分：编译优化
# ==============================================================================

echo ">>> [步骤 12] 写入编译优化选项"

cat >> .config <<'BUILDEOF'

# ==============================================================================
# === 编译优化 ===
# ==============================================================================
# zstd 压缩优化等级
CONFIG_ZSTD_OPTIMIZE_O3=y

# 降低 WPA 日志级别（让日志更清爽）
CONFIG_WPA_MSG_MIN_PRIORITY=3

BUILDEOF

echo "    ✓ 编译优化已写入"

# ==============================================================================
# 完成：打印配置摘要
# ==============================================================================

echo ""
echo "======================================"
echo "  config.sh 执行完成"
echo "======================================"
echo ""
echo "  架构：armvirt_64_generic（Amlogic S905D / N1）"
echo "  输出：tar.gz（Flippy 打包需要）"
echo "  主题：Argon"
echo ""
echo "  防检测：UA2F + kmod-rkp-ipid + TTL nftables"
echo "  科学上网：PassWall（SS + Trojan + Xray + Hysteria）"
echo "  DNS：MosDNS + AdGuardHome"
echo "  Docker：全组件"
echo "  WiFi：尝试驱动板载（方案 A）"
echo ""
echo "  默认 IP：192.168.2.10"
echo "  默认模式：主路由（DHCP 开 + WiFi AP 开）"
echo "  默认密码：password"
echo ""
echo ">>> 接下来 YML 会执行 make defconfig 展开种子配置"
echo "    并做架构验证（防止 defconfig 跑偏到 x86）"
echo ""
