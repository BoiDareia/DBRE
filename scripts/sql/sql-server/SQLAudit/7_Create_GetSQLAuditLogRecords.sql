USE CompanyMonitor
GO

IF EXISTS (SELECT *
FROM sys.procedures
WHERE object_id = OBJECT_ID('dbo.GetSQLAuditLogRecords'))
DROP PROC dbo.GetSQLAuditLogRecords
GO

/*
Execute the stored procedure to:
    (a) get the latest SQL audit events directly from the file
    (b) retrieve all processed SQL Audit records from dbo.SQLAuditLog, from the id that was ast processed.
    (c) after retrieval, update the id that was last processed in the LastProcessed table 
    (d) after retrieval, delete all retrieved SQL Audit records, to conserve space, IF @DeleteRecordsPostRetrieval is enabled.

    Test Usage
    EXEC CompanyMonitor.dbo.GetSQLAuditLogRecords
*/
CREATE PROCEDURE dbo.GetSQLAuditLogRecords
AS
BEGIN
    SET NOCOUNT ON

    DECLARE @DeleteRecordsPostRetrieval BIT = 0
    --> Enable on PROD
    DECLARE @LastProcessId BIGINT
    DECLARE @NewLastProcessId BIGINT

    SELECT @LastProcessId = LastProccessedId
    FROM dbo.LastProcessed
    WHERE ProcessedTable = N'SQLAuditLog'

    -- first get the latest SQL audit events directly from the file.
    EXEC dbo.sql_auditlog_process

    SELECT @NewLastProcessId = MAX(SQLAuditLogID)
    FROM dbo.SQLAuditLog

    SELECT
        [event_UTC_time]
        , [event_local_time]
        , [Action]
        , [succeeded]
        , [session_id]
        , [object_name]
        , [session_server_principal_name]
        , [database_name]
        , [Statement]
        , [Connection_IP]
    FROM dbo.SQLAuditLog
    WHERE [SQLAuditLogID] BETWEEN ISNULL(@LastProcessId,0) AND ISNULL(@NewLastProcessId,0)

    BEGIN TRY
        BEGIN TRAN

        IF (@LastProcessId IS NULL)
        BEGIN
        INSERT INTO dbo.LastProcessed
            (ProcessedTable, LastProccessedId)
        VALUES(N'SQLAuditLog', @NewLastProcessId)
    END
        ELSE
        BEGIN
        UPDATE dbo.LastProcessed SET LastProccessedId = @NewLastProcessId
            WHERE ProcessedTable = N'SQLAuditLog'
    END

        IF(@DeleteRecordsPostRetrieval=1)
        BEGIN
        DELETE dbo.SQLAuditLog
            WHERE [SQLAuditLogID] <= @NewLastProcessId
    END

        COMMIT TRAN
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN
    END CATCH
END
GO

GRANT EXECUTE ON dbo.GetSQLAuditLogRecords TO splunk
GO
