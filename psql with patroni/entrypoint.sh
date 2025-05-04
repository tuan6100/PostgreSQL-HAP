#!/bin/bash

if [[ $UID -ge 10000 ]]; then
    GID=$(id -g)
    sed -e "s/^postgres:x:[^:]*:[^:]*:/postgres:x:$UID:$GID:/" /etc/passwd > /tmp/passwd
    cat /tmp/passwd > /etc/passwd
    rm /tmp/passwd
fi

cat > /home/postgres/patroni.yml <<__EOF__
bootstrap:
  dcs:
    postgresql:
      use_pg_rewind: true
      pg_hba:
        - local all all trust
        - host all all 0.0.0.0/0 scram-sha-256
        - host replication ${PATRONI_REPLICATION_USERNAME} ${PATRONI_KUBERNETES_POD_IP}/16 scram-sha-256
        - host replication ${PATRONI_REPLICATION_USERNAME} 127.0.0.1/32 scram-sha-256
  initdb:
    - auth-host: scram-sha-256
    - auth-local: trust
    - encoding: UTF8
    - locale: en_US.UTF-8
    - data-checksums
restapi:
  connect_address: '${PATRONI_KUBERNETES_POD_IP}:8008'
postgresql:
  connect_address: '${PATRONI_KUBERNETES_POD_IP}:5432'
  authentication:
    superuser:
      password: '${PATRONI_SUPERUSER_PASSWORD}'
    replication:
      password: '${PATRONI_REPLICATION_PASSWORD}'
  parameters:
    listen_addresses: '*'
    max_connections: 300
    shared_buffers: '256MB'
    dynamic_shared_memory_type: 'posix'
    max_wal_size: '2GB'
    min_wal_size: '512MB'
    shared_preload_libraries: 'pg_stat_statements'
    log_directory: '/home/postgres/pgdata/pgroot/data/pg_log'
    log_file_mode: '0644'
    log_filename: 'postgresql-%Y-%m-%d.log'
    log_line_prefix: '%m [%p] %q%u@%d '
    log_rotation_age: '1d'
    log_duration: 'on'
    log_statement: 'none'
    log_min_duration_statement: 1
    log_checkpoints: 'on'
    log_connections: 'off'
    log_disconnections: 'off'
    logging_collector: 'on'
    log_destination: 'csvlog'
__EOF__


unset PATRONI_SUPERUSER_PASSWORD PATRONI_REPLICATION_PASSWORD

exec /usr/bin/python3 /usr/local/bin/patroni /home/postgres/patroni.yml

#!/bin/bash
