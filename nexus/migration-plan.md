# Nexus Repository 3 H2 迁移到 PostgreSQL 方案

## 环境信息

- Nexus 版本：3.91.1-04
- 迁移类型：H2 → PostgreSQL
- PostgreSQL 版本：17

## 前置条件

- 至少 16GB 可用 RAM
- 数据库目录 3 倍的磁盘空间（`./data/db` 目录）
- 迁移期间 Nexus 服务中断

---

## 第一步：备份 H2 数据库

在 Nexus 管理界面执行：System → Tasks → 创建 `Admin - Backup H2 Database` 任务，Location 填写 `/nexus-data/backup`，立即运行。

同时备份 db 目录：

```bash
cp -r ./data/db ./data/db.bak
```

---

## 第二步：准备 .env 文件和 docker-compose.yml

创建 `.env` 文件（存放数据库密码，不提交到版本控制）：

```bash
echo "POSTGRES_PASSWORD=your_secure_password" > .env
```

`docker-compose.yml` 参考配置（nexus-db 通过 env_file 读取密码，Nexus 暂不配置 PostgreSQL 连接参数）：

```yaml
services:
  nexus-db:
    image: postgres:17
    container_name: nexus-db
    restart: unless-stopped
    env_file:
      - .env
    environment:
      - TZ=Asia/Shanghai
      - POSTGRES_DB=nexus
      - POSTGRES_USER=nexus
    volumes:
      - ./postgres-data:/var/lib/postgresql/data
    networks:
      - nginx_default

  nexus:
    image: sonatype/nexus3
    container_name: nexus
    restart: unless-stopped
    depends_on:
      - nexus-db
    environment:
      - TZ=Asia/Shanghai
      - INSTALL4J_ADD_VM_PARAMS=-Dnexus.secrets.file=/nexus-data/nexus-private-key.json
    volumes:
      - ./data:/nexus-data
      - ./nexus-private-key.json:/nexus-data/nexus-private-key.json:ro
    networks:
      - nginx_default

networks:
  nginx_default:
    external: true
```

---

## 第三步：启动 PostgreSQL，初始化 schema

```bash
docker compose up -d nexus-db
```

初始化 schema：

```bash
docker exec nexus-db psql -U nexus -d nexus -c "
CREATE SCHEMA IF NOT EXISTS nexus;
GRANT USAGE, CREATE ON SCHEMA nexus TO nexus;
"
```

---

## 第四步：停止 Nexus，下载迁移工具

```bash
docker compose stop nexus

cd ./data/db
wget https://download.sonatype.com/nexus/nxrm3-migrator/nexus-db-migrator-3.91.1-04.jar
cd ../..
```

---

## 第五步：执行迁移

**工作目录必须是 `nexus.mv.db` 所在目录，否则 H2 会静默创建空库导致迁移 0 条记录。**

```bash
docker run --rm -it \
  --network=nginx_default \
  -v $(pwd)/data/db:/db \
  -w /db \
  sonatype/nexus3:3.91.1 \
  java -Xmx16G -Xms16G -XX:+UseG1GC -XX:MaxDirectMemorySize=28672M \
  -jar nexus-db-migrator-3.91.1-04.jar \
  --migration_type=h2_to_postgres \
  --db_url="jdbc:postgresql://nexus-db:5432/nexus?user=nexus&password=your_secure_password&currentSchema=nexus"
```

迁移成功标志：日志末尾出现 `status: [COMPLETED]`。

迁移完成后执行 VACUUM 回收空间：

```bash
docker exec nexus-db psql -U nexus -d nexus -c "VACUUM(FULL, ANALYZE, VERBOSE);"
```

---

## 第六步：配置 Nexus 连接 PostgreSQL

在 `./data/etc/nexus.properties` 中追加：

```properties
nexus.datastore.enabled=true
nexus.datastore.nexus.jdbcUrl=jdbc:postgresql://nexus-db:5432/nexus?currentSchema=nexus
nexus.datastore.nexus.username=nexus
nexus.datastore.nexus.password=your_secure_password
nexus.datastore.nexus.maximumPoolSize=20
```

---

## 第七步：重命名 H2 文件并启动 Nexus

```bash
mv ./data/db/nexus.mv.db ./data/db/nexus.mv.db.bak

docker compose up -d nexus
```

---

## 第八步：验证

```bash
docker logs -f nexus | grep -i postgresql
```

看到以下输出即为成功：

```
nexus.datastore.nexus.jdbcUrl=jdbc:postgresql://nexus-db:5432/nexus?currentSchema=nexus
```

---

## 迁移后任务

Nexus 启动后自动运行以下任务，**期间不要重启**：

- `Rebuild repository browse`
- `Rebuild repository search`

可在 System → Tasks 中查看进度。

---

## 迁移完成后清理

确认运行正常后：

```bash
tar -czf ./data/db-h2-backup.tar.gz ./data/db.bak
rm -rf ./data/db.bak
```

---

## 注意事项

| 事项 | 说明 |
|------|------|
| JDBC URL 协议 | 固定为 `jdbc:postgresql://`，不随容器名变化 |
| 迁移工具版本 | 必须与 Nexus 版本完全一致（3.91.1-04） |
| 运行目录 | 必须在 `nexus.mv.db` 所在目录（`-w /db`）下运行 |
| 不支持的格式 | Bower、APK、Composer、CPAN、Puppet 不会被迁移 |
| .env 文件 | 加入 `.gitignore`，避免密码泄露 |
