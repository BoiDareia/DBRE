USE identityprovider
GO

--auditentries per gateway/client except user login/logout
SELECT SubjectIdentifier,Action,COUNT(*) [count] FROM dbo.AuditEntries (NOLOCK)
WHERE [When] > '2024-10-09 17:00:00' 
AND [When] < '2024-10-09 19:00:00' 
AND Action NOT  IN ( 'User Login Success','User Logout Success')
GROUP BY SubjectIdentifier,Action
ORDER BY 3 DESC

--auditentries for user login/logout (randomized sibjectidentifier, cant aggregate)
SELECT Action,COUNT(*) [count] FROM dbo.AuditEntries (NOLOCK)
WHERE [When] > '2024-10-09 17:00:00' 
AND [When] < '2024-10-09 19:00:00' 
AND Action  IN ( 'User Login Success','User Logout Success')
GROUP BY Action
ORDER BY 2 desc