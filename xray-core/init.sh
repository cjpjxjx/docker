#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_TEMPLATE="$SCRIPT_DIR/config.example.json"
CONFIG_FILE="$SCRIPT_DIR/config.json"
SHARELINK_FILE="$SCRIPT_DIR/sharelink.txt"
DOCKER_IMAGE="teddysun/xray"

# ========== 配置变量 ==========
# SNI 域名（必须以 www. 开头）
SNI_DOMAIN="www.microsoft.com"

# 分享链接名称（留空则使用默认格式：VLESS-公网IP）
SHARE_LINK_NAME=""
# ==============================

# 参数解析
REFRESH_MODE=false
if [ "$1" == "--refresh" ] || [ "$1" == "-r" ]; then
    REFRESH_MODE=true
fi

echo "=== Xray 配置管理脚本 ==="
echo ""

if [ "$REFRESH_MODE" = true ]; then
    echo "模式: 刷新现有配置"
    echo "说明: 将从现有配置文件中读取 UUID、密钥、端口等信息，仅更新公网 IP 并重新生成分享链接。"
    echo "确认操作: 接下来将读取 config.json 和 sharelink.txt，并覆盖更新 sharelink.txt。"
    read -p "是否确认继续？(y/N): " confirm_refresh
    if [[ ! "$confirm_refresh" =~ ^[Yy]$ ]]; then
        echo "操作已取消"
        exit 0
    fi
    echo ""

    if [ ! -f "$CONFIG_FILE" ] || [ ! -f "$SHARELINK_FILE" ]; then
        echo "错误: 找不到 config.json 或 sharelink.txt，无法执行刷新操作。"
        exit 1
    fi

    echo "1. 从现有文件中提取配置..."
    # 从 config.json 提取
    CLIENT_UUID=$(grep -o '"id": "[^"]*"' "$CONFIG_FILE" | head -1 | cut -d'"' -f4)
    PRIVATE_KEY=$(grep -o '"privateKey": "[^"]*"' "$CONFIG_FILE" | head -1 | cut -d'"' -f4)
    # 兼容单行和多行格式提取 shortIds (取数组中的第一个值)
    SHORT_ID=$(grep -A 1 '"shortIds":' "$CONFIG_FILE" | grep -o '"[^"]*"' | grep -v "shortIds" | head -1 | tr -d '"')
    
    # 从 sharelink.txt 提取公钥 (pbk 参数)
    PUBLIC_KEY=$(grep -o 'pbk=[^&#]*' "$SHARELINK_FILE" | head -1 | cut -d'=' -f2)

    if [ -z "$CLIENT_UUID" ] || [ -z "$PUBLIC_KEY" ] || [ -z "$SHORT_ID" ]; then
        echo "错误: 无法提取完整配置信息 (UUID/PublicKey/shortId)。"
        exit 1
    fi
    echo "   UUID: $CLIENT_UUID"
    echo "   PublicKey: $PUBLIC_KEY"
    echo "   shortId: $SHORT_ID"
    echo ""
    echo "2. 跳过密钥生成 (刷新模式)"
    echo ""
    echo "3. 跳过 shortId 生成 (刷新模式)"
else
    # 正常模式：生成新配置
    # 检查模板文件是否存在
    if [ ! -f "$CONFIG_TEMPLATE" ]; then
        echo "错误: 找不到 config.example.json 模板文件"
        exit 1
    fi

    # 检查 config.json 是否已存在，如果存在则二次确认
    if [ -f "$CONFIG_FILE" ]; then
        echo "警告: config.json 已存在！"
        read -p "是否覆盖现有配置并生成全新的密钥对？(y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "操作已取消"
            exit 0
        fi
        echo ""
    fi

    # 生成 UUID
    echo "1. 生成客户端 UUID..."
    CLIENT_UUID=$(docker run --rm $DOCKER_IMAGE sh -c "xray uuid")
    echo "   UUID: $CLIENT_UUID"

    # 生成 X25519 密钥对
    echo ""
    echo "2. 生成 X25519 密钥对..."
    KEYPAIR=$(docker run --rm $DOCKER_IMAGE sh -c "xray x25519")
    PRIVATE_KEY=$(echo "$KEYPAIR" | grep "PrivateKey" | awk '{print $NF}')
    PUBLIC_KEY=$(echo "$KEYPAIR" | grep -E "^(PublicKey|Password):" | awk '{print $NF}')
    echo "   PrivateKey: $PRIVATE_KEY"
    echo "   PublicKey: $PUBLIC_KEY"

    # 生成 shortId
    echo ""
    echo "3. 生成 shortId..."
    SHORT_ID=$(docker run --rm $DOCKER_IMAGE sh -c "openssl rand -hex 8")
    echo "   shortId: $SHORT_ID"
fi

# 获取公网 IP
echo ""
echo "4. 获取公网 IP..."

# 公网 IP 查询地址列表
IP_CHECK_URLS=(
    "checkip.amazonaws.com"
    "eth0.me"
    "icanhazip.com"
    "ifconfig.co"
    "ipinfo.io/ip"
)

PUBLIC_IP=""

for url in "${IP_CHECK_URLS[@]}"; do
    echo -n "   尝试 $url ... "

    # 获取 HTTP 状态码和响应内容
    response=$(curl -s -w "\n%{http_code}" "http://$url" 2>/dev/null)
    http_code=$(echo "$response" | tail -n1)
    ip_content=$(echo "$response" | head -n1 | tr -d '[:space:]')

    # 检查状态码是否为 200 且内容是否为有效 IP 地址
    if [ "$http_code" = "200" ] && [[ "$ip_content" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        PUBLIC_IP="$ip_content"
        echo "成功 ($PUBLIC_IP)"
        break
    else
        echo "失败"
    fi
done

if [ -z "$PUBLIC_IP" ]; then
    echo ""
    echo "错误: 无法获取公网 IP，所有地址均失败"
    exit 1
fi

echo "   ✓ 公网 IP: $PUBLIC_IP"

# 只有在非刷新模式下才重新生成 config.json
if [ "$REFRESH_MODE" = false ]; then
    echo ""
    echo "5. 生成 config.json..."

    # 提取基础域名（去掉 www. 前缀）
    BASE_DOMAIN="${SNI_DOMAIN#www.}"

    # 从模板复制并替换
    cp "$CONFIG_TEMPLATE" "$CONFIG_FILE"

    # 替换 UUID、私钥、shortId
    sed -i "s/\"id\": \"<template>\"/\"id\": \"$CLIENT_UUID\"/" "$CONFIG_FILE"
    sed -i "s/\"privateKey\": \"<template>\"/\"privateKey\": \"$PRIVATE_KEY\"/" "$CONFIG_FILE"
    sed -i "s/\"<template>\"/\"$SHORT_ID\"/" "$CONFIG_FILE"

    # 替换域名（只有当不是 microsoft.com 时才替换）
    if [ "$BASE_DOMAIN" != "microsoft.com" ]; then
        sed -i "s/www.microsoft.com/$SNI_DOMAIN/g" "$CONFIG_FILE"
        sed -i "s/microsoft.com/$BASE_DOMAIN/g" "$CONFIG_FILE"
    fi

    echo "   配置文件已生成"
else
    echo ""
    echo "5. 跳过生成 config.json (刷新模式)"
fi

# 从 config.json 中读取配置信息
echo ""
echo "6. 读取配置信息..."

# 读取端口
PORT=$(grep -o '"port": [0-9]*' "$CONFIG_FILE" | head -1 | awk '{print $2}')

# 读取 flow
FLOW=$(grep -o '"flow": "[^"]*"' "$CONFIG_FILE" | head -1 | cut -d'"' -f4)

# 提取 SNI (刷新模式下可能已经手动改过 config.json)
SNI_DOMAIN_EXTRACTED=$(grep -o '"serverNames": \[ "[^"]*"' "$CONFIG_FILE" | head -1 | cut -d'"' -f4)
if [ ! -z "$SNI_DOMAIN_EXTRACTED" ]; then
    SNI_DOMAIN="$SNI_DOMAIN_EXTRACTED"
fi

# 生成 VLESS 分享链接
echo ""
echo "7. 生成 VLESS 分享链接..."

# 确定分享链接名称
if [ -z "$SHARE_LINK_NAME" ]; then
    NAME_RAW="VLESS-$PUBLIC_IP"
else
    NAME_RAW="$SHARE_LINK_NAME"
fi

# URL 编码名称 (优先尝试 python3 只转义非字母数字字符，否则回退到 xxd 全转义方案)
if command -v python3 > /dev/null 2>&1; then
    NAME_ENCODED=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$NAME_RAW")
else
    NAME_ENCODED=$(printf "%s" "$NAME_RAW" | xxd -plain | tr -d '\n' | sed 's/\(..\)/%\1/g')
fi

# 组装 VLESS 链接
VLESS_LINK="vless://${CLIENT_UUID}@${PUBLIC_IP}:${PORT}?encryption=none&flow=${FLOW}&security=reality&sni=${SNI_DOMAIN}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none#${NAME_ENCODED}"

# 生成 Mihomo 节点配置 (JSON 格式)
MIHOMO_CONFIG="{\"type\":\"vless\",\"name\":\"$NAME_RAW\",\"server\":\"$PUBLIC_IP\",\"port\":$PORT,\"uuid\":\"$CLIENT_UUID\",\"tls\":true,\"flow\":\"$FLOW\",\"client-fingerprint\":\"chrome\",\"skip-cert-verify\":false,\"reality-opts\":{\"public-key\":\"$PUBLIC_KEY\",\"short-id\":\"$SHORT_ID\"},\"network\":\"tcp\",\"encryption\":\"none\",\"udp\":true,\"servername\":\"$SNI_DOMAIN\"}"

# 保存到 sharelink.txt
{
    echo "=== VLESS 分享链接 ==="
    echo "$VLESS_LINK"
    echo ""
    echo "=== Mihomo 节点配置 ==="
    echo "$MIHOMO_CONFIG"
} > "$SHARELINK_FILE"

echo ""
echo "=== 生成完成 ==="
echo ""
echo "配置信息:"
echo "  客户端 UUID: $CLIENT_UUID"
if [ "$REFRESH_MODE" = false ]; then
    echo "  PrivateKey: $PRIVATE_KEY"
fi
echo "  PublicKey: $PUBLIC_KEY"
echo "  shortId: $SHORT_ID"
echo "  公网 IP: $PUBLIC_IP"
echo "  端口: $PORT"
echo "  SNI: $SNI_DOMAIN"
echo "  Flow: $FLOW"
echo ""
echo "配置信息已保存到: $SHARELINK_FILE"
echo ""
echo "VLESS 分享链接:"
echo "$VLESS_LINK"
echo ""
echo "Mihomo 节点配置:"
echo "$MIHOMO_CONFIG"
echo ""

# 只有在非刷新模式下才提示启动容器
if [ "$REFRESH_MODE" = false ]; then
    echo ""
    read -p "是否立即启动 Xray 容器？(y/N): " start_container

    if [[ "$start_container" =~ ^[Yy]$ ]]; then
        echo ""
        echo "正在启动容器..."

        # 进入脚本目录
        cd "$SCRIPT_DIR"

        # 先停止并删除现有容器
        echo "  → 停止现有容器..."
        docker compose down 2>/dev/null || true

        # 启动新容器
        echo "  → 启动新容器..."
        docker compose up -d

        echo ""
        echo "✓ 容器已启动"
        echo ""
        echo "查看日志: docker compose logs -f"
        echo "停止容器: docker compose down"
    else
        echo ""
        echo "提示: 可通过以下命令手动启动服务:"
        echo "  docker compose up -d"
    fi
fi

echo ""