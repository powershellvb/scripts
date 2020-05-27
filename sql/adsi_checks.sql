
DECLARE @contnumber INT 

if exists (select * from tempdb.sys.all_objects where type='U' and name like '#ADContainer%')
	DROP TABLE #ADContainer
CREATE TABLE #ADContainer(
    cid INT
	, contname NVARCHAR(256)
)

if exists (select * from tempdb.sys.all_objects where type='U' and name like '#ADData%')
	DROP TABLE #ADData
CREATE TABLE #ADData(
	[Name] NVARCHAR(256)
	, distinguishedName NVARCHAR(256)
	, usnCreated    INT
)

-- Specify the Container name.
INSERT INTO #ADContainer (cid, contname)
values (1, 'OU=File3,OU=DIP HSET4L,OU=Services,DC=DETNSW,DC=WIN')
,(2, 'OU=File3,OU=DIP MDI,OU=Services,DC=DETNSW,DC=WIN')
 
SELECT @contnumber = count(cid) from #ADContainer

WHILE @contnumber >= 1 
BEGIN
	DECLARE @Query NVARCHAR (2000)
	DECLARE @Filter NVARCHAR(200)
	DECLARE @Rowcount INT
	DECLARE @container NVARCHAR(256)

	SELECT @container = contname FROM #ADContainer WHERE cid = @contnumber
	select @Filter =''

	WHILE ISNULL(@rowcount,901)  = 901 
	BEGIN
		SELECT @Query = N'
		SELECT top 901
				[Name], distinguishedName, uSNCreated
		FROM OpenQuery(
		   ADSI,
		   ''SELECT name, distinguishedName, uSNCreated
		   FROM ''''LDAP://pw0991rwdc0101.detnsw.win/' + @container + '''''
		   WHERE objectClass = ''''Computer''''
		   ' + @filter + '
		   ORDER BY usnCreated'') AS tblADSI '
	              
		INSERT INTO #ADData 
			exec sp_executesql @Query

		SELECT @Rowcount = @@ROWCOUNT

		SELECT @Filter = N'and usnCreated > '+ LTRIM(STR((SELECT MAX(usnCreated) FROM #ADData)))

	END
	SET @contnumber -= 1
	SET @Rowcount = 901
END

SELECT [Name]            
        , distinguishedName
		, uSNCreated
FROM #ADData
order by [Name]

if exists (select * from tempdb.sys.all_objects where type='U' and name like '#ADData%')
	DROP TABLE #ADData
if exists (select * from tempdb.sys.all_objects where type='U' and name like '#ADContainer%')
DROP TABLE #ADContainer