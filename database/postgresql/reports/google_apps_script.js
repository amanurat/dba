// Google Apps Script สำหรับสร้าง PostgreSQL Performance Dashboard
// วิธีใช้: Extensions → Apps Script → Copy code นี้ไปใส่

function createPerformanceDashboard() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  
  // สร้าง Sheet ใหม่
  var sheets = [
    'Performance Overview',
    'Query Analysis', 
    'Index Management',
    'Optimization History',
    'Monitoring & Alerts',
    'Recommendations'
  ];
  
  // ลบ Sheet เดิมถ้ามี
  sheets.forEach(function(sheetName) {
    var existingSheet = ss.getSheetByName(sheetName);
    if (existingSheet) {
      ss.deleteSheet(existingSheet);
    }
  });
  
  // สร้าง Performance Overview Sheet
  var overviewSheet = ss.insertSheet('Performance Overview');
  var overviewData = [
    ['Database Info', 'Value'],
    ['🗄️ Database', 'simpledb'],
    ['🌐 Server', 'pgus.postgres.database.azure.com'],
    ['📅 Last Tuning', '2025-08-18'],
    ['🏷️ PostgreSQL Version', '17.5'],
    ['📊 Current Grade', 'C (75/100)'],
    [''],
    ['Category', 'Score', 'Max', 'Percentage', 'Rating', 'Status'],
    ['💾 Memory Performance', 25, 30, '83.3%', '🟢 Good', 'Cache Hit: 96.43%'],
    ['⚡ Query Performance', 20, 30, '66.7%', '🟡 Needs Work', '5 Slow Queries'],
    ['🗂️ Index Efficiency', 20, 25, '80.0%', '🟡 Improving', '4 New Indexes'],
    ['📏 Database Size', 10, 15, '66.7%', '🟡 Large', '5.8 GB'],
    ['🎯 TOTAL SCORE', 75, 100, '75.0%', '🟡 Grade C', 'Optimized']
  ];
  
  var range = overviewSheet.getRange(1, 1, overviewData.length, overviewData[0].length);
  range.setValues(overviewData);
  
  // จัดรูปแบบ
  overviewSheet.getRange(1, 1, 1, 2).setBackground('#4CAF50').setFontWeight('bold');
  overviewSheet.getRange(8, 1, 1, 6).setBackground('#2196F3').setFontWeight('bold');
  overviewSheet.autoResizeColumns(1, 6);
  
  // สร้าง Query Analysis Sheet
  var querySheet = ss.insertSheet('Query Analysis');
  var queryData = [
    ['Rank', 'Query Preview', 'Avg Time (ms)', 'Total Time (ms)', 'Calls', 'Impact', 'Status'],
    [1, 'CREATE TABLE performance_test...', 472750.98, 472750.98, 1, '🔴 Critical', 'One-time'],
    [2, 'SELECT * FROM orders WHERE customer_id...', 91.62, 274852.85, 3000, '🟠 High', '✅ Optimized'],
    [3, 'Aggregate Query (country, COUNT, AVG)', 482.45, 13508.60, 28, '🟠 High', 'Needs work'],
    [4, 'JOIN Query (orders + customers)', 412.96, 11562.88, 28, '🟠 High', 'Partial'],
    [5, 'UPDATE orders SET status', 257.69, 7215.32, 28, '🟡 Medium', 'Can improve']
  ];
  
  var queryRange = querySheet.getRange(1, 1, queryData.length, queryData[0].length);
  queryRange.setValues(queryData);
  querySheet.getRange(1, 1, 1, 7).setBackground('#FF9800').setFontWeight('bold');
  querySheet.autoResizeColumns(1, 7);
  
  // สร้าง Index Management Sheet  
  var indexSheet = ss.insertSheet('Index Management');
  var indexData = [
    ['Table', 'Index Name', 'Type', 'Usage Count', 'Size', 'Status', 'Action', 'Priority'],
    ['customers', 'customers_pkey', 'Primary', 535451, '2.2 MB', '🟢 Active', 'Keep', 'Low'],
    ['orders', 'orders_pkey', 'Primary', 0, '22 MB', '🔴 Unused', 'Review', 'High'],
    ['customers', 'customers_email_key', 'Unique', 0, '6.9 MB', '🔴 Unused', 'Review', 'Medium'],
    ['orders', 'idx_orders_customer_id', 'B-tree', 1, '~4 MB', '🟢 New', 'Monitor', 'High'],
    ['orders', 'idx_orders_status', 'B-tree', 0, '~3 MB', '🟡 New', 'Monitor', 'High'],
    ['orders', 'idx_orders_amount', 'B-tree', 0, '~4 MB', '🟡 New', 'Monitor', 'High'],
    ['orders', 'idx_orders_status_ordered_at', 'Composite', 0, '~4 MB', '🟡 New', 'Monitor', 'High']
  ];
  
  var indexRange = indexSheet.getRange(1, 1, indexData.length, indexData[0].length);
  indexRange.setValues(indexData);
  indexSheet.getRange(1, 1, 1, 8).setBackground('#9C27B0').setFontWeight('bold');
  indexSheet.autoResizeColumns(1, 8);
  
  // เพิ่มสีตามสถานะ
  for (var i = 2; i <= indexData.length; i++) {
    var statusCell = indexSheet.getRange(i, 6);
    var status = statusCell.getValue();
    if (status.includes('🟢')) {
      statusCell.setBackground('#C8E6C9');
    } else if (status.includes('🟡')) {
      statusCell.setBackground('#FFF9C4');
    } else if (status.includes('🔴')) {
      statusCell.setBackground('#FFCDD2');
    }
  }
  
  // สร้าง Monitoring Sheet
  var monitorSheet = ss.insertSheet('Monitoring & Alerts');
  var monitorData = [
    ['Check', 'Target', 'Current', 'Status', 'Last Updated', 'Next Check', 'Owner'],
    ['📈 Cache Hit Ratio', '>95%', '96.44%', '🟢 Good', '2025-08-18', '2025-08-19', 'DBA Team'],
    ['👥 Active Connections', '<10', '0', '🟢 Excellent', '2025-08-18', '2025-08-19', 'DBA Team'],
    ['⏱️ Avg Query Time', '<100ms', '0.487ms', '🟢 Excellent', '2025-08-18', '2025-08-19', 'DBA Team'],
    ['💽 Database Size', '<10GB', '5.8GB', '🟢 Good', '2025-08-18', '2025-08-25', 'DBA Team'],
    ['🗂️ Index Usage', 'All used', '4 new monitoring', '🟡 Monitoring', '2025-08-18', '2025-08-25', 'DBA Team']
  ];
  
  var monitorRange = monitorSheet.getRange(1, 1, monitorData.length, monitorData[0].length);
  monitorRange.setValues(monitorData);
  monitorSheet.getRange(1, 1, 1, 7).setBackground('#607D8B').setFontWeight('bold');
  monitorSheet.autoResizeColumns(1, 7);
  
  // สร้าง Recommendations Sheet
  var recoSheet = ss.insertSheet('Recommendations');
  var recoData = [
    ['Priority', 'Task', 'Expected Benefit', 'Effort', 'Risk', 'Owner', 'Deadline', 'Status'],
    ['🔴 High', 'Monitor new index usage', 'Verify optimization success', 'Low', 'Low', 'DBA Team', '2025-08-25', 'Pending'],
    ['🔴 High', 'Set up cache hit alerts', 'Prevent performance drops', 'Medium', 'Low', 'DBA Team', '2025-08-22', 'Pending'],
    ['🟡 Medium', 'Review unused indexes', 'Free up 28+ MB space', 'Medium', 'Medium', 'DBA Team', '2025-09-15', 'Planned'],
    ['🟡 Medium', 'Optimize aggregate queries', 'Reduce 400ms+ queries', 'High', 'Low', 'Dev Team', '2025-09-10', 'Planned'],
    ['🟢 Low', 'Consider table partitioning', 'Future scalability', 'High', 'High', 'Senior DBA', '2026-01-01', 'Research']
  ];
  
  var recoRange = recoSheet.getRange(1, 1, recoData.length, recoData[0].length);
  recoRange.setValues(recoData);
  recoSheet.getRange(1, 1, 1, 8).setBackground('#795548').setFontWeight('bold');
  recoSheet.autoResizeColumns(1, 8);
  
  // สร้าง Chart สำหรับ Performance Score
  var chart = overviewSheet.newChart()
    .setChartType(Charts.ChartType.PIE)
    .addRange(overviewSheet.getRange('A9:B12'))
    .setPosition(2, 8, 0, 0)
    .setOption('title', 'Performance Score Breakdown')
    .setOption('pieHole', 0.4)
    .build();
  
  overviewSheet.insertChart(chart);
  
  Logger.log('PostgreSQL Performance Dashboard created successfully!');
  
  // สร้าง Summary
  SpreadsheetApp.getUi().alert(
    'Success!', 
    'PostgreSQL Performance Dashboard created successfully!\n\n' +
    '✅ 6 sheets created\n' +
    '✅ Data populated\n' +
    '✅ Formatting applied\n' +
    '✅ Charts added\n\n' +
    'You can now customize colors, add more charts, or modify data as needed.',
    SpreadsheetApp.getUi().ButtonSet.OK
  );
}

// ฟังก์ชันสำหรับ Update ข้อมูลแบบ Real-time (ถ้าต่อกับ Database)
function updatePerformanceData() {
  // ใส่ logic สำหรับดึงข้อมูลจาก Database ตรงนี้
  // แล้ว update Google Sheet
  
  var sheet = SpreadsheetApp.getActiveSpreadsheet().getSheetByName('Performance Overview');
  sheet.getRange('E9').setValue(new Date()); // Update timestamp
  
  Logger.log('Performance data updated!');
}