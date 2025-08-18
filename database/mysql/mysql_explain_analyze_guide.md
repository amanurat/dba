# 🧠 MySQL EXPLAIN / ANALYZE Cheat Sheet

คู่มือการใช้ `EXPLAIN`, `EXPLAIN ANALYZE` และ `ANALYZE TABLE` สำหรับวิเคราะห์ Performance ของ Query บน MySQL

---

## 📌 1. ความแตกต่างของแต่ละคำสั่ง

| คำสั่ง              | ทำอะไร                                        | ใช้เมื่อ                             |
|----------------------|-----------------------------------------------|---------------------------------------|
| `EXPLAIN`            | แสดงแผนการรัน query โดยไม่ execute จริง       | อยากดู plan ว่ามี index หรือไม่       |
| `EXPLAIN ANALYZE`    | แสดง plan + รันจริง แล้ววัดเวลาทุกขั้นตอน    | วิเคราะห์ query ช้า / benchmark (MySQL 8.0.18+)     |
| `EXPLAIN FORMAT=TREE`| แสดง plan ในรูปแบบ tree structure            | เข้าใจ execution order ได้ชัดเจนขึ้น |
| `ANALYZE TABLE`      | สร้างสถิติใหม่ให้ optimizer ใช้ planning ดีขึ้น | หลัง bulk insert/update/delete        |

---

## 🔍 2. ตัวอย่าง `EXPLAIN`

```sql
EXPLAIN SELECT * FROM customers WHERE email = 'john@example.com';
```

ผลลัพธ์ (แบบ tabular):

```
+----+-------------+-----------+------+---------------+-----------+---------+-------+------+-------+
| id | select_type | table     | type | possible_keys | key       | key_len | ref   | rows | Extra |
+----+-------------+-----------+------+---------------+-----------+---------+-------+------+-------+
|  1 | SIMPLE      | customers | ref  | idx_email     | idx_email | 767     | const |    1 |       |
+----+-------------+-----------+------+---------------+-----------+---------+-------+------+-------+
```

---

## 🚀 3. ตัวอย่าง `EXPLAIN ANALYZE` (MySQL 8.0.18+)

```sql
EXPLAIN ANALYZE SELECT * FROM customers WHERE email = 'john@example.com';
```

ผลลัพธ์:

```
-> Index lookup on customers using idx_email (email='john@example.com')  
   (cost=0.35 rows=1) (actual time=0.123..0.125 rows=1 loops=1)
```

> แสดงเวลาจริงที่ใช้ (`actual time`) และจำนวน rows ที่ได้จริง → ใช้วิเคราะห์ performance โดยตรง

---

## 🌳 4. ตัวอย่าง `EXPLAIN FORMAT=TREE`

```sql
EXPLAIN FORMAT=TREE 
SELECT c.name, o.total 
FROM customers c 
JOIN orders o ON c.id = o.customer_id 
WHERE c.status = 'active';
```

ผลลัพธ์:

```
-> Nested loop inner join  (cost=2.75 rows=2)
    -> Index lookup on c using idx_status (status='active')  (cost=1.25 rows=2)
    -> Index lookup on o using idx_customer_id (customer_id=c.id)  (cost=0.75 rows=1)
```

> แสดงลำดับการทำงานในรูปแบบ tree ทำให้เข้าใจ execution plan ได้ชัดเจนขึ้น

---

## 🛠 5. ตัวอย่าง `ANALYZE TABLE`

```sql
ANALYZE TABLE customers;
```

ผลลัพธ์:

```
+-----------------+---------+----------+----------+
| Table           | Op      | Msg_type | Msg_text |
+-----------------+---------+----------+----------+
| mydb.customers  | analyze | status   | OK       |
+-----------------+---------+----------+----------+
```

> ใช้เพื่ออัปเดตสถิติของตารางหลังมีการเปลี่ยนข้อมูลจำนวนมาก เช่น insert/delete

---

## 🧪 6. คำแนะนำการใช้งาน

| เป้าหมาย                         | คำสั่งที่แนะนำ                |
|----------------------------------|-------------------------------|
| ตรวจสอบว่า query ใช้ index ไหม  | `EXPLAIN`                     |
| หาว่า query ช้าตรงไหน           | `EXPLAIN ANALYZE` (MySQL 8.0.18+) |
| เข้าใจ execution order          | `EXPLAIN FORMAT=TREE`         |
| Optimizer ตัดสินใจผิด           | `ANALYZE TABLE` แล้วค่อย `EXPLAIN` |
| เปรียบเทียบก่อน-หลังทำ index   | `EXPLAIN ANALYZE` 2 ครั้ง     |

---

## 🎯 7. คำศัพท์ที่พบใน Plan

### Access Types (จากดีที่สุดไปแย่ที่สุด)

| Type | ความหมาย | ประสิทธิภาพ |
|------|-----------|-------------|
| `const` | Primary key หรือ unique key lookup | 🟢 ดีที่สุด |
| `eq_ref` | Unique index lookup ใน JOIN | 🟢 ดีมาก |
| `ref` | Non-unique index lookup | 🟢 ดี |
| `range` | Index range scan (WHERE id BETWEEN) | 🟡 ปานกลาง |
| `index` | Full index scan | 🟠 ช้า |
| `ALL` | Full table scan | 🔴 ช้าที่สุด |

### คำศัพท์อื่นๆ

| คำ | ความหมาย |
|-----|-----------|
| `Using index` | ใช้ covering index (ไม่ต้องอ่าน table) |
| `Using where` | มีการกรอง rows หลังอ่านข้อมูล |
| `Using filesort` | ต้อง sort ข้อมูล (อาจช้า) |
| `Using temporary` | ใช้ temporary table (อาจช้า) |
| `rows` | จำนวน row ที่ optimizer คาดว่าจะต้องตรวจสอบ |
| `cost` | ค่าประมาณความหนักของ operation |

---

## 📊 8. เปรียบเทียบ MySQL vs PostgreSQL

| ฟีเจอร์ | MySQL | PostgreSQL |
|---------|--------|-------------|
| Basic EXPLAIN | ✅ | ✅ |
| EXPLAIN ANALYZE | ✅ (8.0.18+) | ✅ |
| FORMAT=TREE | ✅ | ❌ (ใช้ FORMAT=TEXT) |
| Real execution time | ✅ (ANALYZE) | ✅ (ANALYZE) |
| Buffer usage | ❌ | ✅ (BUFFERS) |
| Visual tools | MySQL Workbench | pgAdmin, explain.depesz.com |

---

## 🔧 9. Visualization Tools

### สำหรับ MySQL:
- **MySQL Workbench** → Visual Explain Plan
- **phpMyAdmin** → Query Analysis
- **Azure Data Studio** → Query Plan viewer
- **Online**: [MySQLExplain.com](https://mysqlexplain.com/)

### แนะนำ:
```sql
-- เปิด profiling เพื่อดูรายละเอียดเวลา
SET profiling = 1;
SELECT * FROM customers WHERE email = 'john@example.com';
SHOW PROFILES;
SHOW PROFILE FOR QUERY 1;
```

---

## 🚨 10. Warning Signs ใน EXPLAIN

| สิ่งที่เจอ | ปัญหา | วิธีแก้ |
|------------|-------|---------|
| `type: ALL` | Full table scan | เพิ่ม index |
| `rows: 100000+` | ตรวจสอบข้อมูลเยอะ | เพิ่ม WHERE condition |
| `Using filesort` | Sort ข้อมูลช้า | เพิ่ม index สำหรับ ORDER BY |
| `Using temporary` | สร้าง temp table | ปรับ query หรือเพิ่ม memory |
| `cost > 1000` | Query หนัก | ตรวจสอบ index และ WHERE |

---

## ✅ 11. สรุป Quick Reference

| ชื่อ | ใช้ทำอะไร | MySQL Version |
|------|------------|---------------|
| `EXPLAIN` | ดูแผนรันล่วงหน้า | ทุกเวอร์ชัน |
| `EXPLAIN ANALYZE` | รันจริง + วัด performance | 8.0.18+ |
| `EXPLAIN FORMAT=TREE` | ดู execution order | 8.0+ |
| `ANALYZE TABLE` | สร้าง stats ให้ optimizer | ทุกเวอร์ชัน |

---

## 💡 12. Tips สำหรับการใช้งาน

### ✅ Best Practices:
- ใช้ `EXPLAIN` ใน development เพื่อเช็ค plan
- ใช้ `EXPLAIN ANALYZE` เฉพาะใน test environment
- ทำ `ANALYZE TABLE` หลัง bulk data changes
- ใช้ `FORMAT=TREE` เพื่อเข้าใจ complex queries

### ⚠️ ข้อระวัง:
- `EXPLAIN ANALYZE` รัน query จริง อาจกระทบ production
- อย่าลืมดู `actual time` ใน ANALYZE ไม่ใช่แค่ `cost`
- ใน MySQL 8.0 ต่ำกว่า 8.0.18 ไม่มี `EXPLAIN ANALYZE`

---

**🎓 การเข้าใจ EXPLAIN คือกุญแจสำคัญในการ optimize MySQL queries!**

ยิ่งใช้บ่อยๆ ยิ่งเข้าใจ pattern และสามารถปรับปรุง performance ได้ดีขึ้น