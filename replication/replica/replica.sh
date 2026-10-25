#!/bin/bash
set -e

if [ ! -s "$PGDATA/PG_VERSION" ]; then
    until pg_isready -h primary -p 5432 -U postgres; do
        sleep 2
    done

    PGPASSWORD=replica_pass gosu postgres pg_basebackup -h primary -p 5432 -D "$PGDATA" -U replicator -Fp -Xs -P -R

    printf 'primary:5432:*:replicator:replica_pass\n' > /var/lib/postgresql/.pgpass
    chown postgres:postgres /var/lib/postgresql/.pgpass
    chmod 600 /var/lib/postgresql/.pgpass
fi

exec docker-entrypoint.sh postgres
