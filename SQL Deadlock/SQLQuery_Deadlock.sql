
--1. Identify Deadlock in PAAS SQL DB
WITH CTE AS (SELECT 
    CAST(event_data AS XML)  AS [target_data_XML]FROM 
    sys.fn_xe_telemetry_blob_target_read_file('dl', null, null, null))SELECT 
    target_data_XML.value('(/event/@timestamp)[1]', 'DateTime2') AS Timestamp,    target_data_XML.query('/event/data[@name=''xml_report'']/value/deadlock') AS deadlock_xml,    target_data_XML.query('/event/data[@name=''database_name'']/value').value('(/value)[1]', 'nvarchar(100)') AS db_name
FROM CTE
 

--=====================================================

--2. Check for OPEN TRANSACTION
dbcc opentran

--=====================================================

--3. Check System Processes
select * from sys.sysprocesses where blocked <>0

--=====================================================

--4. Check Stats:
SELECT s.session_id
    ,r.STATUS
    ,r.blocking_session_id AS 'blocked_by'
    ,r.wait_type
    ,r.wait_resource
    ,CONVERT(VARCHAR, DATEADD(ms, r.wait_time, 0), 8) AS 'wait_time'
    ,r.cpu_time
    ,r.logical_reads
    ,r.reads
    ,r.writes
    ,CONVERT(varchar, (r.total_elapsed_time/1000 / 86400))+ 'd ' +
     CONVERT(VARCHAR, DATEADD(ms, r.total_elapsed_time, 0), 8)   AS 'elapsed_time'
    ,CAST((
            '<?query --  ' + CHAR(13) + CHAR(13) + Substring(st.TEXT, (r.statement_start_offset / 2) + 1, (
                    (
                        CASE r.statement_end_offset
                            WHEN - 1
                                THEN Datalength(st.TEXT)
                            ELSE r.statement_end_offset
                            END - r.statement_start_offset
                        ) / 2
                    ) + 1) + CHAR(13) + CHAR(13) + '--?>'
            ) AS XML) AS 'query_text'
    ,COALESCE(QUOTENAME(DB_NAME(st.dbid)) + N'.' + QUOTENAME(OBJECT_SCHEMA_NAME(st.objectid, st.dbid)) + N'.' + 
     QUOTENAME(OBJECT_NAME(st.objectid, st.dbid)), '') AS 'stored_proc'
    --,qp.query_plan AS 'xml_plan'  -- uncomment (1) if you want to see plan
    ,r.command
    ,s.login_name
    ,s.host_name
    ,s.program_name
    ,s.host_process_id
    ,s.last_request_end_time
    ,s.login_time
    ,r.open_transaction_count
FROM sys.dm_exec_sessions AS s
INNER JOIN sys.dm_exec_requests AS r ON r.session_id = s.session_id
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS st
--OUTER APPLY sys.dm_exec_query_plan(r.plan_handle) AS qp -- uncomment (2) if you want to see plan
WHERE r.wait_type NOT LIKE 'SP_SERVER_DIAGNOSTICS%'
    OR r.session_id != @@SPID
ORDER BY r.cpu_time DESC
    ,r.STATUS
    ,r.blocking_session_id
    ,s.session_id
 
 --================================================

 --5. Check for Deadlock XML:
 WITH cteDeadLocks ([Deadlock_XML]) AS (
  SELECT [Deadlock_XML] = CAST(target_data AS XML) 
  FROM sys.dm_xe_sessions AS xs
  INNER JOIN sys.dm_xe_session_targets AS xst 
  ON xs.[address] = xst.event_session_address
  WHERE xs.[name] = 'system_health'
  AND xst.target_name = 'ring_buffer'
 )
SELECT 
  Deadlock_XML = x.Graph.query('(event/data/value/deadlock)[1]')  
, when_occurred = x.Graph.value('(event/data/value/deadlock/process-list/process/@lastbatchstarted)[1]', 'datetime2(3)') 
, DB = DB_Name(x.Graph.value('(event/data/value/deadlock/process-list/process/@currentdb)[1]', 'int')) --Current database of the first listed process 
FROM (
 SELECT Graph.query('.') AS Graph 
 FROM cteDeadLocks c
 CROSS APPLY c.[Deadlock_XML].nodes('RingBufferTarget/event[@name="xml_deadlock_report"]') AS Deadlock_Report(Graph)
) AS x
ORDER BY when_occurred desc;

--==================================

--6. XML Deadlock
   SELECT CAST(event_data AS xml), timestamp_utc  
   FROM sys.fn_xe_file_target_read_file(  
        N'system_health*.xel', DEFAULT, DEFAULT, DEFAULT)  
   WHERE object_name = 'xml_deadlock_report'  
      AND  timestamp_utc > dateadd(WEEK, -1, sysutcdatetime())  
   ORDER BY timestamp_utc DESC
