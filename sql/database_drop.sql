USE master;

declare @db NVARCHAR(128) = 'AG_TEMP1'
declare @cmd NVARCHAR(MAX)
SET @cmd = 'ALTER DATABASE [' + @db + '] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE [' + @db + ']'

--print @cmd
exec sp_executesql @cmd