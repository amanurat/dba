# 🧠 SQL Server Execution Plan Analysis Guide

คู่มือการใช้ Execution Plans, `SET STATISTICS`, และ Query Analysis สำหรับวิเคราะห์ Performance ของ Query บน SQL Server

---

## 📌 1. ความแตกต่างของเครื่องมือวิเคราะห์

| เครื่องมือ | ทำอะไร | ใช้เมื่อ | SQL Server Version |
|------------|---------|---------|-------------------|
| **Execution Plan** | แสดงแผนการรัน query โดยไม่ execute | ดู plan ว่ามี index หรือไม่ | All versions |
| **Actual Execution Plan** | แสดง plan + รันจริง พร้อมสถิติจริง | วิเคราะห์ query ช้า | All versions |
| **Live Query Statistics** | แสดง plan แบบ real-time ขณะรัน | Monitor query ที่รันนาน | 2016+ |
| **Query Store** | เก็บประวัติ plan และ performance | วิเคราะห์ performance แบบ historical | 2016+ |
| **SET STATISTICS** | แสดงสถิติการใช้ resource | วัด I/O, CPU, Memory usage | All versions |

---

## 🔍 2. การดู Estimated Execution Plan

### 2.1 วิธีเปิดดู Plan
```sql
-- Method 1: SET SHOWPLAN_ALL
SET SHOWPLAN_ALL ON;
SELECT * FROM Customers WHERE CustomerID = 'ALFKI';
SET SHOWPLAN_ALL OFF;

-- Method 2: ใน SSMS กด Ctrl+L ก่อนรัน query
-- Method 3: Include Estimated Execution Plan button
```

### 2.2 ตัวอย่างการอ่าน Plan
```sql
-- Query ที่ใช้ Index Seek (ดี)
SELECT CustomerID, CompanyName 
FROM Customers 
WHERE CustomerID = 'ALFKI';

-- Query ที่ใช้ Table Scan (อาจช้า)
SELECT CustomerID, CompanyName 
FROM Customers 
WHERE CompanyName LIKE '%Foods%';
```

**ผลลัพธ์ที่ดี:**
```
Index Seek (NonClustered) [PK_Customers] 
Cost: 0.0032 (3% of query cost)
```

**ผลลัพธ์ที่อาจมีปัญหา:**
```
Table Scan [Customers]
Cost: 0.0067 (97% of query cost)
```

---

## 🚀 3. การดู Actual Execution Plan

### 3.1 เปิดใช้งาน Actual Plan
```sql
-- Method 1: SET STATISTICS XML
SET STATISTICS XML ON;
SELECT * FROM Customers WHERE Country = 'Germany';
SET STATISTICS XML OFF;

-- Method 2: ใน SSMS กด Ctrl+M แล้วรัน query
-- Method 3: Include Actual Execution Plan button
```

### 3.2 ตัวอย่างการวิเคราะห์
```sql
-- Query สำหรับทดสอบ
SELECT 
    c.CustomerID,
    c.CompanyName,
    COUNT(o.OrderID) AS OrderCount,
    SUM(od.UnitPrice * od.Quantity) AS TotalAmount
FROM Customers c
    LEFT JOIN Orders o ON c.CustomerID = o.CustomerID
    LEFT JOIN [Order Details] od ON o.OrderID = od.OrderID
WHERE c.Country = 'Germany'
GROUP BY c.CustomerID, c.CompanyName
ORDER BY TotalAmount DESC;
```

**สิ่งที่ควรดูใน Actual Plan:**
- **Actual Number of Rows** vs **Estimated Number of Rows**
- **Actual Execution Time** สำหรับแต่ละ operator
- **I/O Cost** และ **CPU Cost**
- **Warning icons** (สีเหลือง) ที่บ่งบอกปัญหา

---

## ⚡ 4. Live Query Statistics (SQL Server 2016+)

### 4.1 เปิดใช้งาน Live Statistics
```sql
-- ใน SSMS: Query menu → Include Live Query Statistics
-- หรือใช้ icon ⚡ ใน toolbar

-- ตัวอย่าง query ที่รันนาน
SELECT 
    p.ProductName,
    SUM(od.Quantity) AS TotalQuantity,
    AVG(od.UnitPrice) AS AvgPrice
FROM Products p
    INNER JOIN [Order Details] od ON p.ProductID = od.ProductID
    INNER JOIN Orders o ON od.OrderID = o.OrderID
WHERE o.OrderDate >= '1997-01-01'
GROUP BY p.ProductName
ORDER BY TotalQuantity DESC;
```

**ประโยชน์ของ Live Statistics:**
- เห็น **progress bar** แต่ละ step
- **Actual rows** แบบ real-time
- **Elapsed time** สำหรับแต่ละ operator
- สามารถ **cancel query** ได้เมื่อเห็นปัญหา

---

## 📊 5. Query Store Analysis

### 5.1 การใช้ Query Store ดู Plan History
```sql
-- ดู query performance ย้อนหลัง
SELECT 
    qst.query_sql_text,
    qsp.plan_id,
    qsp.query_plan,
    rs.avg_duration / 1000.0 AS avg_duration_ms,
    rs.avg_cpu_time / 1000.0 AS avg_cpu_ms,
    rs.avg_logical_io_reads,
    rs.count_executions,
    rs.last_execution_time
FROM sys.query_store_query_text qst
    INNER JOIN sys.query_store_query q ON qst.query_text_id = q.query_text_id
    INNER JOIN sys.query_store_plan qsp ON q.query_id = qsp.query_id
    INNER JOIN sys.query_store_runtime_stats rs ON qsp.plan_id = rs.plan_id
WHERE qst.query_sql_text LIKE '%Customers%'
    AND rs.last_execution_time > DATEADD(day, -7, GETUTCDATE())
ORDER BY rs.avg_duration DESC;
```

### 5.2 เปรียบเทียบ Plan ต่างๆ
```sql
-- หา query ที่มี plan regression
SELECT 
    q.query_id,
    qst.query_sql_text,
    qsp.plan_id,
    rs.avg_duration / 1000.0 AS avg_duration_ms,
    LAG(rs.avg_duration) OVER (PARTITION BY q.query_id ORDER BY rs.last_execution_time) / 1000.0 AS prev_avg_duration_ms,
    CASE 
        WHEN LAG(rs.avg_duration) OVER (PARTITION BY q.query_id ORDER BY rs.last_execution_time) > 0 
        THEN CAST((rs.avg_duration - LAG(rs.avg_duration) OVER (PARTITION BY q.query_id ORDER BY rs.last_execution_time)) * 100.0 / 
                  LAG(rs.avg_duration) OVER (PARTITION BY q.query_id ORDER BY rs.last_execution_time) AS decimal(10,2))
        ELSE NULL
    END AS performance_change_percent
FROM sys.query_store_query q
    INNER JOIN sys.query_store_query_text qst ON q.query_text_id = qst.query_text_id
    INNER JOIN sys.query_store_plan qsp ON q.query_id = qsp.query_id
    INNER JOIN sys.query_store_runtime_stats rs ON qsp.plan_id = rs.plan_id
WHERE rs.count_executions > 10
ORDER BY performance_change_percent DESC;
```

---

## 🛠 6. SET STATISTICS Commands

### 6.1 STATISTICS IO - วัดการใช้ Disk I/O
```sql
SET STATISTICS IO ON;

SELECT CustomerID, CompanyName 
FROM Customers 
WHERE Country = 'Germany';

SET STATISTICS IO OFF;
```

**ผลลัพธ์ตัวอย่าง:**
```
Table 'Customers'. Scan count 1, logical reads 3, physical reads 0, 
read-ahead reads 0, lob logical reads 0, lob physical reads 0.
```

**การแปลผล:**
- **logical reads**: จำนวน page ที่อ่านจาก memory (ยิ่งน้อยยิ่งดี)
- **physical reads**: จำนวน page ที่อ่านจาก disk (ควรเป็น 0 หรือใกล้ 0)
- **read-ahead reads**: pages ที่อ่านล่วงหน้า

### 6.2 STATISTICS TIME - วัดเวลาและ CPU
```sql
SET STATISTICS TIME ON;

SELECT 
    c.CustomerID,
    COUNT(o.OrderID) AS OrderCount
FROM Customers c
    LEFT JOIN Orders o ON c.CustomerID = o.CustomerID
GROUP BY c.CustomerID;

SET STATISTICS TIME OFF;
```

**ผลลัพธ์ตัวอย่าง:**
```
SQL Server parse and compile time: 
   CPU time = 0 ms, elapsed time = 1 ms.

SQL Server Execution Times:
   CPU time = 15 ms, elapsed time = 89 ms.
```

### 6.3 STATISTICS PROFILE - รายละเอียด Execution
```sql
SET STATISTICS PROFILE ON;

SELECT ProductName, UnitPrice 
FROM Products 
WHERE UnitPrice > 50
ORDER BY UnitPrice DESC;

SET STATISTICS PROFILE OFF;
```

---

## 🎯 7. การอ่านและแปล Execution Plan

### 7.1 Operator Types ที่สำคัญ

| Operator | ความหมาย | Performance | เมื่อไหร่ใช้ |
|----------|-----------|-------------|-------------|
| **Index Seek** | ใช้ index หาข้อมูลเฉพาะ | 🟢 ดีที่สุด | WHERE clause มี index |
| **Index Scan** | สแกน index ทั้งหมด | 🟡 ปานกลาง | ไม่มี suitable index |
| **Table Scan** | สแกนตารางทั้งหมด | 🔴 ช้าที่สุด | ไม่มี index เลย |
| **Nested Loop** | JOIN แบบ nested | 🟢 ดีสำหรับข้อมูลน้อย | Small result sets |
| **Hash Match** | JOIN ใช้ hash table | 🟡 ดีสำหรับข้อมูลเยอะ | Large result sets |
| **Merge Join** | JOIN ข้อมูลที่ sort แล้ว | 🟢 ดีสำหรับข้อมูลที่ sort | Sorted inputs |

### 7.2 Warning Signs ใน Plan

| Warning | สาเหตุ | วิธีแก้ |
|---------|--------|---------|
| **Missing Index** | ไม่มี index ที่เหมาะสม | สร้าง index ตามที่แนะนำ |
| **Implicit Conversion** | แปลง data type อัตโนมัติ | ปรับ data type ให้ตรงกัน |
| **Excessive Memory Grant** | ขอ memory มากเกินไป | ปรับ statistics หรือ query |
| **Parallel Plan Warning** | ปัญหา parallelism | ปรับ MAXDOP หรือ cost threshold |

### 7.3 การดู Cost และ Percentage
```sql
-- Query ที่จะดู cost breakdown
SELECT 
    c.CustomerID,
    c.CompanyName,
    o.OrderDate,
    od.ProductID,
    od.Quantity * od.UnitPrice AS LineTotal
FROM Customers c
    INNER JOIN Orders o ON c.CustomerID = o.CustomerID
    INNER JOIN [Order Details] od ON o.OrderID = od.OrderID
WHERE c.Country = 'USA'
    AND o.OrderDate >= '1997-01-01'
    AND od.Quantity > 10
ORDER BY LineTotal DESC;
```

**สิ่งที่ควรดู:**
- **Operator Cost %** - ตัวไหนใช้ cost มากที่สุด
- **Estimated vs Actual Rows** - ถ้าต่างกันมากอาจต้อง update statistics
- **Join Type** - เหมาะสมกับขนาดข้อมูลไหม

---

## 🔧 8. Tools สำหรับ Plan Analysis

### 8.1 SQL Server Management Studio (SSMS)
**ข้อดี:**
- Built-in กับ SQL Server
- Graphical plan viewer
- Tooltip รายละเอียด
- Save/Load plan files

**การใช้งาน:**
- **Ctrl+L**: Estimated Plan
- **Ctrl+M**: Include Actual Plan  
- **Right-click**: Properties, Missing Index Details

### 8.2 Azure Data Studio
**ข้อดี:**
- Cross-platform
- Modern interface
- Query Plan extension
- Integration กับ Azure

### 8.3 Plan Explorer (SentryOne)
**ข้อดี:**
- Advanced plan analysis
- Top Operations view
- Index recommendations
- Wait stats integration

### 8.4 SQL Server Profiler/Extended Events
```sql
-- Extended Events สำหรับจับ slow queries พร้อม plan
CREATE EVENT SESSION [SlowQueries] ON SERVER 
ADD EVENT sqlserver.sql_statement_completed(
    SET collect_statement=(1)
    ACTION(sqlserver.query_plan_hash,sqlserver.sql_text)
    WHERE ([duration]>(1000000))  -- > 1 second
)
ADD TARGET package0.ring_buffer;

ALTER EVENT SESSION [SlowQueries] ON SERVER STATE = START;
```

---

## 📊 9. เปรียบเทียบ SQL Server vs Other Databases

| Feature | SQL Server | MySQL | PostgreSQL |
|---------|------------|-------|------------|
| **Graphical Plans** | ✅ SSMS | ✅ Workbench | ✅ pgAdmin |
| **Actual vs Estimated** | ✅ | ✅ (8.0.18+) | ✅ |
| **Live Statistics** | ✅ (2016+) | ❌ | ❌ |
| **Query Store** | ✅ (2016+) | ❌ | ❌ |
| **Plan Forcing** | ✅ | ❌ | ❌ |
| **Auto Plan Regression** | ✅ (Azure) | ❌ | ❌ |

---

## 🚨 10. Common Performance Issues และการแก้ไข

### 10.1 Table/Index Scan แทน Seek
**ปัญหา:**
```sql
-- Query ที่ทำ Table Scan
SELECT * FROM Orders WHERE YEAR(OrderDate) = 1997;
```

**วิธีแก้:**
```sql
-- ปรับเป็น SARGable query
SELECT * FROM Orders 
WHERE OrderDate >= '1997-01-01' 
    AND OrderDate < '1998-01-01';

-- สร้าง index
CREATE INDEX IX_Orders_OrderDate ON Orders (OrderDate);
```

### 10.2 Implicit Conversion
**ปัญหา:**
```sql
-- CustomerID เป็น NCHAR(5) แต่ใช้ VARCHAR
SELECT * FROM Customers WHERE CustomerID = 'ALFKI';
```

**วิธีแก้:**
```sql
-- ใช้ data type ที่ถูกต้อง
SELECT * FROM Customers WHERE CustomerID = N'ALFKI';
```

### 10.3 Parameter Sniffing
**ปัญหา:**
```sql
-- Stored procedure ที่มี parameter sniffing
CREATE PROCEDURE GetOrdersByCountry @Country NVARCHAR(50)
AS
SELECT * FROM Customers WHERE Country = @Country;
```

**วิธีแก้:**
```sql
-- วิธีที่ 1: ใช้ OPTION (RECOMPILE)
CREATE PROCEDURE GetOrdersByCountry @Country NVARCHAR(50)
AS
SELECT * FROM Customers WHERE Country = @Country
OPTION (RECOMPILE);

-- วิธีที่ 2: ใช้ local variable
CREATE PROCEDURE GetOrdersByCountry @Country NVARCHAR(50)
AS
DECLARE @LocalCountry NVARCHAR(50) = @Country;
SELECT * FROM Customers WHERE Country = @LocalCountry;
```

---

## ✅ 11. Best Practices Checklist

### ✅ **การวิเคราะห์ Plan:**
- ดู **Actual Plan** แทน Estimated สำหรับ performance tuning
- ตรวจสอบ **Actual vs Estimated rows** - ถ้าต่างกันมากต้อง update statistics
- หา **operators ที่ใช้ cost สูงสุด** เป็นจุดเริ่มต้น
- ดู **warning icons** และแก้ไขตามคำแนะนำ

### ✅ **การใช้ Tools:**
- ใช้ **Live Query Statistics** สำหรับ query ที่รันนาน
- ใช้ **Query Store** สำหรับวิเคราะห์ trend และ regression
- ใช้ **SET STATISTICS IO** เพื่อวัด I/O usage
- เก็บ **plan files** สำหรับการเปรียบเทียบ

### ✅ **การ Optimize:**
- แก้ **Table Scan** เป็น **Index Seek** เป็นอันดับแรก
- จัดการ **JOIN order** และ **JOIN type**
- ใช้ **appropriate data types** เพื่อหลีก implicit conversion
- ทำ **statistics update** เป็นประจำ

### ⚠️ **ข้อระวัง:**
- **Estimated Plan ไม่รัน query จริง** - ใช้สำหรับ plan review เท่านั้น
- **Actual Plan รัน query จริง** - ระวังใน production
- **Plan cache** อาจแสดง plan เก่า - ใช้ DBCC FREEPROCCACHE ถ้าจำเป็น
- **Complex queries** อาจมี plan หลายแบบ - ใช้ Query Store ดู history

---

## 💡 12. Advanced Tips

### 🎯 **Plan Analysis Shortcuts:**
```sql
-- หา missing index recommendations
SELECT 
    migs.avg_total_user_cost * (migs.avg_user_impact / 100.0) * (migs.user_seeks + migs.user_scans) AS improvement_measure,
    'CREATE INDEX [IX_' + OBJECT_NAME(mid.object_id, mid.database_id) + '_' + ISNULL(mid.equality_columns,'') + 
    CASE WHEN mid.inequality_columns IS NOT NULL THEN '_' + mid.inequality_columns ELSE '' END + ']' +
    ' ON ' + mid.statement + ' (' + ISNULL(mid.equality_columns,'') +
    CASE WHEN mid.inequality_columns IS NOT NULL THEN ',' + mid.inequality_columns ELSE '' END + ')' +
    ISNULL(' INCLUDE (' + mid.included_columns + ')', '') AS create_index_statement
FROM sys.dm_db_missing_index_groups mig
    INNER JOIN sys.dm_db_missing_index_group_stats migs ON migs.group_handle = mig.index_group_handle
    INNER JOIN sys.dm_db_missing_index_details mid ON mig.index_handle = mid.index_handle
WHERE migs.avg_total_user_cost * (migs.avg_user_impact / 100.0) * (migs.user_seeks + migs.user_scans) > 10
ORDER BY improvement_measure DESC;
```

### 🎯 **Plan Cache Analysis:**
```sql
-- ดู plan cache usage
SELECT 
    cp.objtype,
    cp.cacheobjtype,
    cp.size_in_bytes / 1024 AS size_kb,
    cp.usecounts,
    SUBSTRING(st.text, (qs.statement_start_offset/2)+1,
        ((CASE WHEN qs.statement_end_offset = -1
            THEN LEN(CONVERT(nvarchar(max), st.text)) * 2
            ELSE qs.statement_end_offset
        END - qs.statement_start_offset)/2) + 1) AS query_text
FROM sys.dm_exec_cached_plans cp
    OUTER APPLY sys.dm_exec_sql_text(cp.plan_handle) st
    OUTER APPLY sys.dm_exec_query_stats qs ON cp.plan_handle = qs.plan_handle
WHERE cp.cacheobjtype = 'Compiled Plan'
    AND cp.usecounts > 1
ORDER BY cp.size_in_bytes DESC;
```

---

**🎓 การเข้าใจ Execution Plan คือทักษะสำคัญที่สุดสำหรับ SQL Server Performance Tuning!**

ยิ่งใช้และวิเคราะห์บ่อยๆ ยิ่งเข้าใจ pattern และสามารถ optimize queries ได้ดีขึ้น การรู้จักใช้เครื่องมือต่างๆ ร่วมกันจะทำให้การ troubleshooting มีประสิทธิภาพมากขึ้น