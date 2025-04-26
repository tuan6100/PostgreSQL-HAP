Khởi tạo một database phục vụ quá trình test:
```bash
psql -U $USER -c "CREATE DATABASE test"
pgbench -U $USER -i test
```
Các tham số của pgbench:
    -c: Số lượng client giả lập
    -j: Số lượng thread
    -t: Số lượng transaction mỗi client
    -T: Thời gian chạy (giây)
    -s: Hệ số scale cho việc khởi tạo DB

Các kịch bản kiểm tra

1. Kiểm tra đọc/ghi đồng thời
```Bash
MAX_CONN=$(psql -U postgres -c "SHOW max_connections;" -t | tr -d ' ')
pgbench -U $USER -c $MAX_CONN -j 8 -T 60 -P 10 test
```
Kịch bản này mô phỏng số lượng kết nối đồng thời lớn nhất với 8 thread worker.
Kết quả thu được:
```
progress: 10.0 s, 1410.2 tps, lat 204.007 ms stddev 250.695, 0 failed
progress: 20.0 s, 1431.0 tps, lat 208.340 ms stddev 253.277, 0 failed
progress: 30.0 s, 1323.1 tps, lat 226.643 ms stddev 311.789, 0 failed
progress: 40.0 s, 1352.2 tps, lat 219.710 ms stddev 291.830, 0 failed
progress: 50.0 s, 1466.5 tps, lat 206.949 ms stddev 258.229, 0 failed
progress: 60.0 s, 1349.0 tps, lat 221.779 ms stddev 300.197, 0 failed
scaling factor: 1
query mode: simple
number of clients: 300
number of threads: 8
maximum number of tries: 1
duration: 60 s
number of transactions actually processed: 83622
number of failed transactions: 0 (0.000%)
latency average = 215.654 ms
latency stddev = 279.371 ms
initial connection time = 194.807 ms
tps = 1386.079060 (without initial connection time) 
```
Đánh giá kết quả: