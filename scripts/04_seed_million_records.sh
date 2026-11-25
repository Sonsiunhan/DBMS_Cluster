#!/bin/bash
set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}============================================================================${NC}"
echo -e "${BLUE}   NÂNG CẤP QUY MÔ CSDL SIÊU THỊ LÊN 2,62 TRIỆU BẢN GHI (MILLION-SCALE)    ${NC}"
echo -e "${BLUE}============================================================================${NC}\n"

# 1. Đảm bảo cả 3 container đang chạy và khôi phục chuẩn mô hình 1 Master - 2 Slave
echo -e "${YELLOW}>>> BƯỚC 1: Chuẩn hóa trạng thái cụm 1 Master - 2 Slave và làm sạch GTID <<<${NC}"
docker start mysql-master mysql-slave-1 mysql-slave-2 >/dev/null

for node in mysql-master mysql-slave-1 mysql-slave-2; do
    until docker exec "$node" mysqladmin ping -uroot -prootpassword >/dev/null 2>&1; do
        sleep 1
    done
done

# Reset sạch lịch sử GTID cũ (nếu từng chạy Ca 7 Failover) để 3 node đồng nhất từ GTID :1
docker exec mysql-slave-1 mysql -uroot -prootpassword -e "
STOP REPLICA;
RESET REPLICA ALL;
SET GLOBAL super_read_only = OFF;
SET GLOBAL read_only = OFF;
DROP DATABASE IF EXISTS supermarket_db;
CREATE DATABASE supermarket_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
RESET MASTER;
SET GLOBAL read_only = ON;
SET GLOBAL super_read_only = ON;
" 2>/dev/null

docker exec mysql-slave-2 mysql -uroot -prootpassword -e "
STOP REPLICA;
RESET REPLICA ALL;
SET GLOBAL super_read_only = OFF;
SET GLOBAL read_only = OFF;
DROP DATABASE IF EXISTS supermarket_db;
CREATE DATABASE supermarket_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
RESET MASTER;
SET GLOBAL read_only = ON;
SET GLOBAL super_read_only = ON;
" 2>/dev/null

docker exec mysql-master mysql -uroot -prootpassword -e "
SET GLOBAL super_read_only = OFF;
SET GLOBAL read_only = OFF;
DROP DATABASE IF EXISTS supermarket_db;
CREATE DATABASE supermarket_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'repl_user'@'%' IDENTIFIED WITH mysql_native_password BY 'repl_password';
GRANT REPLICATION SLAVE ON *.* TO 'repl_user'@'%';
FLUSH PRIVILEGES;
RESET MASTER;
" 2>/dev/null

for slave in mysql-slave-1 mysql-slave-2; do
    docker exec "$slave" mysql -uroot -prootpassword -e "
    CHANGE REPLICATION SOURCE TO
      SOURCE_HOST = 'mysql-master',
      SOURCE_USER = 'repl_user',
      SOURCE_PASSWORD = 'repl_password',
      SOURCE_PORT = 3306,
      SOURCE_AUTO_POSITION = 1;
    START REPLICA;
    " 2>/dev/null
done

echo -e "${GREEN}[OK] Cụm 1 Master - 2 Slave đã kết nối thông suốt với GTID sạch.${NC}"

# 2. Nạp lược đồ chuẩn và dữ liệu mẫu gốc (giữ nguyên các ID gốc cho bộ 7 ca test)
echo -e "\n${YELLOW}>>> BƯỚC 2: Khởi tạo lược đồ 6 bảng và tập dữ liệu mẫu nền tảng <<<${NC}"
docker exec -i mysql-master mysql -uroot -prootpassword supermarket_db < "$PROJECT_ROOT/sql/01_schema.sql" 2>/dev/null
docker exec -i mysql-master mysql -uroot -prootpassword supermarket_db < "$PROJECT_ROOT/sql/02_sample_data.sql" 2>/dev/null
echo -e "${GREEN}[OK] Đã nạp lược đồ 01_schema.sql và dữ liệu gốc 02_sample_data.sql.${NC}"

# 3. Sinh 2.620.520 bản ghi theo lô lớn (Set-based Batch Insert) trên Master
echo -e "\n${YELLOW}>>> BƯỚC 3: Sinh 2.620.520 bản ghi nghiệp vụ siêu thị trên Master <<<${NC}"
SEED_START_NS=$(date +%s%N)

echo -e "${CYAN}  [3.1] Tạo bảng chuỗi số phụ trợ và nạp Danh mục (20), Nhân viên (500), Sản phẩm (20.000)...${NC}"
docker exec mysql-master mysql -uroot -prootpassword supermarket_db -e "
DROP TABLE IF EXISTS _seq_1000;
CREATE TABLE _seq_1000 (n INT PRIMARY KEY) ENGINE=InnoDB;

INSERT INTO _seq_1000 (n)
WITH RECURSIVE seq AS (
    SELECT 0 AS n
    UNION ALL
    SELECT n + 1 FROM seq WHERE n < 999
)
SELECT n FROM seq;

-- 1. Mở rộng categories từ 5 -> 20 ngành hàng
INSERT INTO categories (category_name, description) VALUES
('Sữa & Chế phẩm từ sữa', 'Sữa tươi tiệt trùng, sữa chua, phô mai, bơ thực vật'),
('Thực phẩm đông lạnh', 'Cá viên, xúc xích, há cảo, kem lạnh đóng hộp'),
('Mì, Phở, Cháo ăn liền', 'Mì gói, phở khô, bún khô, miến dong đóng gói'),
('Bánh mì & Bánh tươi', 'Bánh mì sandwich, bánh ngọt nướng trong ngày'),
('Trái cây nhập khẩu', 'Táo Mỹ, nho Úc, kiwi New Zealand, lê Hàn Quốc'),
('Chăm sóc cá nhân', 'Kem đánh răng, bàn chải, sữa rửa mặt, lăn khử mùi'),
('Chăm sóc Mẹ & Bé', 'Tã bỉm trẻ em, sữa bột công thức, khăn ướt an toàn'),
('Đồ gia dụng nhà bếp', 'Nồi chảo chống dính, hộp đựng thực phẩm, màng bọc'),
('Văn phòng phẩm', 'Bút bi, sổ tay, giấy in A4, băng keo văn phòng'),
('Thức ăn thú cưng', 'Hạt dinh dưỡng và pate đóng gói cho chó mèo'),
('Thực phẩm chay & Hữu cơ', 'Đậu hũ non, nấm tươi, rau củ đạt chuẩn Organic'),
('Đồ hộp & Thực phẩm chế biến', 'Cá ngừ ngâm dầu, pate gan, thịt hộp tiệt trùng'),
('Trà, Cà phê & Ngũ cốc', 'Cà phê rang xay, trà túi lọc, bột ngũ cốc dinh dưỡng'),
('Khăn giấy & Vật tư vệ sinh', 'Giấy vệ sinh cuộn lớn, khăn giấy rút, túi rác sinh học'),
('Điện gia dụng nhỏ', 'Ấm siêu tốc, ổ cắm điện, bóng đèn LED tiết kiệm điện');

-- 2. Mở rộng employees từ 3 -> 500 nhân viên (ID 4..500)
INSERT INTO employees (employee_id, employee_name, role, phone, salary)
SELECT
    id,
    CONCAT(
        ELT(1 + (id % 10), 'Nguyễn', 'Trần', 'Lê', 'Phạm', 'Hoàng', 'Vũ', 'Đặng', 'Bùi', 'Đỗ', 'Ngô'), ' ',
        ELT(1 + ((id DIV 10) % 8), 'Văn', 'Thị', 'Minh', 'Hoàng', 'Quốc', 'Thanh', 'Đức', 'Ngọc'), ' ',
        ELT(1 + ((id DIV 80) % 10), 'Hùng', 'Lan', 'Tuấn', 'Hương', 'Dũng', 'Linh', 'Hải', 'Trang', 'Phúc', 'Tâm')
    ),
    ELT(1 + (id % 5), 'Thu ngân', 'Thu ngân', 'Nhân viên kho', 'Quầy tươi sống', 'Quản lý ca'),
    CONCAT('090', LPAD(id, 7, '0')),
    7500000 + ((id % 8) * 1000000)
FROM (
    SELECT n + 4 AS id FROM _seq_1000 WHERE n + 4 <= 500
) AS t
ORDER BY id;

-- 3. Mở rộng products từ 10 -> 20.000 sản phẩm (ID 11..20.000)
INSERT INTO products (product_id, barcode, product_name, category_id, unit, price, stock_quantity)
SELECT
    id,
    CONCAT('893850', LPAD(id, 7, '0')),
    CONCAT(
        ELT(1 + (id % 10), 'Sữa tươi', 'Nước khoáng', 'Bánh quy', 'Mì khoai tây', 'Trà ô long', 'Nước xả vải', 'Dầu đậu nành', 'Xúc xích tiệt trùng', 'Cà phê hòa tan', 'Khăn giấy lụa'), ' ',
        ELT(1 + ((id DIV 10) % 8), 'Cao Cấp', 'Đặc Biệt', 'Hương Tự Nhiên', 'Gia Đình', 'Organic', 'Truyền Thống', 'Ít Đường', 'Siêu Tiết Kiệm'),
        ' Mã #', id
    ),
    1 + (id % 20),
    ELT(1 + (id % 6), 'Hộp', 'Chai', 'Gói', 'Lon', 'Túi', 'Kg'),
    12000 + ((id * 17) % 380) * 1000,
    50 + ((id * 31) % 950)
FROM (
    SELECT a.n + b.n * 1000 + 11 AS id
    FROM _seq_1000 a
    CROSS JOIN _seq_1000 b
    WHERE b.n < 20 AND (a.n + b.n * 1000 + 11) <= 20000
) AS p
ORDER BY id;
" 2>/dev/null

echo -e "${CYAN}  [3.2] Nạp 100.000 Khách hàng thành viên (2 lô x 50.000)...${NC}"
for batch in 0 1; do
    START_ID=$(( batch * 50000 + 1 ))
    if [ "$START_ID" -lt 4 ]; then START_ID=4; fi
    END_ID=$(( (batch + 1) * 50000 ))
    docker exec mysql-master mysql -uroot -prootpassword supermarket_db -e "
    INSERT INTO customers (customer_id, customer_name, phone, membership_card, points)
    SELECT
        id,
        CONCAT(
            ELT(1 + (id % 10), 'Nguyễn', 'Trần', 'Lê', 'Phạm', 'Hoàng', 'Phan', 'Vũ', 'Đặng', 'Bùi', 'Đỗ'), ' ',
            ELT(1 + ((id DIV 10) % 8), 'Minh', 'Thị', 'Gia', 'Hữu', 'Thanh', 'Phương', 'Tuấn', 'Bảo'), ' ',
            ELT(1 + ((id DIV 80) % 12), 'Anh', 'Bình', 'Châu', 'Đạt', 'Giang', 'Khánh', 'Khoa', 'My', 'Nam', 'Phong', 'Quân', 'Vy')
        ),
        CONCAT('09', LPAD(id, 8, '0')),
        CONCAT('MEM', LPAD(id, 7, '0')),
        (id * 13) % 2500
    FROM (
        SELECT a.n + b.n * 1000 + $START_ID AS id
        FROM _seq_1000 a
        CROSS JOIN _seq_1000 b
        WHERE b.n < 50 AND (a.n + b.n * 1000 + $START_ID) <= $END_ID
    ) AS c
    ORDER BY id;
    " 2>/dev/null
done

echo -e "${CYAN}  [3.3] Nạp 500.000 Hóa đơn bán lẻ (10 lô x 50.000)...${NC}"
for batch in $(seq 0 9); do
    START_ID=$(( batch * 50000 + 1 ))
    if [ "$START_ID" -lt 3 ]; then START_ID=3; fi
    END_ID=$(( (batch + 1) * 50000 ))
    docker exec mysql-master mysql -uroot -prootpassword supermarket_db -e "
    INSERT INTO orders (order_id, order_code, customer_id, employee_id, total_amount, discount_amount, final_amount, payment_method, order_date)
    SELECT
        id,
        CONCAT('HD2026', LPAD(id, 8, '0')),
        CASE WHEN id % 5 = 0 THEN NULL ELSE 1 + (id % 100000) END,
        1 + (id % 500),
        tot,
        disc,
        tot - disc,
        ELT(1 + (id % 4), 'Tiền mặt', 'Chuyển khoản', 'Thẻ POS', 'Ví điện tử'),
        TIMESTAMP('2026-05-01 07:00:00') + INTERVAL (id % 180) DAY + INTERVAL (id % 50400) SECOND
    FROM (
        SELECT
            id,
            80000 + ((id * 29) % 920) * 1000 AS tot,
            CASE WHEN id % 5 = 0 THEN 0 ELSE ((id % 6) * 5000) END AS disc
        FROM (
            SELECT a.n + b.n * 1000 + $START_ID AS id
            FROM _seq_1000 a
            CROSS JOIN _seq_1000 b
            WHERE b.n < 50 AND (a.n + b.n * 1000 + $START_ID) <= $END_ID
        ) AS raw_ids
    ) AS o
    ORDER BY id;
    " 2>/dev/null
    echo -ne "    -> Đã nạp hóa đơn đến mốc: $END_ID / 500000\r"
done
echo ""

echo -e "${CYAN}  [3.4] Nạp 2.000.000 Chi tiết hóa đơn (20 lô x 100.000)...${NC}"
for batch in $(seq 0 19); do
    START_ID=$(( batch * 100000 + 1 ))
    if [ "$START_ID" -lt 7 ]; then START_ID=7; fi
    END_ID=$(( (batch + 1) * 100000 ))
    docker exec mysql-master mysql -uroot -prootpassword supermarket_db -e "
    INSERT INTO order_details (order_detail_id, order_id, product_id, quantity, unit_price, subtotal)
    SELECT
        id,
        ord_id,
        prod_id,
        qty,
        uprice,
        qty * uprice
    FROM (
        SELECT
            id,
            1 + ((id - 1) DIV 4) AS ord_id,
            1 + ((id * 7919) % 20000) AS prod_id,
            1 + (id % 5) AS qty,
            15000 + ((id * 37) % 185) * 1000 AS uprice
        FROM (
            SELECT a.n + b.n * 1000 + $START_ID AS id
            FROM _seq_1000 a
            CROSS JOIN _seq_1000 b
            WHERE b.n < 100 AND (a.n + b.n * 1000 + $START_ID) <= $END_ID
        ) AS raw_ids
    ) AS od
    ORDER BY id;
    " 2>/dev/null
    echo -ne "    -> Đã nạp chi tiết hóa đơn đến mốc: $END_ID / 2000000\r"
done
echo ""

# Xóa bảng tạm và cập nhật thống kê Optimizer
docker exec mysql-master mysql -uroot -prootpassword supermarket_db -e "
DROP TABLE IF EXISTS _seq_1000;
ANALYZE TABLE categories, employees, products, customers, orders, order_details;
" 2>/dev/null

SEED_END_NS=$(date +%s%N)
MASTER_SEED_SEC=$(awk "BEGIN {printf \"%.2f\", ($SEED_END_NS - $SEED_START_NS)/1000000000}")
echo -e "${GREEN}[HOÀN TẤT MASTER] Đã nạp xong 2.620.520 bản ghi trên Master trong ${MASTER_SEED_SEC} giây!${NC}"

# 4. Theo dõi quá trình đồng bộ sang Slave 1 và Slave 2
echo -e "\n${YELLOW}>>> BƯỚC 4: Theo dõi đồng bộ GTID thời gian thực sang Slave 1 và Slave 2 <<<${NC}"
SYNC_WAIT_START=$(date +%s%N)
MASTER_GTID=$(docker exec mysql-master mysql -uroot -prootpassword -sN -e "SELECT @@global.gtid_executed;" 2>/dev/null | tr -d '\n ')

while true; do
    S1_GTID=$(docker exec mysql-slave-1 mysql -uroot -prootpassword -sN -e "SELECT @@global.gtid_executed;" 2>/dev/null | tr -d '\n ')
    S2_GTID=$(docker exec mysql-slave-2 mysql -uroot -prootpassword -sN -e "SELECT @@global.gtid_executed;" 2>/dev/null | tr -d '\n ')
    LAG1=$(docker exec mysql-slave-1 mysql -uroot -prootpassword -e "SHOW REPLICA STATUS\G" 2>/dev/null | awk '/Seconds_Behind_Source:/ {print $2}')
    LAG2=$(docker exec mysql-slave-2 mysql -uroot -prootpassword -e "SHOW REPLICA STATUS\G" 2>/dev/null | awk '/Seconds_Behind_Source:/ {print $2}')
    echo -ne "    Đang đồng bộ... Lag Slave 1: ${LAG1}s | Lag Slave 2: ${LAG2}s\r"
    if [ "$S1_GTID" = "$MASTER_GTID" ] && [ "$S2_GTID" = "$MASTER_GTID" ]; then
        break
    fi
    sleep 1
done
echo ""
SYNC_WAIT_END=$(date +%s%N)
EXTRA_SYNC_SEC=$(awk "BEGIN {printf \"%.2f\", ($SYNC_WAIT_END - $SYNC_WAIT_START)/1000000000}")
TOTAL_CLUSTER_SEC=$(awk "BEGIN {printf \"%.2f\", ($SYNC_WAIT_END - $SEED_START_NS)/1000000000}")

echo -e "${GREEN}[ĐỒNG BỘ 100%] Cả 2 Slave đã bắt kịp hoàn toàn Master (Thời gian trễ bù thêm sau khi Master xong: ${EXTRA_SYNC_SEC}s, Tổng thời gian toàn cụm: ${TOTAL_CLUSTER_SEC}s).${NC}"

# 5. Xuất báo cáo thống kê số lượng bản ghi, dung lượng đĩa và Binary Log
echo -e "\n${YELLOW}>>> BƯỚC 5: Đối soát số lượng bản ghi & dung lượng lưu trữ trên cả 3 Node <<<${NC}"
bash "$SCRIPT_DIR/02_verify_replication.sh" 2>/dev/null

echo -e "\n--> Thống kê dung lượng bảng & chỉ mục InnoDB trên Master (MB):"
docker exec mysql-master mysql -uroot -prootpassword -e "
SELECT
    table_name AS 'Bảng',
    table_rows AS 'Ước lượng InnoDB',
    ROUND(data_length / 1024 / 1024, 2) AS 'Data (MB)',
    ROUND(index_length / 1024 / 1024, 2) AS 'Index (MB)',
    ROUND((data_length + index_length) / 1024 / 1024, 2) AS 'Tổng (MB)'
FROM information_schema.tables
WHERE table_schema = 'supermarket_db'
UNION ALL
SELECT
    'TOTAL',
    SUM(table_rows),
    ROUND(SUM(data_length) / 1024 / 1024, 2),
    ROUND(SUM(index_length) / 1024 / 1024, 2),
    ROUND(SUM(data_length + index_length) / 1024 / 1024, 2)
FROM information_schema.tables
WHERE table_schema = 'supermarket_db';
" 2>/dev/null

echo -e "\n--> Danh sách tệp Binary Log trên Master (Kiểm chứng tự động tách file max_binlog_size = 100M):"
docker exec mysql-master mysql -uroot -prootpassword -e "SHOW BINARY LOGS;" 2>/dev/null

echo -e "\n${BLUE}============================================================================${NC}"
echo -e "${BLUE}   HOÀN TẤT NÂNG CẤP CỤM LÊN 2.620.520 BẢN GHI/NODE (7,86 TRIỆU TOÀN CỤM)!  ${NC}"
echo -e "${BLUE}============================================================================${NC}"
