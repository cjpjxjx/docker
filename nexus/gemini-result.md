根据 Sonatype 官方文档的规范，从 H2 迁移到 PostgreSQL 的核心要点是：必须使用与 Nexus 版本号完全一致的 `nexus-db-migrator` 工具，且**必须在 `nexus.mv.db` 文件所在的当前目录下运行该工具**。如果在其他目录运行，H2 会静默创建一个空的数据库文件，导致最终显示迁移了 0 条记录。

以下是基于你现有的 Docker Compose 网络结构和数据卷挂载路径，执行数据迁移的完整操作指令：

```bash
# 1. 确保 PostgreSQL 数据库已根据新的 docker-compose.yml 启动
docker compose up -d postgresql

# 2. 停止当前运行的 Nexus 容器以释放 H2 数据库文件锁
docker compose stop nexus

# 3. 进入挂载的数据目录中的 db 文件夹并下载对应版本的迁移工具
cd data/db
wget https://download.sonatype.com/nexus/nxrm3-migrator/nexus-db-migrator-3.91.1-04.jar
cd ../..

# 4. 运行一次性容器执行迁移
# 借助 sonatype/nexus3 镜像内嵌的 Java 环境，接入 nginx_default 网络直连 postgresql
# 必须将工作目录 -w 指定为 /db，确保工具能读取到同目录下的 nexus.mv.db
docker run --rm -it --network=nginx_default \
  -v $(pwd)/data/db:/db \
  -w /db \
  sonatype/nexus3:3.91.1 \
  java -Xmx2G -Xms2G -XX:+UseG1GC -jar nexus-db-migrator-3.91.1-04.jar \
  --migration_type=h2_to_postgres \
  --db_url="jdbc:postgresql://nexus-postgresql:5432/nexus?user=nexus&password=nexus_password"

# 5. 迁移完成后，重命名原有 H2 数据库文件作为备份，并防止 Nexus 重启后误读
mv data/db/nexus.mv.db data/db/nexus.mv.db.bak

# 6. 重新启动应用了新 PostgreSQL 环境变量的 Nexus 容器
docker compose up -d nexus
```

Nexus 启动后，可以通过查看容器日志来确认是否已成功连接并启用了外部 PostgreSQL 数据库：

```bash
docker logs -f nexus | grep PostgreSQL
```

如果日志中出现类似 `Loaded 'nexus' data store configuration defaults (PostgreSQL)` 的输出，则说明数据迁移及配置切换均已成功。