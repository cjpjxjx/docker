# Xray-core Reality 一键部署工具

本项目是一个简单高效 of Xray-core 部署方案，支持最新的 **VLESS + XTLS-Vision + REALITY** 组合。通过自动化脚本，您可以快速生成配置并以 Docker 容器方式运行。

## 功能特点

- **自动配置**：一键生成 UUID、X25519 密钥对和随机 shortId。
- **公网 IP 识别**：自动探测服务器公网 IP，无需手动填写。
- **REALITY 安全性**：默认配置使用 `www.microsoft.com` 作为目标域名（SNI），提供极高的抗封锁能力。
- **Docker 化管理**：使用 Docker Compose 管理，部署与维护极其简便。
- **双重配置输出**：脚本执行完成后直接输出 **VLESS 分享链接** 和 **Mihomo (Clash Meta) 节点配置**。
- **配置刷新功能**：支持通过参数快速刷新分享链接（如公网 IP 变动时），而无需重置密钥。

## 快速开始

### 1. 前置要求

确保您的服务器已安装：
- [Docker](https://docs.docker.com/get-docker/)
- [Docker Compose](https://docs.docker.com/compose/install/)

### 2. 下载并运行

赋予脚本执行权限并运行：

```bash
chmod +x init.sh
./init.sh
```

### 3. 刷新配置（可选）

如果您的服务器公网 IP 发生变动，或者您只想重新生成分享链接而不更改现有密钥，请运行：

```bash
./init.sh --refresh
```

## 脚本执行流程

1. **生成/提取配置**：正常模式下生成新 UUID 和密钥对；刷新模式下从 `config.json` 和 `sharelink.txt` 中提取。
2. **获取公网 IP**：通过多个 API 自动获取当前服务器 IP。
3. **生成/保留配置文件**：根据模板生成 `config.json`（刷新模式下保留原文件）。
4. **生成分享信息**：
    - **VLESS 链接**：适用于 v2rayN, V2RayNG 等。
    - **Mihomo 配置**：适用于 Mihomo (Clash Meta) 内核。
5. **保存信息**：将以上分享信息保存至 `sharelink.txt`。
6. **启动服务**：询问是否立即启动或重启 Docker 容器。

## 文件说明

- `init.sh`: 核心管理脚本。
- `config.example.json`: Xray 配置文件模板。
- `docker-compose.yml`: Docker 服务定义文件。
- `config.json`: (生成的) Xray 运行配置文件。
- `sharelink.txt`: (生成的) 包含 VLESS 分享链接和 Mihomo 节点配置的备份文件。

## 常用管理命令

**启动服务：**
```bash
docker compose up -d
```

**停止服务：**
```bash
docker compose down
```

**查看日志：**
```bash
docker compose logs -f
```

**重启服务：**
```bash
docker compose restart
```

## 注意事项

- **端口占用**：默认配置使用 `443` 端口，请确保该端口未被其他服务（如 Nginx）占用。
- **防火墙**：请确保服务器防火墙（如 ufw, firewalld）已放行对应的端口。
- **自定义域名**：如果需要修改伪装域名，可以编辑 `init.sh` 中的 `SNI_DOMAIN` 变量后再运行。

## 免责声明

本项目仅供学习和研究使用，请在遵守当地法律法规的前提下使用。
