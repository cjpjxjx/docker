# Migrating to a New Database

> Use [Instance Migrator](instance-migrator.html) if you are on OrientDB and wish to migrate to a self-hosted instance (3.90.2+), or to Sonatype Cloud.

This page documents Database Migrator, the database-level migration utility for self-hosted Nexus Repository. Use Database Migrator when you need to change the database used by an existing self-hosted deployment. Database Migrator supports the following database migration scenarios:

- H2 to PostgreSQL
- PostgreSQL to H2
- OrientDB to H2
- OrientDB to PostgreSQL

> The documented workflows require you to shut down Nexus Repository during migration.

Download the latest database migrator utility to receive the latest performance improvements.

See [Download the Latest Database Migrator Utility](download.html#nexus-repositorytm-database-migrator)

## Considerations Before Migrating

Review the following considerations before migrating:

- Database migration is one-way and non-destructive** The original Orient database is not changed and may be used as a recovery point. The migrator does not support migrating back to OrientDB from H2 or PostgreSQL. Running the migrator again overwrites any data in the target database.
- Avoid performing maintenance steps during the migration** Run the database migration in the same environment to avoid complications and to simplify recovery when something goes wrong. Use the same version you were using before the migration. Migrating directly to the cloud from on-premises is not supported.
- Test the migration before running in production** We recommended performing a test migration using a backup of your production instance. Be aware that a backup instance connecting to cloud blob stores may still be connected to production data. The migration may skip artifacts from the source database when they are not found in the file reference. Consult the migration log files to valid the contents that was migrated. Searching and cleanup works differently in H2 and PostgreSQL databases. Evaluate that cleanup policies identify the correct components for cleanup.
- Review unsupported formats and custom plug-ins** PostgreSQL and H2 do not support Bower or the community formats (e.g., APK, Composer, CPAN, Puppet). A subset of Nuget v2 protocol does not work the same as from OrientDB. Unsupported formats are not migrated. Custom plugins that interact with the database, assets, or components may no longer work with the new databases. Groovy scripting is not supported in later versions.

> Database Migrator Utility does not migrate **Repository – Export assets** and **Repository – Import external files** tasks. These tasks reference environment‑specific paths that change between instances. Recreate them in the new instance if the workflow requires Import/Export functionality.

## Migration Environment Prerequisite Requirements

Review the requirements below for the database migration:

- **Unless you are still on OrientDB, you must first upgrade to the latest version of Nexus Repository** A new version of the migration is released for every version of Nexus Repository to take advantage of improvements and bug fixes to the migration process. Only the latest version of the migration is available for download to avoid support issues. Upgrade to the latest supported version of Nexus Repository for your database. If you are using OrientDB, then you must upgrade to the latest 3.70.x version and use the database migrator that is associated with that version. See [Upgrading to Nexus Repository 3.71.0 and Beyond](upgrading-to-nexus-repository-3-71-0-and-beyond.html) and [Nexus Repository 3.70.x Downloads with OrientDB](orientdb-downloads.html)
- **The database migrator requires OpenJDK** The database migrator does not support Oracle JDK.
- **Migrating from OrientDB requires using Java 8 or 11** Migrating off of OrientDB will require using the 3.70.x database migrator available at [Nexus Repository 3.70.x Downloads with OrientDB](orientdb-downloads.html). OrientDB does not support Java 17+, so you will need to upgrade your instance's Java version once you have migrated.
- **The migrator requires at least 16GB of available RAM**
- **The migrator requires three times the disk space as your instance's database directory (minimum 10 GB)** The `$data-dir/db` directory and the temp directory must have enough space for both the backup and the extracted backup to the tmp directory.
- **If migrating to PostgreSQL, the target database must contain a schema with the correct user permissions** The Nexus Repository database user requires `CREATE` and `USAGE` permissions on the specified schema, which must also be on the `search_path` for that user. If your database administrator provisions a database without a schema, you must create the schema manually before running the migrator.

## Post-Migration Tasks

These tasks are critical to the proper functioning of the repository after the migration process and may take a notable amount of time to complete.

**Do not restart your instance** while the post-migration tasks are running to avoid damaging your browse and search index.

1. Run the following tasks manually when using these formats:

   ```
   Rebuild Helm metadata
   ```

2. After migrating your database, Nexus Repository runs the following tasks:

   ```
   Rebuild repository browse
   Rebuild repository search
   ```

3. Use the below states in the task log to follow along with the post-migration process: 

   ```
   repository.rebuild-index 
   repository.search.update 
   create.browse.nodes
   repository.yum.rebuild.metadata
   component.normalize.version
   repository.metrics.blob.size.copy
   file.blobstore.metrics.datastore.migration
   ```

4. When migrating to H2, keep the `nexus.mv.db` and `nexus.trace.db` (if present). All other files and folders in `db` are legacy OrientDB data and can be removed. For PostgreSQL migrations, the entire `db` directory is no longer needed. Before deleting, it is strongly recommended to compress and move the `db` directory to a backup location.

## Migrating From H2 to PostgreSQL

The section covers migrating Nexus Repository instance with an embedded H2 database to an external PostgreSQL database.

1. Perform a backup of the H2 database using the `Admin - Backup H2 Database` task.

2. Download the Database Migrator binary and copy it into the `$data-dir/db` directory. See [Directories](directories.html) for details on locating the `$data-dir`.

3. A PostgreSQL server must be configured for Nexus Repository to connect to. Follow the instructions in [Install Nexus Repository with PostgreSQL](install-nexus-repository-with-a-postgresql-database.html). Do not start Nexus Repository with the PostgreSQL configuration until after the migration is complete. 

   > If your database administrator provisions a database without a schema, you must create the schema manually and grant the required permissions to the Nexus Repository database user before proceeding:

   ```
   CREATE SCHEMA <schema_name>;
   GRANT USAGE, CREATE ON SCHEMA <schema_name> TO <nexus_user>;
   ```

   If you use a schema name other than `nexus`, update the `currentSchema` parameter in the `--db_url` argument in Step 5 accordingly.

4. Shut down Nexus Repository.

5. Update the `db_url` in the following command using your PostgreSQL configuration. 

   ```
   java -Xmx16G -Xms16G -XX:+UseG1GC -XX:MaxDirectMemorySize=28672M \ 
   -jar nexus-db-migrator-*.jar \ 
   --migration_type=h2_to_postgres \ 
   --db_url="jdbc:postgresql://<database URL>:<port>/nexus?user=postgresUser&password=secretPassword&currentSchema=nexus"
   ```

   **This command must run in the `$data-dir/db` directory.**

6. Run the following command on the PostgreSQL database to reclaim storage occupied by obsoleted tuples left from the migration. 

   ```
   VACUUM(FULL, ANALYZE, VERBOSE);
   ```

7. Start Nexus Repository.

   [Post-migration tasks](migrating-to-a-new-database.html#post-migration-tasks) must be completed before you can upgrade your Nexus Repository version.

### Optional Parameters

You may not need these optional parameters unless directed to by Sonatype support.

- `-y, --yes`: Parameter to skip waiting for user input and assume a "yes" response to the initial warning.
- `--content_migration=false` Parameter to only migrate the security and config tables: users, roles, and blobstore configuration. Repository content is not migrated.
- `--shutdown_compact=false` Parameter to disable H2 Content DB compression; this is set to true by default.

Migrating From PostgreSQL to H2**

This topic covers migrating from a PostgreSQL database to an embedded H2 database.
