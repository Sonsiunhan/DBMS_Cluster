#!/bin/bash
set -e

QUERY="
SELECT 'categories' AS tbl, COUNT(*) AS count FROM categories
UNION ALL SELECT 'products', COUNT(*) FROM products
UNION ALL SELECT 'customers', COUNT(*) FROM customers
UNION ALL SELECT 'employees', COUNT(*) FROM employees
UNION ALL SELECT 'orders', COUNT(*) FROM orders
UNION ALL SELECT 'order_details', COUNT(*) FROM order_details;
"

echo "=========================================="
echo " KIỂM TRA SỐ LƯỢNG BẢN GHI TRÊN CÁC NODE "
echo "=========================================="

echo "--> Node 1: MASTER (mysql-master):"
docker exec mysql-master mysql -uroot -prootpassword supermarket_db -e "$QUERY" 2>/dev/null

echo "--> Node 2: SLAVE 1 (mysql-slave-1):"
docker exec mysql-slave-1 mysql -uroot -prootpassword supermarket_db -e "$QUERY" 2>/dev/null

echo "--> Node 3: SLAVE 2 (mysql-slave-2):"
docker exec mysql-slave-2 mysql -uroot -prootpassword supermarket_db -e "$QUERY" 2>/dev/null
