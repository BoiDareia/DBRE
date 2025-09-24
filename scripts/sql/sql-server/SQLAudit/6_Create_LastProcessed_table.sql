USE CompanyMonitor
GO

IF NOT EXISTS(SELECT *
FROM sys.tables
WHERE object_id = OBJECT_ID('dbo.LastProcessed'))
BEGIN
    CREATE TABLE dbo.LastProcessed
    (
        ProcessedTable NVARCHAR(128) NOT NULL,
        LastProccessedId BIGINT NULL,
        PRIMARY KEY CLUSTERED (ProcessedTable ASC)
    )
END