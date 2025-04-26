#!/bin/bash

# Define variables
USER="tuan"
NODE_IP="localhost"
MASTER_PORT="5432"
SLAVE0_PORT="30432"
SLAVE1_PORT="30433"
SLAVE2_PORT="30434"
TEST_DB="test"

echo "=== PostgreSQL Benchmark Testing ==="
echo "Master: $NODE_IP:$MASTER_PORT"
echo "Slave 0: $NODE_IP:$SLAVE0_PORT"
echo "Slave 1: $NODE_IP:$SLAVE1_PORT"
echo "Slave 2: $NODE_IP:$SLAVE2_PORT"

# Get maximum connection limit
echo "Checking max_connections..."
MAX_CONN=$(PGPASSWORD=20226100 psql -U $USER -h $NODE_IP -p $MASTER_PORT -c "SHOW max_connections;" -t | tr -d ' ')
SAFE_CONN=$(($MAX_CONN * 80 / 100))
echo "Max connections: $MAX_CONN, Safe connections: $SAFE_CONN"

# Create test database if not exists
echo "Creating test database..."
PGPASSWORD=20226100 psql -U $USER -h $NODE_IP -p $MASTER_PORT -c "CREATE DATABASE $TEST_DB;" 2>/dev/null
PGPASSWORD=20226100 pgbench -U $USER -h $NODE_IP -p $MASTER_PORT -i -s 10 $TEST_DB

# Test 1: Write-heavy load on master
echo -e "\n=== Test 1: Write-heavy load on master (100 clients) ==="
PGPASSWORD=20226100 pgbench -U $USER -h $NODE_IP -p $MASTER_PORT -c 100 -j 4 -T 30 -P 10 $TEST_DB

# Test 2: Read-only load on slave 0
echo -e "\n=== Test 2: Read-only load on slave 0 (100 clients) ==="
PGPASSWORD=20226100 pgbench -U $USER -h $NODE_IP -p $SLAVE0_PORT -c 100 -j 4 -T 30 -P 10 -S $TEST_DB

# Test 3: Read-only load distributed across all slaves
echo -e "\n=== Test 3: Distributed read load across all slaves (100 clients each) ==="
PGPASSWORD=20226100 pgbench -U $USER -h $NODE_IP -p $SLAVE0_PORT -c 100 -j 4 -T 30 -P 10 -S -N $TEST_DB &
PGBENCH_PID1=$!
PGPASSWORD=20226100 pgbench -U $USER -h $NODE_IP -p $SLAVE1_PORT -c 100 -j 4 -T 30 -P 10 -S -N $TEST_DB &
PGBENCH_PID2=$!
PGPASSWORD=20226100 pgbench -U $USER -h $NODE_IP -p $SLAVE2_PORT -c 100 -j 4 -T 30 -P 10 -S -N $TEST_DB &
PGBENCH_PID3=$!

wait $PGBENCH_PID1 $PGBENCH_PID2 $PGBENCH_PID3

# Test 4: Maximum safe load on master
echo -e "\n=== Test 4: Maximum safe load on master ($SAFE_CONN clients) ==="
PGPASSWORD=20226100 pgbench -U $USER -h $NODE_IP -p $MASTER_PORT -c $SAFE_CONN -j 8 -T 30 -P 10 $TEST_DB

# Test 5: Mixed read-write workload
echo -e "\n=== Test 5: Mixed read-write workload (70% select, 30% update) ==="
cat > custom_script.sql << EOF
\set aid random(1, 100000 * :scale)
\set bid random(1, 1 * :scale)
\set tid random(1, 10 * :scale)
\set delta random(-5000, 5000)
SELECT abalance FROM pgbench_accounts WHERE aid = :aid;
SELECT abalance FROM pgbench_accounts WHERE aid = :aid;
SELECT abalance FROM pgbench_accounts WHERE aid = :aid;
SELECT abalance FROM pgbench_accounts WHERE aid = :aid;
SELECT abalance FROM pgbench_accounts WHERE aid = :aid;
SELECT abalance FROM pgbench_accounts WHERE aid = :aid;
SELECT abalance FROM pgbench_accounts WHERE aid = :aid;
UPDATE pgbench_accounts SET abalance = abalance + :delta WHERE aid = :aid;
UPDATE pgbench_accounts SET abalance = abalance + :delta WHERE aid = :aid;
UPDATE pgbench_accounts SET abalance = abalance + :delta WHERE aid = :aid;
EOF

PGPASSWORD=20226100 pgbench -U $USER -h $NODE_IP -p $MASTER_PORT -c 100 -j 4 -T 30 -P 10 -f custom_script.sql $TEST_DB

# Clean up
rm -f custom_script.sql

echo "Benchmarking complete!"