
# 🧠 PostgreSQL EXPLAIN / ANALYZE Cheat Sheet

คู่มือการใช้ `EXPLAIN`, `EXPLAIN ANALYZE` และ `ANALYZE` สำหรับวิเคราะห์ Performance ของ Query บน PostgreSQL

---

## 📌 1. ความแตกต่างของแต่ละคำสั่ง

| คำสั่ง              | ทำอะไร                                        | ใช้เมื่อ                             |
|----------------------|-----------------------------------------------|---------------------------------------|
| `EXPLAIN`            | แสดงแผนการรัน query โดยไม่ execute จริง       | อยากดู plan ว่ามี index หรือไม่       |
| `EXPLAIN ANALYZE`    | แสดง plan + รันจริง แล้ววัดเวลาทุกขั้นตอน    | วิเคราะห์ query ช้า / benchmark     |
| `ANALYZE`            | สร้างสถิติใหม่ให้ optimizer ใช้ planning ดีขึ้น | หลัง bulk insert/update/delete        |

---

## 🔍 2. ตัวอย่าง `EXPLAIN`

```sql
EXPLAIN SELECT * FROM customers WHERE email = 'john@example.com';
```

ผลลัพธ์ (แค่ประมาณ):

```
Index Scan using idx_email on customers  (cost=0.42..8.44 rows=1 width=64)
  Index Cond: (email = 'john@example.com')
```

---

## 🚀 3. ตัวอย่าง `EXPLAIN ANALYZE`

```sql
EXPLAIN ANALYZE SELECT * FROM customers WHERE email = 'john@example.com';
```

ผลลัพธ์:

```
Index Scan using idx_email on customers  (actual time=0.030..0.035 rows=1 loops=1)
  Index Cond: (email = 'john@example.com')
Planning Time: 0.084 ms
Execution Time: 0.078 ms
```

> แสดงเวลาแต่ละขั้นตอนจริง และจำนวน rows ที่ scan → ใช้วิเคราะห์ performance โดยตรง

---

## 🛠 4. ตัวอย่าง `ANALYZE`

```sql
ANALYZE customers;
```

> ใช้เพื่ออัปเดตสถิติของตารางหลังมีการเปลี่ยนข้อมูลจำนวนมาก เช่น insert/delete

---

## 🧪 5. คำแนะนำการใช้งาน

| เป้าหมาย                         | คำสั่งที่แนะนำ                |
|----------------------------------|-------------------------------|
| ตรวจสอบว่า query ใช้ index ไหม  | `EXPLAIN`                     |
| หาว่า query ช้าตรงไหน           | `EXPLAIN ANALYZE`             |
| Planner ตัดสินใจผิด             | `ANALYZE` แล้วค่อย `EXPLAIN` |
| เปรียบเทียบก่อน-หลังทำ index   | `EXPLAIN ANALYZE` 2 ครั้ง     |

---

## 🎯 6. คำศัพท์ที่พบใน Plan

| คำ | ความหมาย |
|-----|-----------|
| Seq Scan | การ scan ทั้ง table (ช้า) |
| Index Scan | ใช้ index (เร็วกว่า Seq) |
| Filter | เงื่อนไขที่ใช้คัดแถว |
| Cost | ค่าประมาณความหนักของ query |
| Rows | จำนวน row ที่ planner คาดว่าจะได้ |
| Actual Time | เวลาจริงที่ใช้ (จาก ANALYZE) |

---

## 📊 7. Visualization Tool ที่ใช้ดู Plan

- DBeaver → คลิกขวา EXPLAIN → ดูแบบ Tree
- Azure Data Studio → Query Plan แบบกราฟ
- [https://explain.depesz.com/](https://explain.depesz.com) → Paste plan เพื่อดูแบบสี

---

## ✅ สรุป

| ชื่อ | ใช้ทำอะไร | ใช้เมื่อ |
|------|------------|----------|
| EXPLAIN | ดูแผนรันล่วงหน้า | เช็ค index / plan |
| EXPLAIN ANALYZE | รันจริง + วัด performance | วิเคราะห์ query |
| ANALYZE | สร้าง stats ให้ planner | หลัง bulk data |

---

💡 **Tip:** ควรใช้ `EXPLAIN ANALYZE` เฉพาะในระบบ test/dev เพราะมันรัน query จริง อาจกระทบ production

