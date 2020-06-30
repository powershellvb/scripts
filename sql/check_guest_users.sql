if exists (select * from tempdb.sys.all_objects where [name] like '#guestusers%' and [type] = 'u')
	drop table #guestusers

create table #guestusers (
dbname nvarchar(256)
,dbprincipal sysname
,[type] char(1)
,objname nvarchar(256)
,major_id int
,class_desc nvarchar(120)
,[permission_name] nvarchar(256)
,state_desc nvarchar(120)
)

Declare @cmd varchar(2000)
set @cmd = 'IF ''?'' NOT IN(''master'', ''model'', ''msdb'', ''tempdb'', ''monitor'')
BEGIN 
USE [?]
SELECT db_name() as dbname, dpr.name as dbprincipal, dpr.type, coalesce(obj.name,null,'''') as objname
, dpe.major_id, dpe.class_desc, dpe.permission_name, dpe.state_desc
FROM sys.database_principals dpr
INNER JOIN sys.database_permissions dpe
ON dpr.principal_id = dpe.grantee_principal_id
left join sys.all_objects obj on dpe.major_id = obj.object_id
WHERE dpr.name = ''guest'' and dpe.state_desc != ''deny''
END'
insert into #guestusers (dbname, dbprincipal, [type], objname, major_id, class_desc, [permission_name], state_desc)
exec sp_msforeachdb @cmd


select * from #guestusers

if exists (select * from tempdb.sys.all_objects where [name] like '#guestusers%' and [type] = 'u')
	drop table #guestusers