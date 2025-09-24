USE [CompanyMonitor]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

IF NOT EXISTS(SELECT *
FROM sys.tables
WHERE object_id = OBJECT_ID('[dbo].[SQLAUditLog]'))
BEGIN
	CREATE TABLE [dbo].[SQLAuditLog]
	(
		[SQLAuditLogID] [bigint] NOT NULL IDENTITY(1,1),
		[event_UTC_time] [datetime2](7) NOT NULL,
		[event_local_time] [datetime2] NOT NULL,
		[action_id] [varchar](4) NOT NULL,
		[Action] [varchar](40) NOT NULL,
		[succeeded] [bit] NOT NULL,
		[session_id] [smallint] NOT NULL,
		[object_id] [int] NULL,
		[object_name] [nvarchar](128) NULL,
		[session_server_principal_name] [nvarchar](128) NOT NULL,
		[database_name] [nvarchar](128) NULL,
		[Statement] [nvarchar](4000) NULL,
		[Connection_IP] [nvarchar](300) NULL,
		CONSTRAINT PK_SQLAUditLog PRIMARY KEY CLUSTERED ([SQLAuditLogID])
	) ON [PRIMARY]
END
GO

IF NOT EXISTS (SELECT *
FROM sys.indexes
WHERE name = 'CIX_SQLAUditLog_event_UTC_time' AND object_id = OBJECT_ID('[dbo].[SQLAUditLog]'))
BEGIN
	CREATE NONCLUSTERED INDEX [CIX_SQLAUditLog_event_UTC_time] ON [dbo].[SQLAUditLog]([event_UTC_time] DESC)
	WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON)
END
GO



