WITH XMLNAMESPACES ('http://schemas.microsoft.com/sqlserver/2004/07/showplan' AS sp)
SELECT
    D.session_id, 
    D.blocking_session_id, 
    D.database_id, 
    T1.text AS blocking_statement, 
    T2.text AS blocked_statement
FROM sys.dm_exec_requests D
CROSS APPLY sys.dm_exec_sql_text(D.sql_handle) T1
JOIN sys.dm_exec_connections C
ON D.blocking_session_id = C.session_id
CROSS APPLY sys.dm_exec_sql_text(C.most_recent_sql_handle) T2
WHERE D.blocking_session_id <> 0;
