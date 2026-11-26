# Cụm CSDL Phân Tán MySQL 8.0 (1 Master – 2 Slave) — Quản Lý Bán Hàng Siêu Thị

Dự án triển khai kiến trúc nhân bản cơ sở dữ liệu **1 Primary (Master) – 2 Replica (Slave)** trên nền **MySQL 8.0 & Docker Compose**, áp dụng cho bài toán **Quản lý bán hàng chuỗi siêu thị (`supermarket_db`)** ở quy mô **2.620.520 bản ghi/node** (~7,86 triệu bản ghi trên toàn cụm). Hệ thống cấu hình định danh giao dịch toàn cục **GTID (`Auto_Position = 1`)**, cơ chế ghi bền vững **Crash-Safety (`sync_binlog = 1`, `innodb_flush_log_at_trx_commit = 1`)**, khóa bảo vệ toàn vẹn **Super Read-Only** trên các máy Slave và bộ **8 kịch bản kiểm thử tự động** từ đồng bộ DML, ACID Rollback, Online DDL, đo độ trễ tải cao cho tới chuyển đổi dự phòng sự cố (Failover).

---

## 1. Kiến trúc cổng kết nối Localhost & Tài khoản

Toàn bộ cụm chạy cô lập trong mạng nội bộ Docker `dbms-net` và ánh xạ trực tiếp ra `localhost` (`127.0.0.1`) của máy cá nhân:

| Vai trò | Tên Container | Địa chỉ từ Máy thật (Host) | Quyền hạn | Cấu hình cốt lõi |
| :--- | :--- | :--- | :--- | :--- |
| **Master (Primary)** | `mysql-master` | `127.0.0.1:3306` | `Read / Write` | `server-id=1`, GTID ON, `sync_binlog=1`, ROW binlog |
| **Slave 1 (Replica)** | `mysql-slave-1` | `127.0.0.1:3307` | `Super Read-Only` | `server-id=2`, `Auto_Position=1`, `log_replica_updates=ON` |
| **Slave 2 (Replica)** | `mysql-slave-2` | `127.0.0.1:3308` | `Super Read-Only` | `server-id=3`, `Auto_Position=1`, `log_replica_updates=ON` |

* **Database:** `supermarket_db`
* **Tài khoản quản trị (trên cả 3 node):** User `root` / Password `rootpassword`
* **Tài khoản luồng nhân bản nội bộ:** User `repl_user` / Password `repl_password`

---

## 2. Yêu cầu tiên quyết & Chuẩn bị theo Hệ điều hành

### 2.1. Công cụ cần có
* **Ubuntu / Debian / Linux:** Đã cài đặt `Docker Engine` và `Docker Compose v2` (`docker compose version`), dung lượng ổ cứng trống tối thiểu **4 GB**.
* **Windows 10 / 11:** Đã cài đặt **Docker Desktop** (đang bật ở chế độ Linux Containers / WSL2 backend) và **Git for Windows** (đi kèm **Git Bash**) hoặc **WSL2 (Ubuntu)**, dung lượng ổ cứng trống tối thiểu **4 GB**.

### 2.2. Giải phóng cổng `3306`, `3307`, `3308` trên `localhost` (Nếu bị trùng)
Nếu máy tính của bạn đang cài sẵn MySQL Server, MariaDB hoặc XAMPP chạy ngầm ở cổng `3306`, hãy tạm dừng dịch vụ đó trước khi bật Docker:

* **Trên Ubuntu / Linux:**
  ```bash
  # Kiểm tra xem cổng 3306/3307/3308 có đang bị chiếm không
  sudo ss -tlnp | grep -E '3306|3307|3308'

  # Nếu có dịch vụ mysql/mariadb trên máy thật đang chạy thì tạm dừng:
  sudo systemctl stop mysql mariadb 2>/dev/null || true
  ```

* **Trên Windows (Mở PowerShell với quyền Administrator):**
  ```powershell
  # Kiểm tra cổng 3306/3307/3308
  netstat -ano | findstr ":3306 :3307 :3308"

  # Tạm dừng dịch vụ MySQL trên Windows (ví dụ MySQL80) nếu đang chạy:
  Get-Service MySQL* -ErrorAction SilentlyContinue | Stop-Service -Force
  ```

### 2.3. Bước chuẩn hóa môi trường riêng cho máy Windows
Nếu bạn đang thao tác trên **Windows**:
1. Khuyến nghị mở **Git Bash** hoặc **WSL2 Terminal** ngay tại thư mục gốc `DBMS_Cluster`.
2. Chạy lệnh dưới đây một lần duy nhất để tắt tự động đổi đường dẫn của Git Bash và đảm bảo các tệp `.sh`, `.cnf`, `.sql` chuẩn ký tự xuống dòng `LF` của Linux:
   ```bash
   export MSYS_NO_PATHCONV=1
   sed -i 's/\r$//' config/master/my.cnf config/slave1/my.cnf config/slave2/my.cnf scripts/*.sh scripts/tests/*.sh
   ```
   *(Nếu bạn chỉ dùng **Windows PowerShell**, xem cú pháp gọi lệnh ở Mục 4.2 bên dưới).*

---

## 3. Hướng dẫn Thiết lập Cụm CSDL từ Con số 0

Thực hiện tuần tự các bước sau tại thư mục gốc `DBMS_Cluster`:

### Bước 1: Khởi chạy 3 Container MySQL 8.0
```bash
docker compose up -d
```
Chờ khoảng 10–15 giây để Docker tải ảnh `mysql:8.0` (lần đầu) và khởi tạo 3 container `mysql-master`, `mysql-slave-1`, `mysql-slave-2`. Kiểm tra bằng `docker compose ps`.

### Bước 2: Thiết lập Nhân bản GTID & Khởi tạo Dữ liệu (Chọn 1 trong 2 chế độ)

#### Chế độ A (Khuyến nghị — Chuẩn báo cáo): Thiết lập GTID + Nạp tự động 2.620.520 bản ghi/node
Kịch bản `04_seed_million_records.sh` đã tích hợp sẵn **toàn bộ quy trình từ A–Z**: tự chờ MySQL sẵn sàng, tạo tài khoản `repl_user`, bắt tay GTID cho cả 2 Slave, nạp lược đồ 6 bảng và sinh tự động **2.620.520 bản ghi** trên Master (~45 giây) rồi đồng bộ sang cả 2 Slave:

* **Trên Ubuntu / Linux / WSL2 / Git Bash:**
  ```bash
  MSYS_NO_PATHCONV=1 bash ./scripts/04_seed_million_records.sh
  ```
* **Trên Windows PowerShell:**
  ```powershell
  & "C:\Program Files\Git\bin\bash.exe" -c "MSYS_NO_PATHCONV=1 bash ./scripts/04_seed_million_records.sh"
  ```

#### Chế độ B (Khởi tạo siêu tốc ~5 giây cho máy cấu hình thấp): Dữ liệu mẫu nhỏ gọn
Nếu chỉ muốn dựng nhanh cấu trúc 6 bảng với bộ dữ liệu mẫu nhỏ trong `sql/` mà không cần sinh hàng triệu dòng:

* **Trên Ubuntu / Linux / WSL2 / Git Bash:**
  ```bash
  MSYS_NO_PATHCONV=1 bash ./scripts/01_setup_replication.sh
  docker exec -i -e MYSQL_PWD=rootpassword mysql-master mysql -uroot < ./sql/01_schema.sql
  docker exec -i -e MYSQL_PWD=rootpassword mysql-master mysql -uroot < ./sql/02_sample_data.sql
  ```
* **Trên Windows PowerShell:**
  ```powershell
  & "C:\Program Files\Git\bin\bash.exe" -c "MSYS_NO_PATHCONV=1 bash ./scripts/01_setup_replication.sh && docker exec -i -e MYSQL_PWD=rootpassword mysql-master mysql -uroot < ./sql/01_schema.sql && docker exec -i -e MYSQL_PWD=rootpassword mysql-master mysql -uroot < ./sql/02_sample_data.sql"
  ```

### Bước 3: Đối soát xác nhận cả 3 Node đã đồng bộ 100%
* **Trên Ubuntu / Linux / WSL2 / Git Bash:**
  ```bash
  MSYS_NO_PATHCONV=1 bash ./scripts/02_verify_replication.sh
  ```
* **Trên Windows PowerShell:**
  ```powershell
  & "C:\Program Files\Git\bin\bash.exe" -c "MSYS_NO_PATHCONV=1 bash ./scripts/02_verify_replication.sh"
  ```
Khi màn hình in ra số lượng bản ghi của cả 6 bảng (`categories`, `products`, `customers`, `employees`, `orders`, `order_details`) khớp nhau tuyệt đối trên **MASTER**, **SLAVE 1** và **SLAVE 2** (ở Chế độ A là `20 / 20000 / 100000 / 500 / 500000 / 2000000`), hệ thống đã sẵn sàng 100% để chạy kiểm thử!

---

## 4. Hướng dẫn Thực hiện Ngay 8 Ca Kiểm thử Thực nghiệm

### 4.1. Chạy trên Ubuntu / Linux / macOS / WSL2 / Git Bash
```bash
# (Chỉ cần thiết trên Git Bash Windows)
export MSYS_NO_PATHCONV=1

# Ca 1: Đồng bộ dữ liệu bán hàng xuôi (INSERT, UPDATE, DELETE)
bash ./scripts/tests/01_test_dml_replication.sh

# Ca 2: Bảo vệ toàn vẹn dữ liệu trên Slave bằng khóa ghi Super Read-Only (ERROR 1290)
bash ./scripts/tests/02_test_readonly_protection.sh

# Ca 3: Gián đoạn mạng trên Slave 1 và tự động đồng bộ bù qua GTID
bash ./scripts/tests/03_test_fault_tolerance.sh

# Ca 4: Đảm bảo tính nguyên tố ACID — ROLLBACK không rò rỉ dữ liệu rác sang Slave
bash ./scripts/tests/04_test_transaction_rollback.sh

# Ca 5: Nâng cấp cấu trúc bảng trực tuyến (Online DDL: thêm cột expiry_date)
bash ./scripts/tests/05_test_online_ddl.sh

# Ca 6: Đo lường độ trễ Seconds_Behind_Source dưới tải 500 giao dịch liên tiếp
bash ./scripts/tests/06_test_replication_lag.sh

# Ca 8: Đối soát quy mô 2,62 triệu bản ghi, dung lượng InnoDB & tốc độ tra cứu POS (< 1ms)
bash ./scripts/tests/08_test_million_scale_benchmark.sh

# Ca 7 (CHẠY SAU CÙNG): Đánh sập Master, thăng hạng Slave 1 làm Master mới & điều hướng Slave 2
bash ./scripts/tests/07_test_failover_disaster_recovery.sh

# Khôi phục cụm về lại kiến trúc 1 Master - 2 Slave ban đầu ngay sau khi chạy xong Ca 7:
bash ./scripts/tests/07_restore_original_cluster.sh
```

### 4.2. Chạy trực tiếp từ Windows PowerShell (Không cần đổi cửa sổ Terminal)
Nếu đang đứng trong **Windows PowerShell**, bạn chạy từng ca bằng mẫu lệnh sau:
```powershell
$BASH = "C:\Program Files\Git\bin\bash.exe"

& $BASH -c "MSYS_NO_PATHCONV=1 bash ./scripts/tests/01_test_dml_replication.sh"
& $BASH -c "MSYS_NO_PATHCONV=1 bash ./scripts/tests/02_test_readonly_protection.sh"
& $BASH -c "MSYS_NO_PATHCONV=1 bash ./scripts/tests/03_test_fault_tolerance.sh"
& $BASH -c "MSYS_NO_PATHCONV=1 bash ./scripts/tests/04_test_transaction_rollback.sh"
& $BASH -c "MSYS_NO_PATHCONV=1 bash ./scripts/tests/05_test_online_ddl.sh"
& $BASH -c "MSYS_NO_PATHCONV=1 bash ./scripts/tests/06_test_replication_lag.sh"
& $BASH -c "MSYS_NO_PATHCONV=1 bash ./scripts/tests/08_test_million_scale_benchmark.sh"

# Chạy Ca 7 Failover và khôi phục lại cụm gốc:
& $BASH -c "MSYS_NO_PATHCONV=1 bash ./scripts/tests/07_test_failover_disaster_recovery.sh"
& $BASH -c "MSYS_NO_PATHCONV=1 bash ./scripts/tests/07_restore_original_cluster.sh"
```

---

## 5. Cấu trúc thư mục dự án

```text
DBMS_Cluster/
├── config/
│   ├── master/my.cnf                         # Cấu hình Master: GTID, Crash-Safety, Binary Log
│   ├── slave1/my.cnf                         # Cấu hình Slave 1: GTID, Super Read-Only, Relay Log
│   └── slave2/my.cnf                         # Cấu hình Slave 2: GTID, Super Read-Only, Relay Log
├── sql/
│   ├── 01_schema.sql                         # Lược đồ 6 bảng CSDL siêu thị chuẩn InnoDB (UTF8MB4)
│   └── 02_sample_data.sql                    # Bộ dữ liệu mẫu khởi tạo nhanh
├── scripts/
│   ├── 01_setup_replication.sh               # Tự động tạo user & bắt tay GTID Replication
│   ├── 02_verify_replication.sh              # Đối soát số lượng bản ghi 6 bảng trên cả 3 node
│   ├── 04_seed_million_records.sh            # Thiết lập cụm & sinh 2.620.520 bản ghi/node
│   └── tests/                                # Bộ 8 kịch bản kiểm thử chuyên sâu độc lập
│       ├── 01_test_dml_replication.sh        # Ca 1: Đồng bộ INSERT, UPDATE, DELETE xuôi
│       ├── 02_test_readonly_protection.sh    # Ca 2: Chặn ghi trái phép trên Slave (ERROR 1290)
│       ├── 03_test_fault_tolerance.sh        # Ca 3: Đứt mạng tạm thời & tự bù qua GTID
│       ├── 04_test_transaction_rollback.sh   # Ca 4: Toàn vẹn giao dịch ACID & lệnh ROLLBACK
│       ├── 05_test_online_ddl.sh             # Ca 5: Nâng cấp bảng trực tuyến (Online DDL)
│       ├── 06_test_replication_lag.sh        # Ca 6: Đo độ trễ dưới tải 500 đơn hàng liên tiếp
│       ├── 07_test_failover_disaster_recovery.sh # Ca 7: Thăng hạng Slave 1 khi Master sập nguồn
│       ├── 07_restore_original_cluster.sh    # Khôi phục kiến trúc 1 Master - 2 Slave sau Ca 7
│       └── 08_test_million_scale_benchmark.sh # Ca 8: Đối soát 2,62 triệu dòng & đo hiệu năng POS
├── report/
│   ├── main.tex                              # Mã nguồn báo cáo LaTeX
│   ├── main.pdf                              # Bản báo cáo PDF hoàn chỉnh
│   └── images/                               # Ảnh chụp đối chứng thực thi Terminal (Ca 1 - Ca 8)
├── .gitattributes                            # Cố định chuẩn xuống dòng LF đa hệ điều hành
├── docker-compose.yml                        # Định nghĩa hạ tầng 3 container & mạng dbms-net
└── README.md                                 # Tài liệu hướng dẫn thiết lập & vận hành
```

---

## 6. Xử lý sự cố thường gặp & Dọn dẹp hệ thống

* **Lỗi `Bind for 0.0.0.0:3306 failed: port is already allocated`:** Cổng `3306` trên `localhost` đang bị chiếm bởi MySQL/XAMPP cài trên máy thật. Thực hiện lệnh dừng dịch vụ ở **Mục 2.2** rồi chạy lại `docker compose up -d`.
* **Lỗi `$'\r': command not found` hoặc MySQL bỏ qua `my.cnf` trên Windows:** Chạy lệnh `sed -i 's/\r$//' ...` ở **Mục 2.3**, sau đó chạy `docker compose restart`.
* **Dừng tạm thời cụm (giữ nguyên 2,62 triệu bản ghi cho lần mở sau):**
  ```bash
  docker compose stop
  ```
* **Xóa sạch toàn bộ container và dữ liệu ổ đĩa ảo (Reset trắng hoàn toàn):**
  ```bash
  docker compose down -v
  ```
