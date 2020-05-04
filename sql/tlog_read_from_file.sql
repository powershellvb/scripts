USE dbName

SELECT 
 [Current LSN],    
 [Transaction ID],
 [Transaction Name],
     Operation,
     [Begin Time]
FROM 
    fn_dblog(NULL, NULL) 
WHERE [Operation] = 'LOP_DELETE_ROWS' 
GO

use master
-- Find DELETE ROWS
SELECT [Current LSN], [Transaction ID], [Transaction Name], [Operation], [Begin Time], [PartitionID], [TRANSACTION SID]
FROM fn_dump_dblog (NULL, NULL, N'DISK', 1, N'D:\MSSQL\MSSQL13.CESDBI1\MSSQL\Backup\SI_Stage\SI_Stage_backup_20200505010003.trn', /*change this*/
DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT)
WHERE Operation = 'LOP_DELETE_ROWS'
GO

-- FIND BEGIN TIME
SELECT [Current LSN], 	[Transaction ID], 
	[Transaction Name], 
	[Operation], 
	[Begin Time],
	SUSER_SNAME([TRANSACTION SID]) as [LoginName]
FROM fn_dump_dblog (NULL, NULL, N'DISK', 1, N'D:\MSSQL\MSSQL13.CESDBI1\MSSQL\Backup\SI_Stage\SI_Stage_backup_20200505010003.trn', /*change this*/
	DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
	DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
	DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
	DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
	DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT)
WHERE [Transaction ID] = '0000:b9f1412d' /*change this*/
	AND Operation = 'LOP_BEGIN_XACT'
GO

--FIND OBJECT ID
USE DBName

SELECT so.* 
FROM sys.objects so
INNER JOIN sys.partitions sp on so.object_id = sp.object_id
WHERE partition_id = 281474978938880
GO

--DOING THEM TOGETHER
USE DBName

WITH CTE
as
       (SELECT [Transaction ID], count(*) as DeletedRows
       FROM fn_dump_dblog (NULL, NULL, N'DISK', 1, N'D:\ReadingDBLog_201503022236.trn',
       DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
       DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
       DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
       DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
       DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT)
       WHERE Operation = ('LOP_DELETE_ROWS')
       AND [PartitionId] = (SELECT sp.partition_id
                            FROM sys.objects so
                            INNER JOIN sys.partitions sp on so.object_id = sp.object_id
                            WHERE name = 'Location')
       GROUP BY [Transaction ID]
       )
SELECT [Current LSN], a.[Transaction ID], [Transaction Name], [Operation], [Begin Time], SUSER_SNAME([TRANSACTION SID]) as LoginName, DeletedRows
FROM fn_dump_dblog (NULL, NULL, N'DISK', 1, N'D:\ReadingDBLog_201503022236.trn',
	DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
	DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
	DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
	DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT,
	DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT, DEFAULT) as a
INNER JOIN cte on a.[Transaction ID] = cte.[Transaction ID]
WHERE Operation = ('LOP_BEGIN_XACT')
GO