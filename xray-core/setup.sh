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

echo "=== Xray 配置自动生成脚本 ==="
echo ""

# 检查模板文件是否存在
if [ ! -f "$CONFIG_TEMPLATE" ]; then
    echo "错误: 找不到 config.example.json 模板文件"
    exit 1
fi

# 检查 config.json 是否已存在，如果存在则二次确认
if [ -f "$CONFIG_FILE" ]; then
    echo "警告: config.json 已存在！"
    read -p "是否覆盖现有配置？(y/N): " confirm
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
PRIVATE_KEY=$(echo "$KEYPAIR" | grep "PrivateKey:" | awk '{print $2}')
PUBLIC_KEY=$(echo "$KEYPAIR" | grep "Password:" | awk '{print $2}')
echo "   PrivateKey: $PRIVATE_KEY"
echo "   Password: $PUBLIC_KEY"

# 生成 shortId
echo ""
echo "3. 生成 shortId..."
SHORT_ID=$(docker run --rm $DOCKER_IMAGE sh -c "openssl rand -hex 8")
echo "   shortId: $SHORT_ID"

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

# 从模板生成 config.json
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

# 从 config.json 中读取配置信息
echo ""
echo "6. 读取配置信息..."

# 读取端口
PORT=$(grep -o '"port": [0-9]*' "$CONFIG_FILE" | head -1 | awk '{print $2}')

# 读取 flow
FLOW=$(grep -o '"flow": "[^"]*"' "$CONFIG_FILE" | head -1 | cut -d'"' -f4)

# 生成 VLESS 分享链接
echo ""
echo "7. 生成 VLESS 分享链接..."

# 确定分享链接名称
if [ -z "$SHARE_LINK_NAME" ]; then
    NAME_RAW="VLESS-$PUBLIC_IP"
else
    NAME_RAW="$SHARE_LINK_NAME"
fi

# URL 编码名称
NAME_ENCODED=$(printf "%s" "$NAME_RAW" | xxd -plain | tr -d '\n' | sed 's/\(..\)/%\1/g')

# 组装 VLESS 链接
VLESS_LINK="vless://${CLIENT_UUID}@${PUBLIC_IP}:${PORT}?encryption=none&flow=${FLOW}&security=reality&sni=${SNI_DOMAIN}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none#${NAME_ENCODED}"

# 保存到 sharelink.txt
echo "$VLESS_LINK" > "$SHARELINK_FILE"

echo ""
echo "=== 生成完成 ==="
echo ""
echo "配置信息:"
echo "  客户端 UUID: $CLIENT_UUID"
echo "  PrivateKey: $PRIVATE_KEY"
echo "  Password: $PUBLIC_KEY"
echo "  shortId: $SHORT_ID"
echo "  公网 IP: $PUBLIC_IP"
echo "  端口: $PORT"
echo "  SNI: $SNI_DOMAIN"
echo "  Flow: $FLOW"
echo "  分享链接名称: $NAME_RAW"
echo ""
echo "VLESS 分享链接已保存到: $SHARELINK_FILE"
echo ""
echo "分享链接:"
echo "$VLESS_LINK"
echo ""

# 二次确认是否启动容器
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
    echo "提示: 可通过以下命令手动启动/重启服务:"
    echo "  docker compose up -d"
fi

echo ""