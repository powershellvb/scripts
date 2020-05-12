-- Extract Deadlock from ring buffer target
SELECT XEvent.query('(event/data/value/deadlock)[1]') AS DeadlockGraph
FROM (
    SELECT XEvent.query('.') AS XEvent
    FROM (
        SELECT CAST(target_data AS XML) AS TargetData
        FROM sys.dm_xe_session_targets st
        INNER JOIN sys.dm_xe_sessions s 
ON s.address = st.event_session_address
        WHERE s.NAME = 'system_health'
            AND st.target_name = 'ring_buffer'
        ) AS Data
CROSS APPLY TargetData.nodes('RingBufferTarget/event[@name="xml_deadlock_report"]') AS XEventData(XEvent)
) AS source;

-- to read XML - https://www.sqlshack.com/understanding-the-xml-description-of-the-deadlock-graph-in-sql-server/
-- save the result as .xdl to view the deadlock graph

-- Extract Deadlock from the log file
CREATE TABLE #errorlog (
            LogDate DATETIME 
            , ProcessInfo VARCHAR(100)
            , [Text] VARCHAR(MAX)
            );
DECLARE @tag VARCHAR (MAX) , @path VARCHAR(MAX);
INSERT INTO #errorlog EXEC sp_readerrorlog;
SELECT @tag = text
FROM #errorlog 
WHERE [Text] LIKE 'Logging%MSSQL\Log%'; --log name
DROP TABLE #errorlog;
SET @path = SUBSTRING(@tag, 38, CHARINDEX('MSSQL\Log', @tag) - 29);
SELECT 
  CONVERT(xml, event_data).query('/event/data/value/child::*') AS DeadlockReport,
  CONVERT(xml, event_data).value('(event[@name="xml_deadlock_report"]/@timestamp)[1]', 'datetime') 
  AS Execution_Time
FROM sys.fn_xe_file_target_read_file(@path + '\system_health*.xel', NULL, NULL, NULL)
WHERE OBJECT_NAME like 'xml_deadlock_report';

--Event Session
CREATE EVENT SESSION [deadlock_capture] ON SERVER 

--Events to track Lock_deadlock and Lock_deadlock_chain
ADD EVENT sqlserver.lock_deadlock(
    ACTION(sqlserver.sql_text)),
ADD EVENT sqlserver.lock_deadlock_chain(
    ACTION(sqlserver.sql_text))

-- TARGET to use, for this case, a file
ADD TARGET package0.event_file(SET filename=N'deadlock_capture')

--The event session advanced parameters, you can see that the event starts automatically
WITH (MAX_MEMORY=4096 KB,EVENT_RETENTION_MODE=ALLOW_SINGLE_EVENT_LOSS,MAX_DISPATCH_LATENCY=30 
SECONDS,MAX_EVENT_SIZE=0 KB,MEMORY_PARTITION_MODE=NONE,TRACK_CAUSALITY=OFF,STARTUP_STATE=ON)

GO

--TO CREATE DEADLOCK
BEGIN TRAN

UPDATE tableA
set [value] = 'C1'
WHERE id = 1

WAITFOR DELAY '00:00:05'

UPDATE tableB
set [value] = 'C2'
WHERE id = 1

-- TRAN 2
BEGIN TRAN

UPDATE tableB
set [value] = 'C2'
WHERE id = 1

WAITFOR DELAY '00:00:05'

UPDATE tableA
set [value] = 'C1'
WHERE id = 1