IF ((SELECT OBJECT_ID('eSuite_item_itm_validity_check')) IS NOT NULL)
DROP PROCEDURE eSuite_item_itm_validity_check
GO
CREATE PROCEDURE eSuite_item_itm_validity_check (
	-- Standard parameters to ALL grids, >>DON'T CHANGE<<
	@CurUser INT=NULL,
	@ExtGridFilter NVARCHAR(MAX)=NULL,-- Column to use to calc the group sub-totals
	@ExtGridGroup NVARCHAR(100)=NULL,-- Column to use to calc the group sub-totals
	@ExtGridSummary NVARCHAR(max)=NULL,-- Summary configuration to generate summary table
	@ExtGridStep INT=NULL,-- [1=Generate CREATE DDL|2=Fill temp table|3=Retrieve data`|4=Update data on temp table]
	@ExtGridSession NVARCHAR(10)=NULL,-- Grid session number
	@ExtGridStart INT=NULL,-- Position to start the result set, used with Step 3 and 2
	@ExtMaxRecords INT=NULL,-- Records per page
	@ExtGridSort NVARCHAR(4000)=NULL,-- Column to use to sort the result set
	@ExtGridOutput NVARCHAR(100)=NULL,-- Output result
	@ExtKeyList NVARCHAR(max)=NULL,-- List with the key values used to update the temp table (see Step 4)
	@ExtLookUp NVARCHAR(max)=NULL,-- Look up condition to find a specific record, used with Step 3
	@ExtLookUpStart INTEGER=NULL,-- Position to start the look up search, used with Step 3 and LookUp
	@PostData NVARCHAR(max)=NULL, -- XML list of filters
	@SubTable NVARCHAR(100)=NULL, -- Subtable for reports
	@Top INT=NULL,-- Maximum number of records to be returned
	@F1000 NVARCHAR(5)=NULL,-- Target filter

	--Specific parameters and filters
	@ITEM_ITM_FILTER_TABLE NVARCHAR(100)=NULL, -- Item filter table name
	
	@TargetMode NVARCHAR(1)=NULL,--Target mode [0-Single Target(PAL)|1-Multi target|2-Multi tenant]
	@TargetBase NVARCHAR(5)=NULL,--Target from System.INI

	-- SELLABILITY VALIDATORS
		@MissObj bit=0, -- checkbox - Missing in Main Item 
		@MissPos bit=0, -- checkbox - Missing POS Record 
		@MissPrice bit=0, -- checkbox - Missing Price Record
		@MissDpt bit=0, -- checkbox - Bad or Missing Sub-Dept/Dept
		@BadTare bit=0, -- checkbox - Bad Tare Link 
		@ZeroPrice bit=0, -- checkbox - Zero Price and F1120 not EZ
		@BadObjAlt bit=0, -- checkbox - Conflict between Main and Alternate Code
		@BadKit bit=0, -- checkbox - Bad Link in Kit Table
		@BadScaleTxt bit=0, -- checkbox - Bad Link to Scale Text
		@MultiplePriceLikeCode bit=0, -- checkbox - Like codes with different prices.
		@BadBtlLnk bit=0, -- checkbox - Bad Bottle Link 
	-- QUALITY VALIDATORS
		@MissCost bit=0, -- checkbox - Missing Cost Record 
		@MissLoc bit=0, -- checkbox - Missing Location Record
		@MissCat bit=0, -- checkbox - Bad or Missing category
		@MissFam bit=0, -- checkbox - Bad or Missing Family
		@MissCls bit=0, -- checkbox - Bad or Missing Classification 
		@BadCode bit=0, -- checkbox - Bad Report Code
		@MissVnd bit=0, -- checkbox - Bad or Missing Vendor id
		@BlankVndCode bit=0, -- checkbox - Blank Vendor Code
		@BadVndAuth bit=0, -- checkbox - Issue with Authorized Vendor Flag
		@ZeroCost bit=0, -- checkbox - Zero or missing Cost
		@KitSplitInv bit=0, -- checkbox - Kit or Split Item wiht Inventory
		@MultiVndCode bit=0, -- checkbox - Multiple Items with Same Vendor Code
		@PriceValidation bit=0 -- checkbox - Check That Prices and quantities aren't greater than 9999 (due to scans in the wrong fields)
	)
AS
BEGIN
	DECLARE @TableKeys eSuite_base_grid_keys
	DECLARE @Sql nvarchar(MAX)=N''
	DECLARE @Prm NVARCHAR(MAX)

	IF @ExtGridSession IS NULL SET @ExtGridSession=N''

	-- Default order field
	IF (ISNULL(@ExtGridSort,'')='' AND ISNULL(@ExtGridGroup,'')='') SET @ExtGridSort=N'F01,TablePriority,SRC,FLD'
	ELSE IF @ExtGridGroup=@ExtGridSort SET @ExtGridSort=@ExtGridGroup + N',TablePriority,SRC,FLD'

	--Protect the filter table name from SQL injection
	IF (NULLIF(@ITEM_ITM_FILTER_TABLE,'') IS NULL) OR ((SELECT OBJECT_ID('TEMPDB..'+@ITEM_ITM_FILTER_TABLE)) IS NULL)
		SET @ITEM_ITM_FILTER_TABLE=NULL

	IF @ExtGridStep IS NULL
	BEGIN
		CREATE TABLE #ITEM_ITM_VALIDITY_CHECK(
			F01 VARCHAR(13), 
			F29 VARCHAR(60),
			F155 VARCHAR(30),
			F22 VARCHAR(30),
			F02 VARCHAR(40),
			ItmDescr VARCHAR(200),
			TablePriority int,
			SRC VARCHAR(50),
			PK XML, 
			FLD VARCHAR(50), 
			DESCR VARCHAR(250),
			DATATYPE VARCHAR(100),
			VALUE VARCHAR(250),
			REASON VARCHAR(500)
		)
		SET @ExtGridStep=2
	END
	ELSE
	IF @ExtGridStep=1
	BEGIN
		SELECT SQL='IF OBJECT_ID(''tempdb..#ITEM_ITM_VALIDITY_CHECK'+@ExtGridSession+''') IS NOT NULL DROP TABLE #ITEM_ITM_VALIDITY_CHECK'+@ExtGridSession+';'+
		'CREATE TABLE #ITEM_ITM_VALIDITY_CHECK'+@ExtGridSession+' (
			F01 VARCHAR(13), 
			F29 VARCHAR(60),
			F155 VARCHAR(30),
			F22 VARCHAR(30),
			F02 VARCHAR(40),
			ItmDescr VARCHAR(200),
			TablePriority int, 
			SRC VARCHAR(50),
			PK XML, 
			FLD VARCHAR(50), 
			DESCR VARCHAR(250),
			DATATYPE VARCHAR(100),
			VALUE VARCHAR(250),
			REASON VARCHAR(500)
		)
		'
		RETURN
	END

	IF @ExtGridStep=2
	BEGIN
		SELECT @F1000=F1056 FROM CLK_TAB WHERE F1185=@CurUSer AND NULLIF(F1056,'') IS NOT NULL

		SET @prm = N'@F1000 VARCHAR(10), @TargetMode NVARCHAR(1), @TargetBase NVARCHAR(5)'
		-- Missing in Main Item 
		IF ISNULL(@MissObj,1)=1 
		BEGIN 
			SET @SQL = N'
			INSERT INTO #ITEM_ITM_VALIDITY_CHECK'+@ExtGridSession+N'
				SELECT DISTINCT TMP.F01, 
								NULL AS F29, 
								NULL AS F155, 
								NULL AS F22, 
								ISNULL(POS.F02,'''') AS F02, 
								ISNULL(POS.F02,'''') AS ItmDescr,
								1 AS TablePriority,
								''OBJ_TAB'' AS SRC,
								''<PK></PK>'' AS PK,
								NULL AS FLD, 
								NULL AS DESCR, 
								NULL AS DATATYPE, 
								NULL AS VALUE, 
								''Missing Main Item'' AS REASON
				FROM '+@ITEM_ITM_FILTER_TABLE+N' TMP 
				LEFT JOIN OBJ_TAB OBJ ON OBJ.F01=TMP.F01
				LEFT JOIN (SELECT DISTINCT F01, MAX(F02) AS F02 FROM POS_TAB WHERE @F1000 IS NULL OR F1000=@F1000 GROUP BY F01) POS ON POS.F01=TMP.F01
				WHERE OBJ.F01 IS NULL'	
			EXEC sp_executesql @SQL, @PRM, @F1000,@TargetMode, @TargetBase
		END
		-- Missing POS Record
		IF ISNULL(@MissPOS,1)=1 
		BEGIN 
			SET @SQL = N'
			INSERT INTO #ITEM_ITM_VALIDITY_CHECK'+@ExtGridSession+N'
				SELECT DISTINCT TMP.F01,
								ISNULL(OBJ.F29,'''') AS F29, 
								ISNULL(OBJ.F155,'''') AS F155, 
								ISNULL(OBJ.F22,'''') AS F22, 
								NULL AS F02,
								CONCAT(ISNULL(OBJ.F29,''''),'' '',ISNULL(OBJ.F155,''''),'' '',ISNULL(OBJ.F22,'''')) AS ItmDescr,
								2 AS TablePriority,
								''POS_TAB'' AS SRC,
								CONCAT(''<PK>'',(Select ''Target Identifier'' as d,'''' as v for XML RAW(''F1000'')),''</PK>'') AS PK,
								NULL AS FLD, 
								NULL AS DESCR, 
								NULL AS DATATYPE, 
								NULL AS VALUE, 
								''Missing POS Record'' AS REASON
				FROM '+@ITEM_ITM_FILTER_TABLE+N' TMP 
				LEFT JOIN OBJ_TAB OBJ ON OBJ.F01=TMP.F01
				LEFT JOIN POS_TAB POS ON POS.F01=TMP.F01 AND (@F1000 IS NULL OR POS.F1000=@F1000)
				WHERE POS.F01 IS NULL'
			EXEC sp_executesql @SQL, @PRM, @F1000, @TargetMode, @TargetBase
		END 
		-- Missing PRICE Record
		IF ISNULL(@MissPrice,1)=1 
		BEGIN 
			SET @SQL = N'
			INSERT INTO #ITEM_ITM_VALIDITY_CHECK'+@ExtGridSession+N'
				SELECT DISTINCT TMP.F01,
								ISNULL(OBJ.F29,'''') AS F29, 
								ISNULL(OBJ.F155,'''') AS F155, 
								ISNULL(OBJ.F22,'''') AS F22, 
								ISNULL(POS.F02,'''') AS F02,
								CONCAT(ISNULL(OBJ.F29,''''),'' '',ISNULL(OBJ.F155,''''),'' '',ISNULL(OBJ.F22,''''),'' '',ISNULL(POS.F02,'''')) AS ItmDescr,
								3 AS TablePriority,
								''PRICE_TAB'' AS SRC,
								CONCAT(''<PK>'',(Select ''Target Identifier'' as d,'''' as v for XML RAW(''F1000'')),(Select ''Price level'' as d,'''' as v for XML RAW(''F126'')),''</PK>'') AS PK,
								NULL AS FLD, 
								NULL AS DESCR, 
								NULL AS DATATYPE, 
								NULL AS VALUE, 
								''Missing PRICE Record'' AS REASON
				FROM '+@ITEM_ITM_FILTER_TABLE+N' TMP 
				LEFT JOIN OBJ_TAB OBJ ON OBJ.F01=TMP.F01
				LEFT JOIN PRICE_TAB PRI ON PRI.F01=TMP.F01 AND (@F1000 IS NULL OR PRI.F1000=@F1000)
				LEFT JOIN (SELECT DISTINCT F01, MAX(F02) AS F02 FROM POS_TAB WHERE @F1000 IS NULL OR F1000=@F1000 GROUP BY F01) POS ON POS.F01=TMP.F01
				WHERE PRI.F01 IS NULL'
			EXEC sp_executesql @SQL, @PRM, @F1000, @TargetMode, @TargetBase
		END 
		-- Bad or Missing Sub-Dept/Dept
		IF ISNULL(@MissDpt,1)=1 
		BEGIN 
			SET @SQL = N'
			INSERT INTO #ITEM_ITM_VALIDITY_CHECK'+@ExtGridSession+N'
				SELECT DISTINCT TMP.F01,
								ISNULL(OBJ.F29,'''') AS F29, 
								ISNULL(OBJ.F155,'''') AS F155, 
								ISNULL(OBJ.F22,'''') AS F22, 
								ISNULL(POS.F02,'''') AS F02,
								CONCAT(ISNULL(OBJ.F29,''''),'' '',ISNULL(OBJ.F155,''''),'' '',ISNULL(OBJ.F22,''''),'' '',ISNULL(POS.F02,'''')) AS ItmDescr,
								CASE WHEN SDP.F04 IS NULL THEN 2 ELSE 5 END AS TablePriority,
								CASE WHEN SDP.F04 IS NULL THEN ''POS_TAB'' ELSE ''SDP_TAB'' END  AS SRC,
								CASE WHEN SDP.F04 IS NULL THEN CONCAT(''<PK>'',(Select ''Target Identifier'' as d,POS.F1000 as v for XML RAW(''F1000'')),''</PK>'')
									ELSE CONCAT(''<PK>'',(Select ''Sub-Department code'' as d,SDP.F04 as v for XML RAW(''F04'')),''</PK>'')
									END AS PK, 
								CASE WHEN SDP.F04 IS NULL THEN ''F04'' ELSE ''F03'' END AS FLD, 
								RBF.F1454 AS DESCR, 
								CASE RBF.F1458
									WHEN ''dtString'' THEN ''string''
									WHEN ''dtDateTime'' THEN ''TS''
									WHEN ''dtCurrency'' THEN ''$''
									WHEN ''dtDouble'' THEN ''float''
									WHEN ''dtInteger'' THEN ''int''
									ELSE ''string''                        
									END AS DATATYPE, 
								CASE WHEN SDP.F04 IS NULL THEN POS.F04 
									WHEN DPT.F03 IS NULL THEN SDP.F03
									ELSE NULL 
									END  AS VALUE, 	
								CASE WHEN SDP.F04 IS NULL THEN ''Missing sub-Department'' ELSE ''Missing Department'' END AS REASON
				FROM '+@ITEM_ITM_FILTER_TABLE+N' TMP 
				LEFT JOIN OBJ_TAB OBJ ON OBJ.F01=TMP.F01
				JOIN POS_TAB POS ON POS.F01=TMP.F01 AND (@F1000 IS NULL OR POS.F1000=@F1000)
				LEFT JOIN SDP_TAB SDP ON SDP.F04=POS.F04
				LEFT JOIN DEPT_TAB DPT ON DPT.F03=SDP.F03
				JOIN RB_FIELDS RBF ON RBF.F1452=''POS_TAB'' AND RBF.F1453=CASE WHEN SDP.F04 IS NULL THEN ''F04'' ELSE ''F03'' END
				WHERE SDP.F04 IS NULL OR DPT.F03 IS NULL'
			EXEC sp_executesql @SQL, @PRM, @F1000, @TargetMode, @TargetBase
		END 
		-- Bad Tare Link 
		IF ISNULL(@BadTare,1)=1 
		BEGIN 
			SET @SQL = N'
			INSERT INTO #ITEM_ITM_VALIDITY_CHECK'+@ExtGridSession+N'
				SELECT DISTINCT TMP.F01,
								ISNULL(OBJ.F29,'''') AS F29, 
								ISNULL(OBJ.F155,'''') AS F155, 
								ISNULL(OBJ.F22,'''') AS F22, 
								ISNULL(POS.F02,'''') AS F02,
								CONCAT(ISNULL(OBJ.F29,''''),'' '',ISNULL(OBJ.F155,''''),'' '',ISNULL(OBJ.F22,''''),'' '',ISNULL(POS.F02,'''')) AS ItmDescr,
								2 AS TablePriority,
								''POS_TAB'' AS SRC,
								CONCAT(''<PK>'',(Select ''Target Identifier'' as d,POS.F1000 as v for XML RAW(''F1000'')),''</PK>'') AS PK, 
								''F06'' AS FLD, 
								RBF.F1454 AS DESCR, 
								CASE RBF.F1458
									WHEN ''dtString'' THEN ''string''
									WHEN ''dtDateTime'' THEN ''TS''
									WHEN ''dtCurrency'' THEN ''$''
									WHEN ''dtDouble'' THEN ''float''
									WHEN ''dtInteger'' THEN ''int''
									ELSE ''string''                        
									END AS DATATYPE, 
								POS.F06 AS VALUE, 	
								''Bad Tare Link'' AS REASON
				FROM '+@ITEM_ITM_FILTER_TABLE+N' TMP 
				LEFT JOIN OBJ_TAB OBJ ON OBJ.F01=TMP.F01 
				LEFT JOIN POS_TAB POS ON POS.F01=TMP.F01 AND (@F1000 IS NULL OR POS.F1000=@F1000)
				LEFT JOIN TAR_TAB TAR ON TAR.F06=POS.F06
				JOIN RB_FIELDS RBF ON RBF.F1452=''POS_TAB'' AND RBF.F1453=''F06''
				WHERE TAR.F06 IS NULL AND ISNULL(POS.F06,0)<>0'
			EXEC sp_executesql @SQL, @PRM, @F1000, @TargetMode, @TargetBase
		END
		-- Zero Price and F1120 not EZ
		IF ISNULL(@ZeroPrice,1)=1 
		BEGIN 
			SET @SQL = N'
			INSERT INTO #ITEM_ITM_VALIDITY_CHECK'+@ExtGridSession+N'
				SELECT DISTINCT TMP.F01,
								ISNULL(OBJ.F29,'''') AS F29, 
								ISNULL(OBJ.F155,'''') AS F155, 
								ISNULL(OBJ.F22,'''') AS F22, 
								ISNULL(POS.F02,'''') AS F02,
								CONCAT(ISNULL(OBJ.F29,''''),'' '',ISNULL(OBJ.F155,''''),'' '',ISNULL(OBJ.F22,''''),'' '',ISNULL(POS.F02,'''')) AS ItmDescr,
								3 AS TablePriority,
								''PRICE_TAB'' AS SRC,
								CONCAT(''<PK>'',(Select ''Target Identifier'' as d,PRI.F1000 as v for XML RAW(''F1000'')),(Select ''Price level'' as d,PRI.F126 as v for XML RAW(''F126'')),''</PK>'') AS PK, 
								NULL AS FLD, 
								NULL AS DESCR, 
								NULL AS DATATYPE, 
								NULL AS VALUE, 	
								''Zero Price or Quantity (Active/Next)'' AS REASON
				FROM '+@ITEM_ITM_FILTER_TABLE+N' TMP 
				LEFT JOIN OBJ_TAB OBJ ON OBJ.F01=TMP.F01 
				JOIN PRICE_TAB PRI ON PRI.F01=TMP.F01 AND (PRI.F1007 IS NULL or PRI.F1007=0 or PRI.F1013=0 or PRI.F1006=0 or PRI.F1012=0) AND (@F1000 IS NULL OR PRI.F1000=@F1000)
				LEFT JOIN POS_TAB POS ON POS.F01=TMP.F01 AND POS.F1000=PRI.F1000 
				WHERE UPPER(ISNULL(POS.F1120,'''')) NOT LIKE ''%EZ%''
			'
			EXEC sp_executesql @SQL, @PRM, @F1000, @TargetMode, @TargetBase
		END
		--  Bad Link in Kit Table
		IF ISNULL(@BadKit,1)=1 
		BEGIN 
			SET @SQL = N'
			INSERT INTO #ITEM_ITM_VALIDITY_CHECK'+@ExtGridSession+N'
				SELECT 	KIT.F01,
						MAX(ISNULL(OBJ.F29,'''')) AS F29, 
						MAX(ISNULL(OBJ.F155,'''')) AS F155, 
						MAX(ISNULL(OBJ.F22,'''')) AS F22, 
						MAX(ISNULL(POS.F02,'''')) AS F02,
						CONCAT(MAX(ISNULL(OBJ.F29,'''')),'' '',MAX(ISNULL(OBJ.F155,'''')),'' '',MAX(ISNULL(OBJ.F22,'''')),'' '',MAX(ISNULL(POS.F02,''''))) AS ItmDescr,
						5 AS TablePriority,
						''KIT_TAB'' AS SRC,
						CONCAT(''<PK>'',(Select ''Price level'' as d,MAX(KIT.F126) as v for XML RAW(''F126'')),(Select ''Kit UPC Link'' as d,KIT.F1507 as v for XML RAW(''F1507'')),''</PK>'') AS PK, 
						MAX(CASE WHEN OBJ.F01 IS NULL THEN ''F01'' ELSE ''F1507'' END) AS FLD,
						MAX(RBF.F1454) AS DESCR, 
						MAX(CASE RBF.F1458
							WHEN ''dtString'' THEN ''string''
							WHEN ''dtDateTime'' THEN ''TS''
							WHEN ''dtCurrency'' THEN ''$''
							WHEN ''dtDouble'' THEN ''float''
							WHEN ''dtInteger'' THEN ''int''
							ELSE ''string''                        
							END) AS DATATYPE, 
						CASE WHEN MAX(OBJ.F01) IS NULL THEN KIT.F01 ELSE KIT.F1507 END AS VALUE, 	
						''Bad Link in Kit Table'' AS REASON
				FROM '+@ITEM_ITM_FILTER_TABLE+N' TMP 
				JOIN KIT_TAB KIT ON KIT.F01=TMP.F01
				LEFT JOIN OBJ_TAB OBJ ON OBJ.F01=TMP.F01
				LEFT JOIN (SELECT DISTINCT F01, MAX(F02) AS F02 FROM POS_TAB WHERE @F1000 IS NULL OR F1000=@F1000 GROUP BY F01) POS ON POS.F01=TMP.F01
				LEFT JOIN OBJ_TAB OBJ2 ON OBJ2.F01=KIT.F1507
				JOIN RB_FIELDS RBF ON RBF.F1452=''KIT_TAB'' AND RBF.F1453=CASE WHEN OBJ.F01 IS NULL THEN ''F01'' ELSE ''F1507'' END 
				WHERE OBJ.F01 IS NULL OR OBJ2.f01 IS NULL
				GROUP BY KIT.F01,KIT.F1507				
			'
			EXEC sp_executesql @SQL, @PRM, @F1000, @TargetMode, @TargetBase
		END
		-- Conflict between Main and Alternate Code
		IF ISNULL(@BadObjAlt,1)=1 
		BEGIN 
			SET @SQL = N'
			INSERT INTO #ITEM_ITM_VALIDITY_CHECK'+@ExtGridSession+N'
				SELECT DISTINCT ALT.F01,
								ISNULL(REF.F29,'''') AS F29, 
								ISNULL(REF.F155,'''') AS F155, 
								ISNULL(REF.F22,'''') AS F22, 
								ISNULL(POS.F02,'''') AS F02,
								CONCAT(ISNULL(REF.F29,''''),'' '',ISNULL(REF.F155,''''),'' '',ISNULL(REF.F22,''''),'' '',ISNULL(POS.F02,'''')) AS ItmDescr,
								5 AS TablePriority,
								''ALT_TAB'' AS SRC,
								CONCAT(''<PK>'',(Select ''Target Identifier'' as d,ALT.F1000 as v for XML RAW(''F1000'')),(Select ''Alternate code'' as d,ALT.F154 as v for XML RAW(''F154'')),''</PK>'') AS PK, 
								''F154'' AS FLD, 
								RBF.F1454 AS DESCR, 
								CASE RBF.F1458
									WHEN ''dtString'' THEN ''string''
									WHEN ''dtDateTime'' THEN ''TS''
									WHEN ''dtCurrency'' THEN ''$''
									WHEN ''dtDouble'' THEN ''float''
									WHEN ''dtInteger'' THEN ''int''
									ELSE ''string''
									END AS DATATYPE, 
								ALT.F154 AS VALUE, 	
								''Conflict between Alternate Code and Main item: '' + OBJ.F01  AS REASON
				FROM '+@ITEM_ITM_FILTER_TABLE+N' TMP 
				JOIN OBJ_TAB OBJ ON OBJ.F01=TMP.F01 
				JOIN ALT_TAB ALT ON REPLACE(LTRIM(REPLACE(OBJ.F01,''0'','' '')),'' '',''0'')=REPLACE(LTRIM(REPLACE(ALT.F154,''0'','' '')),'' '',''0'')
					AND REPLACE(LTRIM(REPLACE(ALT.F01,''0'','' '')),'' '',''0'')<>REPLACE(LTRIM(REPLACE(OBJ.F01,''0'','' '')),'' '',''0'')
				LEFT JOIN OBJ_TAB REF ON REF.F01=ALT.F01 
				LEFT JOIN (SELECT DISTINCT F01, MAX(F02) AS F02 FROM POS_TAB WHERE @F1000 IS NULL OR F1000=@F1000 GROUP BY F01) POS ON POS.F01=ALT.F01
				JOIN RB_FIELDS RBF ON RBF.F1452=''ALT_TAB'' AND RBF.F1453=''F154'' 
			'
			EXEC sp_executesql @SQL, @PRM, @F1000, @TargetMode, @TargetBase
		END
		-- Bad Link to Scale Text
		IF ISNULL(@BadScaleTxt,1)=1 
		BEGIN 
			SET @SQL = N'
			INSERT INTO #ITEM_ITM_VALIDITY_CHECK'+@ExtGridSession+N'
				SELECT DISTINCT TMP.F01,
								ISNULL(OBJ.F29,'''') AS F29, 
								ISNULL(OBJ.F155,'''') AS F155, 
								ISNULL(OBJ.F22,'''') AS F22, 
								ISNULL(POS.F02,'''') AS F02,
								CONCAT(ISNULL(OBJ.F29,''''),'' '',ISNULL(OBJ.F155,''''),'' '',ISNULL(OBJ.F22,''''),'' '',ISNULL(POS.F02,'''')) AS ItmDescr,
								5 AS TablePriority,
								''SCL_TAB'' AS SRC,
								CONCAT(''<PK>'',(Select ''Target Identifier'' as d,SCL.F1000 as v for XML RAW(''F1000'')),''</PK>'') AS PK, 
								''F267'' AS FLD, 
								RBF.F1454 AS DESCR, 
								CASE RBF.F1458
									WHEN ''dtString'' THEN ''string''
									WHEN ''dtDateTime'' THEN ''TS''
									WHEN ''dtCurrency'' THEN ''$''
									WHEN ''dtDouble'' THEN ''float''
									WHEN ''dtInteger'' THEN ''int''
									ELSE ''string''                        
									END AS DATATYPE, 
								SCL.F267 AS VALUE, 	
								''Bad Link to Scale Text'' AS REASON
				FROM '+@ITEM_ITM_FILTER_TABLE+N' TMP 
				LEFT JOIN OBJ_TAB OBJ ON OBJ.F01=TMP.F01 
				LEFT JOIN (SELECT DISTINCT F01, MAX(F02) AS F02 FROM POS_TAB WHERE @F1000 IS NULL OR F1000=@F1000 GROUP BY F01) POS ON POS.F01=TMP.F01
				JOIN SCL_TAB SCL ON SCL.F01=TMP.F01 AND (@F1000 IS NULL OR SCL.F1000=@F1000)
				LEFT JOIN SCL_BBA_TXT TXT ON TXT.F267=SCL.F267 AND (@F1000 IS NULL OR TXT.F1000=@F1000)
				JOIN RB_FIELDS RBF ON RBF.F1452=''SCL_TAB'' AND RBF.F1453=''F267'' 
				WHERE TXT.F267 IS NULL
			'
			EXEC sp_executesql @SQL, @PRM, @F1000, @TargetMode, @TargetBase
		END
		-- Like codes with different prices.
		IF ISNULL(@MultiplePriceLikeCode,1)=1 
		BEGIN 
			SET @SQL = N'
			INSERT INTO #ITEM_ITM_VALIDITY_CHECK'+@ExtGridSession+N'
				SELECT DISTINCT PRI.F01,
								ISNULL(OBJ.F29,'''') AS F29, 
								ISNULL(OBJ.F155,'''') AS F155, 
								ISNULL(OBJ.F22,'''') AS F22, 
								ISNULL(POS.F02,'''') AS F02,
								CONCAT(ISNULL(OBJ.F29,''''),'' '',ISNULL(OBJ.F155,''''),'' '',ISNULL(OBJ.F22,''''),'' '',ISNULL(POS.F02,'''')) AS ItmDescr,
								3 AS TablePriority,
								''PRICE_TAB'' AS SRC,
								CONCAT(''<PK>'',(Select ''Target Identifier'' as d,PRI.F1000 as v for XML RAW(''F1000'')),(Select ''Price level'' as d,PRI.F126 as v for XML RAW(''F126'')),(Select ''Like code'' as d,PRI.F122 as v for XML RAW(''F122'')),''</PK>'') AS PK, 
								''F122'' AS FLD, 
								RBF.F1454 AS DESCR, 
								CASE RBF.F1458
									WHEN ''dtString'' THEN ''string''
									WHEN ''dtDateTime'' THEN ''TS''
									WHEN ''dtCurrency'' THEN ''$''
									WHEN ''dtDouble'' THEN ''float''
									WHEN ''dtInteger'' THEN ''int''
									ELSE ''string''                        
									END AS DATATYPE, 
								PRI.F122 AS VALUE, 	
								''Like codes with different prices'' AS REASON
				FROM '+@ITEM_ITM_FILTER_TABLE+N' TMP 
				LEFT JOIN OBJ_TAB OBJ ON OBJ.F01=TMP.F01 
				LEFT JOIN (SELECT DISTINCT F01, MAX(F02) AS F02 FROM POS_TAB GROUP BY F01) POS ON POS.F01=TMP.F01
				JOIN (SELECT MIN(F01) AS F01, F122,F1000,F126, MAX(f1007) as MaxF1007, MIN(f1007) as MinF1007 
						FROM PRICE_TAB 
						WHERE NULLIF(F122,'''') IS NOT NULL
						 AND (@F1000 IS NULL OR F1000=@F1000) 
						GROUP BY f122,F1000,F126 
						HAVING MAX(f1007)<>MIN(f1007)) PRI ON PRI.F01=TMP.F01
				JOIN RB_FIELDS RBF ON RBF.F1452=''PRICE_TAB'' AND RBF.F1453=''F122'' 
			'
			EXEC sp_executesql @SQL, @PRM, @F1000, @TargetMode, @TargetBase
		END
		-- Bad Bottle Link 
		IF ISNULL(@BadBtlLnk,1)=1 
		BEGIN 
			SET @SQL = N'
			INSERT INTO #ITEM_ITM_VALIDITY_CHECK'+@ExtGridSession+N'
				SELECT DISTINCT TMP.F01,
								ISNULL(OBJ.F29,'''') AS F29, 
								ISNULL(OBJ.F155,'''') AS F155, 
								ISNULL(OBJ.F22,'''') AS F22, 
								ISNULL(POS.F02,'''') AS F02,
								CONCAT(ISNULL(OBJ.F29,''''),'' '',ISNULL(OBJ.F155,''''),'' '',ISNULL(OBJ.F22,''''),'' '',ISNULL(POS.F02,'''')) AS ItmDescr,
								2 AS TablePriority,
								''POS_TAB'' AS SRC,
								CONCAT(''<PK>'',(Select ''Target Identifier'' as d,POS.F1000 as v for XML RAW(''F1000'')),''</PK>'') AS PK, 
								''F05'' AS FLD, 
								RBF.F1454 AS DESCR, 
								CASE RBF.F1458
									WHEN ''dtString'' THEN ''string''
									WHEN ''dtDateTime'' THEN ''TS''
									WHEN ''dtCurrency'' THEN ''$''
									WHEN ''dtDouble'' THEN ''float''
									WHEN ''dtInteger'' THEN ''int''
									ELSE ''string''                        
									END AS DATATYPE, 
								POS.F05 AS VALUE, 	
								''Bad Bottle Link'' AS REASON
				FROM '+@ITEM_ITM_FILTER_TABLE+N' TMP 
				LEFT JOIN OBJ_TAB OBJ ON OBJ.F01=TMP.F01 
				LEFT JOIN POS_TAB POS ON POS.F01=TMP.F01 AND (@F1000 IS NULL OR POS.F1000=@F1000)
				LEFT JOIN BTL_TAB BTL ON BTL.F05=POS.F05
				JOIN RB_FIELDS RBF ON RBF.F1452=''POS_TAB'' AND RBF.F1453=''F05''
				WHERE BTL.F05 IS NULL AND ISNULL(POS.F05,0)<>0'
			EXEC sp_executesql @SQL, @PRM, @F1000, @TargetMode, @TargetBase
		END

		-- QUALITY VALIDATORS
		-- checkbox - Missing Cost Record 
		IF ISNULL(@MissCost,1)=1 
		BEGIN 
			SET @SQL = N'
			INSERT INTO #ITEM_ITM_VALIDITY_CHECK'+@ExtGridSession+N'
				SELECT DISTINCT TMP.F01,
								ISNULL(OBJ.F29,'''') AS F29, 
								ISNULL(OBJ.F155,'''') AS F155, 
								ISNULL(OBJ.F22,'''') AS F22, 
								ISNULL(POS.F02,'''') AS F02,
								CONCAT(ISNULL(OBJ.F29,''''),'' '',ISNULL(OBJ.F155,''''),'' '',ISNULL(OBJ.F22,''''),'' '',ISNULL(POS.F02,'''')) AS ItmDescr,
								4 AS TablePriority,
								''COST_TAB'' AS SRC,
								CONCAT(''<PK>'',(Select ''Target Identifier'' as d,'''' as v for XML RAW(''F1000'')),(Select ''Vendor id'' as d,'''' as v for XML RAW(''F27'')),(Select ''Buying format'' as d,'''' as v for XML RAW(''F1184'')),''</PK>'') AS PK,
								NULL AS FLD, 
								NULL AS DESCR, 
								NULL AS DATATYPE, 
								NULL AS VALUE, 
								''Missing Cost Record'' AS REASON
				FROM '+@ITEM_ITM_FILTER_TABLE+N' TMP 
				LEFT JOIN OBJ_TAB OBJ ON OBJ.F01=TMP.F01 
				LEFT JOIN (SELECT DISTINCT F01, MAX(F02) AS F02 FROM POS_TAB WHERE @F1000 IS NULL OR F1000=@F1000 GROUP BY F01) POS ON POS.F01=TMP.F01
				LEFT JOIN COST_TAB COS ON COS.F01=TMP.F01
				WHERE COS.F01 IS NULL				
			'
			EXEC sp_executesql @SQL, @PRM, @F1000, @TargetMode, @TargetBase
		END
		-- Missing Location Record
		IF ISNULL(@MissLoc,1)=1 
		BEGIN 
			SET @SQL = N'
			INSERT INTO #ITEM_ITM_VALIDITY_CHECK'+@ExtGridSession+N'
				SELECT DISTINCT TMP.F01,
								ISNULL(OBJ.F29,'''') AS F29, 
								ISNULL(OBJ.F155,'''') AS F155, 
								ISNULL(OBJ.F22,'''') AS F22, 
								ISNULL(POS.F02,'''') AS F02,
								CONCAT(ISNULL(OBJ.F29,''''),'' '',ISNULL(OBJ.F155,''''),'' '',ISNULL(OBJ.F22,''''),'' '',ISNULL(POS.F02,'''')) AS ItmDescr,
								5 AS TablePriority,
								''LOC_TAB'' AS SRC,
								CONCAT(''<PK>'',(Select ''Target Identifier'' as d,'''' as v for XML RAW(''F1000'')),(Select ''Shelf location'' as d,'''' as v for XML RAW(''F117'')),''</PK>'') AS PK,
								NULL AS FLD, 
								NULL AS DESCR, 
								NULL AS DATATYPE, 
								NULL AS VALUE, 
								''Missing Location Record'' AS REASON
				FROM '+@ITEM_ITM_FILTER_TABLE+N' TMP 
				LEFT JOIN OBJ_TAB OBJ ON OBJ.F01=TMP.F01 
				LEFT JOIN (SELECT DISTINCT F01, MAX(F02) AS F02 FROM POS_TAB WHERE @F1000 IS NULL OR F1000=@F1000 GROUP BY F01) POS ON POS.F01=TMP.F01
				LEFT JOIN LOC_TAB LOC ON LOC.F01=TMP.F01 AND (@F1000 IS NULL OR LOC.F1000=@F1000) 
				WHERE LOC.F01 IS NULL
			'
			EXEC sp_executesql @SQL, @PRM, @F1000, @TargetMode, @TargetBase
		END
		-- Bad or Missing category
		IF ISNULL(@MissCat,1)=1 
		BEGIN 
			SET @SQL = N'
			INSERT INTO #ITEM_ITM_VALIDITY_CHECK'+@ExtGridSession+N'
				SELECT DISTINCT TMP.F01,
								ISNULL(OBJ.F29,'''') AS F29, 
								ISNULL(OBJ.F155,'''') AS F155, 
								ISNULL(OBJ.F22,'''') AS F22, 
								ISNULL(POS.F02,'''') AS F02,
								CONCAT(ISNULL(OBJ.F29,''''),'' '',ISNULL(OBJ.F155,''''),'' '',ISNULL(OBJ.F22,''''),'' '',ISNULL(POS.F02,'''')) AS ItmDescr,
								1 AS TablePriority,
								''OBJ_TAB'' AS SRC,
								''<PK></PK>'' AS PK, 
								''F17'' AS FLD, 
								RBF.F1454 AS DESCR, 
								CASE RBF.F1458
									WHEN ''dtString'' THEN ''string''
									WHEN ''dtDateTime'' THEN ''TS''
									WHEN ''dtCurrency'' THEN ''$''
									WHEN ''dtDouble'' THEN ''float''
									WHEN ''dtInteger'' THEN ''int''
									ELSE ''string''                        
									END AS DATATYPE, 
								OBJ.F17 AS VALUE, 	
								''Bad or Missing Category'' AS REASON
				FROM '+@ITEM_ITM_FILTER_TABLE+N' TMP 
				JOIN OBJ_TAB OBJ ON OBJ.F01=TMP.F01 
				LEFT JOIN (SELECT DISTINCT F01, MAX(F02) AS F02 FROM POS_TAB WHERE @F1000 IS NULL OR F1000=@F1000 GROUP BY F01) POS ON POS.F01=TMP.F01
				LEFT JOIN CAT_TAB CAT ON OBJ.F17=CAT.F17
				JOIN RB_FIELDS RBF ON RBF.F1452=''OBJ_TAB'' AND RBF.F1453=''F17'' 
				WHERE CAT.F17 IS NULL OR OBJ.F17 IS NULL
			'
			EXEC sp_executesql @SQL, @PRM, @F1000, @TargetMode, @TargetBase
		END
		-- Bad or Missing Family
		IF ISNULL(@MissFam,1)=1 
		BEGIN 
			SET @SQL = N'
			INSERT INTO #ITEM_ITM_VALIDITY_CHECK'+@ExtGridSession+N'
				SELECT DISTINCT TMP.F01,
								ISNULL(OBJ.F29,'''') AS F29, 
								ISNULL(OBJ.F155,'''') AS F155, 
								ISNULL(OBJ.F22,'''') AS F22, 
								ISNULL(POS.F02,'''') AS F02,
								CONCAT(ISNULL(OBJ.F29,''''),'' '',ISNULL(OBJ.F155,''''),'' '',ISNULL(OBJ.F22,''''),'' '',ISNULL(POS.F02,'''')) AS ItmDescr,
								1 AS TablePriority,
								''OBJ_TAB'' AS SRC,
								''<PK></PK>'' AS PK, 
								''F16'' AS FLD, 
								RBF.F1454 AS DESCR, 
								CASE RBF.F1458
									WHEN ''dtString'' THEN ''string''
									WHEN ''dtDateTime'' THEN ''TS''
									WHEN ''dtCurrency'' THEN ''$''
									WHEN ''dtDouble'' THEN ''float''
									WHEN ''dtInteger'' THEN ''int''
									ELSE ''string''                        
									END AS DATATYPE, 
								OBJ.F16 AS VALUE, 	
								''Bad or Missing Family'' AS REASON
				FROM '+@ITEM_ITM_FILTER_TABLE+N' TMP 
				JOIN OBJ_TAB OBJ ON OBJ.F01=TMP.F01 
				LEFT JOIN (SELECT DISTINCT F01, MAX(F02) AS F02 FROM POS_TAB WHERE @F1000 IS NULL OR F1000=@F1000 GROUP BY F01) POS ON POS.F01=TMP.F01
				LEFT JOIN FAM_TAB FAM ON FAM.F16=OBJ.F16
				JOIN RB_FIELDS RBF ON RBF.F1452=''OBJ_TAB'' AND RBF.F1453=''F16'' 
				WHERE FAM.F16 IS NULL OR OBJ.F16 IS NULL
			'
			EXEC sp_executesql @SQL, @PRM, @F1000, @TargetMode, @TargetBase
		END
		--  Bad or Missing Classification 
		IF ISNULL(@MissCls,1)=1 
		BEGIN 
			SET @SQL = N'
			INSERT INTO #ITEM_ITM_VALIDITY_CHECK'+@ExtGridSession+N'
				SELECT DISTINCT TMP.F01,
								ISNULL(OBJ.F29,'''') AS F29, 
								ISNULL(OBJ.F155,'''') AS F155, 
								ISNULL(OBJ.F22,'''') AS F22, 
								ISNULL(POS.F02,'''') AS F02,
								CONCAT(ISNULL(OBJ.F29,''''),'' '',ISNULL(OBJ.F155,''''),'' '',ISNULL(OBJ.F22,''''),'' '',ISNULL(POS.F02,'''')) AS ItmDescr,
								5 AS TablePriority,
								''CLS_TAB'' AS SRC,
								CONCAT(''<PK>'',(Select ''Class ID'' as d,CLS.F2935 as v for XML RAW(''F2935'')),''</PK>'') AS PK, 
								''F2935'' AS FLD, 
								RBF.F1454 AS DESCR, 
								CASE RBF.F1458
									WHEN ''dtString'' THEN ''string''
									WHEN ''dtDateTime'' THEN ''TS''
									WHEN ''dtCurrency'' THEN ''$''
									WHEN ''dtDouble'' THEN ''float''
									WHEN ''dtInteger'' THEN ''int''
									ELSE ''string''                        
									END AS DATATYPE, 
								CLS.F2935 AS VALUE, 	
								''Bad or Missing Classification'' AS REASON
				FROM '+@ITEM_ITM_FILTER_TABLE+N' TMP 
				LEFT JOIN OBJ_TAB OBJ ON OBJ.F01=TMP.F01 
				LEFT JOIN (SELECT DISTINCT F01, MAX(F02) AS F02 FROM POS_TAB WHERE @F1000 IS NULL OR F1000=@F1000 GROUP BY F01) POS ON POS.F01=TMP.F01
				JOIN CLS_TAB CLS ON CLS.F01=TMP.F01
				LEFT JOIN CLS_AUX CAUX ON CAUX.F2935=CLS.F2935
				JOIN RB_FIELDS RBF ON RBF.F1452=''CLS_TAB'' AND RBF.F1453=''F2935'' 
				WHERE CAUX.F2935 IS NULL
			'
			EXEC sp_executesql @SQL, @PRM, @F1000, @TargetMode, @TargetBase
		END
		--  Bad Report Code
		IF ISNULL(@BadCode,1)=1 
		BEGIN 
			SET @SQL = N'
			INSERT INTO #ITEM_ITM_VALIDITY_CHECK'+@ExtGridSession+N'
				SELECT DISTINCT TMP.F01,
								ISNULL(OBJ.F29,'''') AS F29, 
								ISNULL(OBJ.F155,'''') AS F155, 
								ISNULL(OBJ.F22,'''') AS F22, 
								ISNULL(POS.F02,'''') AS F02,
								CONCAT(ISNULL(OBJ.F29,''''),'' '',ISNULL(OBJ.F155,''''),'' '',ISNULL(OBJ.F22,''''),'' '',ISNULL(POS.F02,'''')) AS ItmDescr,
								1 AS TablePriority,
								''OBJ_TAB'' AS SRC,
								''<PK></PK>'' AS PK, 
								''F18'' AS FLD, 
								RBF.F1454 AS DESCR, 
								CASE RBF.F1458
									WHEN ''dtString'' THEN ''string''
									WHEN ''dtDateTime'' THEN ''TS''
									WHEN ''dtCurrency'' THEN ''$''
									WHEN ''dtDouble'' THEN ''float''
									WHEN ''dtInteger'' THEN ''int''
									ELSE ''string''                        
									END AS DATATYPE, 
								OBJ.F18 AS VALUE, 	
								''Bad Report Code'' AS REASON
				FROM '+@ITEM_ITM_FILTER_TABLE+N' TMP 
				JOIN OBJ_TAB OBJ ON OBJ.F01=TMP.F01 
				LEFT JOIN (SELECT DISTINCT F01, MAX(F02) AS F02 FROM POS_TAB WHERE @F1000 IS NULL OR F1000=@F1000 GROUP BY F01) POS ON POS.F01=TMP.F01
				LEFT JOIN RPC_TAB RPC ON OBJ.F18=RPC.F18
				JOIN RB_FIELDS RBF ON RBF.F1452=''OBJ_TAB'' AND RBF.F1453=''F18'' 
				WHERE RPC.F18 IS NULL OR OBJ.F18 IS NULL
			'
			EXEC sp_executesql @SQL, @PRM, @F1000, @TargetMode, @TargetBase
		END
		--  Bad or Missing Vendor id
		IF ISNULL(@MissVnd,1)=1 
		BEGIN 
			SET @SQL = N'
			INSERT INTO #ITEM_ITM_VALIDITY_CHECK'+@ExtGridSession+N'
				SELECT DISTINCT TMP.F01,
								ISNULL(OBJ.F29,'''') AS F29, 
								ISNULL(OBJ.F155,'''') AS F155, 
								ISNULL(OBJ.F22,'''') AS F22, 
								ISNULL(POS.F02,'''') AS F02,
								CONCAT(ISNULL(OBJ.F29,''''),'' '',ISNULL(OBJ.F155,''''),'' '',ISNULL(OBJ.F22,''''),'' '',ISNULL(POS.F02,'''')) AS ItmDescr,
								4 AS TablePriority,
								''COST_TAB'' AS SRC,
								CONCAT(''<PK>'',(Select ''Target Identifier'' as d,COS.F1000 as v for XML RAW(''F1000'')),(Select ''Vendor id'' as d,COS.F27 as v for XML RAW(''F27'')),(Select ''Buying format'' as d,COS.F1184 as v for XML RAW(''F1184'')),''</PK>'') AS PK, 
								''F27'' AS FLD, 
								RBF.F1454 AS DESCR, 
								CASE RBF.F1458
									WHEN ''dtString'' THEN ''string''
									WHEN ''dtDateTime'' THEN ''TS''
									WHEN ''dtCurrency'' THEN ''$''
									WHEN ''dtDouble'' THEN ''float''
									WHEN ''dtInteger'' THEN ''int''
									ELSE ''string''                        
									END AS DATATYPE, 
								COS.F27 AS VALUE, 	
								''Bad or Missing Vendor id'' AS REASON
				FROM '+@ITEM_ITM_FILTER_TABLE+N' TMP 
				LEFT JOIN OBJ_TAB OBJ ON OBJ.F01=TMP.F01 
				LEFT JOIN (SELECT DISTINCT F01, MAX(F02) AS F02 FROM POS_TAB WHERE @F1000 IS NULL OR F1000=@F1000 GROUP BY F01) POS ON POS.F01=TMP.F01
				JOIN COST_TAB COS ON COS.F01=TMP.F01 AND (@F1000 IS NULL OR COS.F1000=@F1000) 
				LEFT JOIN VENDOR_TAB VND ON VND.F27=COS.F27
				JOIN RB_FIELDS RBF ON RBF.F1452=''COST_TAB'' AND RBF.F1453=''F27'' 
				WHERE VND.F27 IS NULL
			'
			EXEC sp_executesql @SQL, @PRM, @F1000, @TargetMode, @TargetBase
		END
		-- Blank Vendor Code
		IF ISNULL(@BlankVndCode,1)=1 
		BEGIN 
			SET @SQL = N'
			INSERT INTO #ITEM_ITM_VALIDITY_CHECK'+@ExtGridSession+N'
				SELECT DISTINCT TMP.F01,
								ISNULL(OBJ.F29,'''') AS F29, 
								ISNULL(OBJ.F155,'''') AS F155, 
								ISNULL(OBJ.F22,'''') AS F22, 
								ISNULL(POS.F02,'''') AS F02,
								CONCAT(ISNULL(OBJ.F29,''''),'' '',ISNULL(OBJ.F155,''''),'' '',ISNULL(OBJ.F22,''''),'' '',ISNULL(POS.F02,'''')) AS ItmDescr,
								4 AS TablePriority,
								''COST_TAB'' AS SRC,
								CONCAT(''<PK>'',(Select ''Target Identifier'' as d,COS.F1000 as v for XML RAW(''F1000'')),(Select ''Vendor id'' as d,COS.F27 as v for XML RAW(''F27'')),(Select ''Buying format'' as d,COS.F1184 as v for XML RAW(''F1184'')),''</PK>'') AS PK, 
								NULL AS FLD, 
								NULL AS DESCR, 
								NULL AS DATATYPE, 
								NULL AS VALUE, 	
								''Blank Vendor Code'' AS REASON
				FROM '+@ITEM_ITM_FILTER_TABLE+N' TMP 
				LEFT JOIN OBJ_TAB OBJ ON OBJ.F01=TMP.F01 
				LEFT JOIN (SELECT DISTINCT F01, MAX(F02) AS F02 FROM POS_TAB WHERE @F1000 IS NULL OR F1000=@F1000 GROUP BY F01) POS ON POS.F01=TMP.F01
				JOIN COST_TAB COS ON COS.F01=TMP.F01 AND (@F1000 IS NULL OR COS.F1000=@F1000)
				WHERE NULLIF(COS.F26,'''') IS NULL
			'
			EXEC sp_executesql @SQL, @PRM, @F1000, @TargetMode, @TargetBase
		END
		--  Issue with Authorized Vendor Flag
		IF ISNULL(@BadVndAuth,1)=1 
		BEGIN 
			SET @SQL = N'
			INSERT INTO #ITEM_ITM_VALIDITY_CHECK'+@ExtGridSession+N'
				SELECT DISTINCT COS.F01,
								MAX(ISNULL(OBJ.F29,'''')) AS F29, 
								MAX(ISNULL(OBJ.F155,'''')) AS F155, 
								MAX(ISNULL(OBJ.F22,'''')) AS F22, 
								MAX(ISNULL(POS.F02,'''')) AS F02,
								CONCAT(MAX(ISNULL(OBJ.F29,'''')),'' '',MAX(ISNULL(OBJ.F155,'''')),'' '',MAX(ISNULL(OBJ.F22,'''')),'' '',MAX(ISNULL(POS.F02,''''))) AS ItmDescr,
								4 AS TablePriority,
								''COST_TAB'' AS SRC,
								CONCAT(''<PK>'',(Select ''Target Identifier'' as d,COS.F1000 as v for XML RAW(''F1000'')),(Select ''Vendor id'' as d,MAX(COS.F27) as v for XML RAW(''F27'')),(Select ''Buying format'' as d,MAX(COS.F1184) as v for XML RAW(''F1184'')),''</PK>'') AS PK, 
								NULL AS FLD, 
								NULL AS DESCR, 
								NULL AS DATATYPE, 
								NULL AS VALUE, 	
								''Issue with Authorized Vendor Flag'' AS REASON
				FROM '+@ITEM_ITM_FILTER_TABLE+N' TMP 
				LEFT JOIN OBJ_TAB OBJ ON OBJ.F01=TMP.F01 
				LEFT JOIN (SELECT DISTINCT F01, MAX(F02) AS F02 FROM POS_TAB WHERE @F1000 IS NULL OR F1000=@F1000 GROUP BY F01) POS ON POS.F01=TMP.F01
				JOIN COST_TAB COS ON COS.F01=TMP.F01 AND (@F1000 IS NULL OR COS.F1000=@F1000)
				JOIN RB_FIELDS RBF ON RBF.F1452=''COST_TAB'' AND RBF.F1453=''F27'' 
				GROUP BY COS.F01,COS.F1000
				HAVING SUM(CASE WHEN ISNULL(NULLIF(COS.F90,''''),''1'')=''1'' THEN 1 ELSE 0 END)<>1
			'
			EXEC sp_executesql @SQL, @PRM, @F1000, @TargetMode, @TargetBase
		END
		--  Zero Cost
		IF ISNULL(@ZeroCost,1)=1 
		BEGIN 
			SET @SQL = N'
			INSERT INTO #ITEM_ITM_VALIDITY_CHECK'+@ExtGridSession+N'
				SELECT DISTINCT TMP.F01,
								ISNULL(OBJ.F29,'''') AS F29, 
								ISNULL(OBJ.F155,'''') AS F155, 
								ISNULL(OBJ.F22,'''') AS F22, 
								ISNULL(POS.F02,'''') AS F02,
								CONCAT(ISNULL(OBJ.F29,''''),'' '',ISNULL(OBJ.F155,''''),'' '',ISNULL(OBJ.F22,''''),'' '',ISNULL(POS.F02,'''')) AS ItmDescr,
								4 AS TablePriority,
								''COST_TAB'' AS SRC,
								CONCAT(''<PK>'',(Select ''Target Identifier'' as d,COS.F1000 as v for XML RAW(''F1000'')),(Select ''Vendor id'' as d,COS.F27 as v for XML RAW(''F27'')),(Select ''Buying format'' as d,COS.F1184 as v for XML RAW(''F1184'')),''</PK>'') AS PK, 
								''F38'' AS FLD, 
								RBF.F1454 AS DESCR, 
								CASE RBF.F1458
									WHEN ''dtString'' THEN ''string''
									WHEN ''dtDateTime'' THEN ''TS''
									WHEN ''dtCurrency'' THEN ''$''
									WHEN ''dtDouble'' THEN ''float''
									WHEN ''dtInteger'' THEN ''int''
									ELSE ''string''                        
									END AS DATATYPE, 
								COS.F38 AS VALUE, 
								''Zero Cost'' AS REASON
				FROM '+@ITEM_ITM_FILTER_TABLE+N' TMP 
				LEFT JOIN OBJ_TAB OBJ ON OBJ.F01=TMP.F01 
				LEFT JOIN (SELECT DISTINCT F01, MAX(F02) AS F02 FROM POS_TAB WHERE @F1000 IS NULL OR F1000=@F1000 GROUP BY F01) POS ON POS.F01=TMP.F01
				JOIN COST_TAB COS ON COS.F01=TMP.F01 AND (@F1000 IS NULL OR COS.F1000=@F1000)
				JOIN RB_FIELDS RBF ON RBF.F1452=''COST_TAB'' AND RBF.F1453=''F38'' 
				WHERE ISNULL(COS.F38,0)=0
			'
			EXEC sp_executesql @SQL, @PRM, @F1000, @TargetMode, @TargetBase
		END
		--	Kit or Split Item with Inventory
		IF ISNULL(@KitSplitInv,1)=1 
		BEGIN 
			/* Kit With Inventory */ 
			SET @SQL = N'
			INSERT INTO #ITEM_ITM_VALIDITY_CHECK'+@ExtGridSession+N'
				SELECT DISTINCT TMP.F01,
								ISNULL(OBJ.F29,'''') AS F29, 
								ISNULL(OBJ.F155,'''') AS F155, 
								ISNULL(OBJ.F22,'''') AS F22, 
								ISNULL(POS.F02,'''') AS F02,
								CONCAT(ISNULL(OBJ.F29,''''),'' '',ISNULL(OBJ.F155,''''),'' '',ISNULL(OBJ.F22,''''),'' '',ISNULL(POS.F02,'''')) AS ItmDescr,
								5 AS TablePriority,
								''KIT_TAB'' AS SRC,
								CONCAT(''<PK>'',(Select ''Price level'' as d,KIT.F126 as v for XML RAW(''F126'')),(Select ''Kit UPC Link'' as d,KIT.F1507 as v for XML RAW(''F1507'')),''</PK>'') AS PK,  
								''F1507'' AS FLD, 
								RBF.F1454 AS DESCR, 
								CASE RBF.F1458
									WHEN ''dtString'' THEN ''string''
									WHEN ''dtDateTime'' THEN ''TS''
									WHEN ''dtCurrency'' THEN ''$''
									WHEN ''dtDouble'' THEN ''float''
									WHEN ''dtInteger'' THEN ''int''
									ELSE ''string''                        
									END AS DATATYPE, 
								KIT.F1507 AS VALUE, 
								''Kit Item with Inventory'' AS REASON
				FROM '+@ITEM_ITM_FILTER_TABLE+N' TMP 
				LEFT JOIN OBJ_TAB OBJ ON OBJ.F01=TMP.F01 
				LEFT JOIN (SELECT DISTINCT F01, MAX(F02) AS F02 FROM POS_TAB WHERE @F1000 IS NULL OR F1000=@F1000 GROUP BY F01) POS ON POS.F01=TMP.F01
  				JOIN KIT_TAB KIT ON KIT.F01=TMP.F01
				JOIN RPT_ITM_N RPT ON RPT.F01=KIT.F01 and RPT.F1034=8501 AND (RPT.F64<>0 OR RPT.F65<>0)
				JOIN RB_FIELDS RBF ON RBF.F1452=''KIT_TAB'' AND RBF.F1453=''F1507'' 
			'
			EXEC sp_executesql @SQL, @PRM, @F1000, @TargetMode, @TargetBase
			
			/* Kit UPC found within kit */ 
			SET @SQL = N'
			INSERT INTO #ITEM_ITM_VALIDITY_CHECK'+@ExtGridSession+N'
				SELECT DISTINCT TMP.F01,
								ISNULL(OBJ.F29,'''') AS F29, 
								ISNULL(OBJ.F155,'''') AS F155, 
								ISNULL(OBJ.F22,'''') AS F22, 
								ISNULL(POS.F02,'''') AS F02,
								CONCAT(ISNULL(OBJ.F29,''''),'' '',ISNULL(OBJ.F155,''''),'' '',ISNULL(OBJ.F22,''''),'' '',ISNULL(POS.F02,'''')) AS ItmDescr,
								5 AS TablePriority,
								''KIT_TAB'' AS SRC,
								CONCAT(''<PK>'',(Select ''Price level'' as d,KIT.F126 as v for XML RAW(''F126'')),(Select ''Kit UPC Link'' as d,KIT.F1507 as v for XML RAW(''F1507'')),''</PK>'') AS PK,  
								''F1507'' AS FLD, 
								RBF.F1454 AS DESCR, 
								CASE RBF.F1458
									WHEN ''dtString'' THEN ''string''
									WHEN ''dtDateTime'' THEN ''TS''
									WHEN ''dtCurrency'' THEN ''$''
									WHEN ''dtDouble'' THEN ''float''
									WHEN ''dtInteger'' THEN ''int''
									ELSE ''string''                        
									END AS DATATYPE, 
								KIT.F1507 AS VALUE, 
								''Kit UPC found within kit'' AS REASON
				FROM '+@ITEM_ITM_FILTER_TABLE+N' TMP 
				LEFT JOIN OBJ_TAB OBJ ON OBJ.F01=TMP.F01 
				LEFT JOIN (SELECT DISTINCT F01, MAX(F02) AS F02 FROM POS_TAB WHERE @F1000 IS NULL OR F1000=@F1000 GROUP BY F01) POS ON POS.F01=TMP.F01
  				JOIN KIT_TAB KIT ON KIT.F01=TMP.F01 AND KIT.F01=KIT.F1507
				JOIN RB_FIELDS RBF ON RBF.F1452=''KIT_TAB'' AND RBF.F1453=''F1507'' 
			'
			EXEC sp_executesql @SQL, @PRM, @F1000, @TargetMode, @TargetBase

			/* Kit incorrect Ratio */ 
			SET @SQL = N'
			INSERT INTO #ITEM_ITM_VALIDITY_CHECK'+@ExtGridSession+N'
				SELECT DISTINCT TMP.F01,
								ISNULL(OBJ.F29,'''') AS F29, 
								ISNULL(OBJ.F155,'''') AS F155, 
								ISNULL(OBJ.F22,'''') AS F22, 
								ISNULL(POS.F02,'''') AS F02,
								CONCAT(ISNULL(OBJ.F29,''''),'' '',ISNULL(OBJ.F155,''''),'' '',ISNULL(OBJ.F22,''''),'' '',ISNULL(POS.F02,'''')) AS ItmDescr,
								5 AS TablePriority,
								''KIT_TAB'' AS SRC,
								CONCAT(''<PK>'',(Select ''Price level'' as d,KIT1.F126 as v for XML RAW(''F126'')),(Select ''Kit UPC Link'' as d,KIT1.F1507 as v for XML RAW(''F1507'')),''</PK>'') AS PK,  
								CASE WHEN KIT1.RNUM=1 AND KIT1.F1510 IS NOT NULL THEN ''F1510'' ELSE ''F1507'' END AS FLD, 
								RBF.F1454 AS DESCR, 
								CASE RBF.F1458
									WHEN ''dtString'' THEN ''string''
									WHEN ''dtDateTime'' THEN ''TS''
									WHEN ''dtCurrency'' THEN ''$''
									WHEN ''dtDouble'' THEN ''float''
									WHEN ''dtInteger'' THEN ''int''
									ELSE ''string''                        
									END AS DATATYPE, 
								CASE WHEN KIT1.RNUM=1 AND KIT1.F1510 IS NOT NULL THEN KIT1.F1510 ELSE KIT1.F1507 END AS VALUE, 
								''Kit - Sum of ratio must be < 100 and only last ratio must be empty'' AS REASON
				FROM '+@ITEM_ITM_FILTER_TABLE+N' TMP 
				LEFT JOIN OBJ_TAB OBJ ON OBJ.F01=TMP.F01 
				LEFT JOIN (SELECT DISTINCT F01, MAX(F02) AS F02 FROM POS_TAB WHERE @F1000 IS NULL OR F1000=@F1000 GROUP BY F01) POS ON POS.F01=TMP.F01
				LEFT JOIN (SELECT F01, F126, F1507, F1510, ROW_NUMBER() OVER (PARTITION BY F01, F126 ORDER BY F01 DESC,F126 DESC,F1507 DESC) AS RNUM FROM KIT_TAB) KIT1 ON KIT1.F01=TMP.F01
				LEFT JOIN (SELECT F01, F126, SUM(CASE WHEN F1510 IS NULL THEN 1 ELSE 0 END) AS CNT, SUM(F1510) AS RATIO FROM KIT_TAB GROUP BY F01, F126) KIT2 ON KIT2.F01=TMP.F01
				JOIN RB_FIELDS RBF ON RBF.F1452=''KIT_TAB'' AND RBF.F1453=''F1507'' 
				WHERE (KIT1.RNUM=1 AND KIT2.CNT <> 1)
				OR (KIT1.RNUM=1 AND (KIT2.RATIO < 1 OR KIT2.RATIO > 99))
			'
			EXEC sp_executesql @SQL, @PRM, @F1000, @TargetMode, @TargetBase

			/* Split with Inventory */ 
			SET @SQL = N'
			INSERT INTO #ITEM_ITM_VALIDITY_CHECK'+@ExtGridSession+N'
				SELECT DISTINCT TMP.F01,
								ISNULL(OBJ.F29,'''') AS F29, 
								ISNULL(OBJ.F155,'''') AS F155, 
								ISNULL(OBJ.F22,'''') AS F22, 
								ISNULL(POS.F02,'''') AS F02,
								CONCAT(ISNULL(OBJ.F29,''''),'' '',ISNULL(OBJ.F155,''''),'' '',ISNULL(OBJ.F22,''''),'' '',ISNULL(POS.F02,'''')) AS ItmDescr,
								4 AS TablePriority,
								''COST_TAB'' AS SRC,
								CONCAT(''<PK>'',(Select ''Target Identifier'' as d,COS.F1000 as v for XML RAW(''F1000'')),(Select ''Vendor id'' as d,COS.F27 as v for XML RAW(''F27'')),(Select ''Buying format'' as d,COS.F1184 as v for XML RAW(''F1184'')),''</PK>'') AS PK, 
								''F220'' AS FLD, 
								RBF.F1454 AS DESCR, 
								CASE RBF.F1458
									WHEN ''dtString'' THEN ''string''
									WHEN ''dtDateTime'' THEN ''TS''
									WHEN ''dtCurrency'' THEN ''$''
									WHEN ''dtDouble'' THEN ''float''
									WHEN ''dtInteger'' THEN ''int''
									ELSE ''string''                        
									END AS DATATYPE, 
								COS.F220 AS VALUE, 
								''Split Master ''+ TMP.F01 + '' Cannot Have Inventory'' AS REASON
				FROM '+@ITEM_ITM_FILTER_TABLE+N' TMP 
				LEFT JOIN OBJ_TAB OBJ ON OBJ.F01=TMP.F01 
				LEFT JOIN (SELECT DISTINCT F01, MAX(F02) AS F02 FROM POS_TAB WHERE @F1000 IS NULL OR F1000=@F1000 GROUP BY F01) POS ON POS.F01=TMP.F01
				JOIN RPT_ITM_N RPT ON RPT.F01=TMP.F01 AND RPT.F1034=8501 AND (RPT.F64<>0 OR RPT.F65<>0)
				JOIN COST_TAB COS ON COS.F01=RPT.F01 AND ISNULL(COS.F220,'''')<>'''' AND (@F1000 IS NULL OR COS.F1000=@F1000) 
					AND COS.F1000=(select F1000 from dbo.eSuite_base_target_cost(RPT.F1056,@TargetMode,@TargetBase,''1'',COS.F01,@TargetBase,RPT.F1056))
				JOIN RB_FIELDS RBF ON RBF.F1452=''COST_TAB'' AND RBF.F1453=''F220'' 
			'
			EXEC sp_executesql @SQL, @PRM, @F1000, @TargetMode, @TargetBase

			/* Invalid Split Code */ 
			SET @SQL = N'
			INSERT INTO #ITEM_ITM_VALIDITY_CHECK'+@ExtGridSession+N'
				SELECT DISTINCT TMP.F01,
								ISNULL(OBJ.F29,'''') AS F29, 
								ISNULL(OBJ.F155,'''') AS F155, 
								ISNULL(OBJ.F22,'''') AS F22, 
								ISNULL(POS.F02,'''') AS F02,
								CONCAT(ISNULL(OBJ.F29,''''),'' '',ISNULL(OBJ.F155,''''),'' '',ISNULL(OBJ.F22,''''),'' '',ISNULL(POS.F02,'''')) AS ItmDescr,
								4 AS TablePriority,
								''COST_TAB'' AS SRC,
								CONCAT(''<PK>'',(Select ''Target Identifier'' as d,COS.F1000 as v for XML RAW(''F1000'')),(Select ''Vendor id'' as d,COS.F27 as v for XML RAW(''F27'')),(Select ''Buying format'' as d,COS.F1184 as v for XML RAW(''F1184'')),''</PK>'') AS PK, 
								''F220'' AS FLD, 
								RBF.F1454 AS DESCR, 
								CASE RBF.F1458
									WHEN ''dtString'' THEN ''string''
									WHEN ''dtDateTime'' THEN ''TS''
									WHEN ''dtCurrency'' THEN ''$''
									WHEN ''dtDouble'' THEN ''float''
									WHEN ''dtInteger'' THEN ''int''
									ELSE ''string'' END AS DATATYPE, 
								COS.F220 AS VALUE, 
								''Invalid Split Code '' AS REASON
				FROM '+@ITEM_ITM_FILTER_TABLE+N' TMP 
				LEFT JOIN OBJ_TAB OBJ ON OBJ.F01=TMP.F01 
				LEFT JOIN (SELECT DISTINCT F01, MAX(F02) AS F02 FROM POS_TAB WHERE @F1000 IS NULL OR F1000=@F1000 GROUP BY F01) POS ON POS.F01=TMP.F01
  				JOIN COST_TAB COS ON COS.F01=TMP.F01 AND ISNULL(COS.F220,'''')<>'''' AND (@F1000 IS NULL OR COS.F1000=@F1000) 
				LEFT JOIN OBJ_TAB SPLIT ON SPLIT.F01=COS.F220
				JOIN RB_FIELDS RBF ON RBF.F1452=''COST_TAB'' AND RBF.F1453=''F220'' 
				WHERE SPLIT.F01 IS NULL OR COS.F01=COS.f220
			'
			EXEC sp_executesql @SQL, @PRM, @F1000, @TargetMode, @TargetBase

			/* Missing split code on authorized vendor */ 
			SET @SQL = N'
			INSERT INTO #ITEM_ITM_VALIDITY_CHECK'+@ExtGridSession+N'
				SELECT DISTINCT TMP.F01,
								ISNULL(OBJ.F29,'''') AS F29, 
								ISNULL(OBJ.F155,'''') AS F155, 
								ISNULL(OBJ.F22,'''') AS F22, 
								ISNULL(POS.F02,'''') AS F02,
								CONCAT(ISNULL(OBJ.F29,''''),'' '',ISNULL(OBJ.F155,''''),'' '',ISNULL(OBJ.F22,''''),'' '',ISNULL(POS.F02,'''')) AS ItmDescr,
								4 AS TablePriority,
								''COST_TAB'' AS SRC,
								CONCAT(''<PK>'',(Select ''Vendor authorized item'' as d,COS.F90 as v for XML RAW(''F90'')),''</PK>'') AS PK, 
								''F220'' AS FLD, 
								RBF.F1454 AS DESCR, 
								CASE RBF.F1458
									WHEN ''dtString'' THEN ''string''
									WHEN ''dtDateTime'' THEN ''TS''
									WHEN ''dtCurrency'' THEN ''$''
									WHEN ''dtDouble'' THEN ''float''
									WHEN ''dtInteger'' THEN ''int''
									ELSE ''string'' END AS DATATYPE, 
								COS2.F220 AS VALUE, 
								''Split code discrepancy between authorized vendor'' AS REASON
				FROM '+@ITEM_ITM_FILTER_TABLE+N' TMP 
				LEFT JOIN OBJ_TAB OBJ ON OBJ.F01=TMP.F01 
				LEFT JOIN (SELECT DISTINCT F01, MAX(F02) AS F02 FROM POS_TAB  WHERE @F1000 IS NULL OR F1000=@F1000 GROUP BY F01) POS ON POS.F01=TMP.F01
  				JOIN COST_TAB COS ON COS.F01=TMP.F01 AND ISNULL(COS.F220,'''')<>'''' AND ISNULL(NULLIF(COS.F90,''''),1)=1 AND (@F1000 IS NULL OR COS.F1000=@F1000)
				JOIN COST_TAB COS2 ON COS2.F01=COS.F01 AND ISNULL(COS2.F220,'''')<>ISNULL(COS.F220,'''') AND ISNULL(NULLIF(COS2.F90,''''),1)=1 AND (@F1000 IS NULL OR COS2.F1000=@F1000) 
				JOIN RB_FIELDS RBF ON RBF.F1452=''COST_TAB'' AND RBF.F1453=''F220'' 
			'
			EXEC sp_executesql @SQL, @PRM, @F1000, @TargetMode, @TargetBase

			/* split code cascade issue */ 
			SET @SQL = N'
			INSERT INTO #ITEM_ITM_VALIDITY_CHECK'+@ExtGridSession+N'
				SELECT DISTINCT TMP.F01,
								ISNULL(OBJ.F29,'''') AS F29, 
								ISNULL(OBJ.F155,'''') AS F155, 
								ISNULL(OBJ.F22,'''') AS F22, 
								ISNULL(POS.F02,'''') AS F02,
								CONCAT(ISNULL(OBJ.F29,''''),'' '',ISNULL(OBJ.F155,''''),'' '',ISNULL(OBJ.F22,''''),'' '',ISNULL(POS.F02,'''')) AS ItmDescr,
								4 AS TablePriority,
								''COST_TAB'' AS SRC,
								CONCAT(''<PK>'',(Select ''Target Identifier'' as d,COS.F1000 as v for XML RAW(''F1000'')),(Select ''Vendor id'' as d,COS.F27 as v for XML RAW(''F27'')),(Select ''Buying format'' as d,COS.F1184 as v for XML RAW(''F1184'')),''</PK>'') AS PK, 
								''F220'' AS FLD, 
								RBF.F1454 AS DESCR, 
								CASE RBF.F1458
									WHEN ''dtString'' THEN ''string''
									WHEN ''dtDateTime'' THEN ''TS''
									WHEN ''dtCurrency'' THEN ''$''
									WHEN ''dtDouble'' THEN ''float''
									WHEN ''dtInteger'' THEN ''int''
									ELSE ''string'' END AS DATATYPE, 
								COS.F220 AS VALUE, 
								''Split code '' + COS.F220 + '' has split code '' + COS2.F220  AS REASON
				FROM '+@ITEM_ITM_FILTER_TABLE+N' TMP 
				LEFT JOIN OBJ_TAB OBJ ON OBJ.F01=TMP.F01 
				LEFT JOIN (SELECT DISTINCT F01, MAX(F02) AS F02 FROM POS_TAB WHERE @F1000 IS NULL OR F1000=@F1000 GROUP BY F01) POS ON POS.F01=TMP.F01
  				JOIN COST_TAB COS ON COS.F01=TMP.F01 AND ISNULL(COS.F220,'''')<>'''' AND ISNULL(NULLIF(COS.F90,''''),1)=1 AND (@F1000 IS NULL OR COS.F1000=@F1000)
				JOIN COST_TAB COS2 ON COS2.F01=COS.F220 AND (COS2.F90=1 OR COS2.F90 IS NULL) AND COS.F01<>COS2.F01 AND (@F1000 IS NULL OR COS2.F1000=@F1000)
				JOIN RB_FIELDS RBF ON RBF.F1452=''COST_TAB'' AND RBF.F1453=''F220'' 
				WHERE ISNULL(COS2.F220,'''')<>''''
			'
			EXEC sp_executesql @SQL, @PRM, @F1000, @TargetMode, @TargetBase

			/* split code quantity with no split code */ 
			SET @SQL = N'
			INSERT INTO #ITEM_ITM_VALIDITY_CHECK'+@ExtGridSession+N'
				SELECT DISTINCT TMP.F01,
								ISNULL(OBJ.F29,'''') AS F29, 
								ISNULL(OBJ.F155,'''') AS F155, 
								ISNULL(OBJ.F22,'''') AS F22, 
								ISNULL(POS.F02,'''') AS F02,
								CONCAT(ISNULL(OBJ.F29,''''),'' '',ISNULL(OBJ.F155,''''),'' '',ISNULL(OBJ.F22,''''),'' '',ISNULL(POS.F02,'''')) AS ItmDescr,
								4 AS TablePriority,
								''COST_TAB'' AS SRC,
								CONCAT(''<PK>'',(Select ''Target Identifier'' as d,COS.F1000 as v for XML RAW(''F1000'')),(Select ''Vendor id'' as d,COS.F27 as v for XML RAW(''F27'')),(Select ''Buying format'' as d,COS.F1184 as v for XML RAW(''F1184'')),''</PK>'') AS PK, 
								''F1795'' AS FLD, 
								RBF.F1454 AS DESCR, 
								CASE RBF.F1458
									WHEN ''dtString'' THEN ''string''
									WHEN ''dtDateTime'' THEN ''TS''
									WHEN ''dtCurrency'' THEN ''$''
									WHEN ''dtDouble'' THEN ''float''
									WHEN ''dtInteger'' THEN ''int''
									ELSE ''string'' END AS DATATYPE, 
								COS.F1795 AS VALUE, 
								''split code quantity with no split code ''  AS REASON
				FROM '+@ITEM_ITM_FILTER_TABLE+N' TMP 
				LEFT JOIN OBJ_TAB OBJ ON OBJ.F01=TMP.F01 
				LEFT JOIN (SELECT DISTINCT F01, MAX(F02) AS F02 FROM POS_TAB WHERE @F1000 IS NULL OR F1000=@F1000 GROUP BY F01) POS ON POS.F01=TMP.F01
				JOIN COST_TAB COS ON COS.F01=TMP.F01 AND ISNULL(COS.F220,'''')='''' AND ISNULL(COS.F1795,0)<>0 AND (@F1000 IS NULL OR COS.F1000=@F1000)
				JOIN RB_FIELDS RBF ON RBF.F1452=''COST_TAB'' AND RBF.F1453=''F1795'' 
			'
			EXEC sp_executesql @SQL, @PRM, @F1000, @TargetMode, @TargetBase

			/* split code with no quantity */ 
			SET @SQL = N'
			INSERT INTO #ITEM_ITM_VALIDITY_CHECK'+@ExtGridSession+N'
				SELECT DISTINCT TMP.F01,
								ISNULL(OBJ.F29,'''') AS F29, 
								ISNULL(OBJ.F155,'''') AS F155, 
								ISNULL(OBJ.F22,'''') AS F22, 
								ISNULL(POS.F02,'''') AS F02,
								CONCAT(ISNULL(OBJ.F29,''''),'' '',ISNULL(OBJ.F155,''''),'' '',ISNULL(OBJ.F22,''''),'' '',ISNULL(POS.F02,'''')) AS ItmDescr,
								4 AS TablePriority,
								''COST_TAB'' AS SRC,
								CONCAT(''<PK>'',(Select ''Target Identifier'' as d,COS.F1000 as v for XML RAW(''F1000'')),(Select ''Vendor id'' as d,COS.F27 as v for XML RAW(''F27'')),(Select ''Buying format'' as d,COS.F1184 as v for XML RAW(''F1184'')),''</PK>'') AS PK, 
								''F220'' AS FLD, 
								RBF.F1454 AS DESCR, 
								CASE RBF.F1458
									WHEN ''dtString'' THEN ''string''
									WHEN ''dtDateTime'' THEN ''TS''
									WHEN ''dtCurrency'' THEN ''$''
									WHEN ''dtDouble'' THEN ''float''
									WHEN ''dtInteger'' THEN ''int''
									ELSE ''string'' END AS DATATYPE, 
								COS.F220 AS VALUE, 
								''split code with no quantity''  AS REASON
				FROM '+@ITEM_ITM_FILTER_TABLE+N' TMP 
				LEFT JOIN OBJ_TAB OBJ ON OBJ.F01=TMP.F01 
				LEFT JOIN (SELECT DISTINCT F01, MAX(F02) AS F02 FROM POS_TAB WHERE @F1000 IS NULL OR F1000=@F1000 GROUP BY F01) POS ON POS.F01=TMP.F01
  				JOIN COST_TAB COS ON COS.F01=TMP.F01 AND ISNULL(COS.F220,'''')<>'''' AND ISNULL(COS.F1795,0)=0 AND (@F1000 IS NULL OR COS.F1000=@F1000)
				JOIN RB_FIELDS RBF ON RBF.F1452=''COST_TAB'' AND RBF.F1453=''F220'' 
			'
			EXEC sp_executesql @SQL, @PRM, @F1000, @TargetMode, @TargetBase

			/* split code with inconsistent quantity */ 
			SET @SQL = N'
			INSERT INTO #ITEM_ITM_VALIDITY_CHECK'+@ExtGridSession+N'
				SELECT DISTINCT TMP.F01,
								ISNULL(OBJ.F29,'''') AS F29, 
								ISNULL(OBJ.F155,'''') AS F155, 
								ISNULL(OBJ.F22,'''') AS F22, 
								ISNULL(POS.F02,'''') AS F02,
								CONCAT(ISNULL(OBJ.F29,''''),'' '',ISNULL(OBJ.F155,''''),'' '',ISNULL(OBJ.F22,''''),'' '',ISNULL(POS.F02,'''')) AS ItmDescr,
								4 AS TablePriority,
								''COST_TAB'' AS SRC,
								CONCAT(''<PK>'',(Select ''Target Identifier'' as d,COS.F1000 as v for XML RAW(''F1000'')),(Select ''Vendor id'' as d,COS.F27 as v for XML RAW(''F27'')),(Select ''Buying format'' as d,COS.F1184 as v for XML RAW(''F1184'')),''</PK>'') AS PK, 
								''F1795'' AS FLD, 
								RBF.F1454 AS DESCR, 
								CASE RBF.F1458
									WHEN ''dtString'' THEN ''string''
									WHEN ''dtDateTime'' THEN ''TS''
									WHEN ''dtCurrency'' THEN ''$''
									WHEN ''dtDouble'' THEN ''float''
									WHEN ''dtInteger'' THEN ''int''
									ELSE ''string'' END AS DATATYPE, 
								COS.F1795 AS VALUE, 
								''split code with inconsistent split quantities''  AS REASON
				FROM '+@ITEM_ITM_FILTER_TABLE+N' TMP 
				LEFT JOIN OBJ_TAB OBJ ON OBJ.F01=TMP.F01 
				LEFT JOIN (SELECT DISTINCT F01, MAX(F02) AS F02 FROM POS_TAB WHERE @F1000 IS NULL OR F1000=@F1000 GROUP BY F01) POS ON POS.F01=TMP.F01
  				JOIN COST_TAB COS ON COS.F01=TMP.F01 AND (COS.F90=1 OR COS.F90 IS NULL) AND (@F1000 IS NULL OR COS.F1000=@F1000)
				JOIN (SELECT F01,AVG(F1795) AS F1795 FROM COST_TAB WHERE (F90=1 OR F90 IS NULL) AND (@F1000 IS NULL OR F1000=@F1000) GROUP BY F01) COS2 ON COS.F01=COS2.F01 AND COS.F1795<>COS2.F1795
				JOIN RB_FIELDS RBF ON RBF.F1452=''COST_TAB'' AND RBF.F1453=''F1795'' 
			'
			EXEC sp_executesql @SQL, @PRM, @F1000, @TargetMode, @TargetBase
		END
		IF ISNULL(@MultiVndCode,1)=1 
		BEGIN 
			SET @SQL = N'
			INSERT INTO #ITEM_ITM_VALIDITY_CHECK'+@ExtGridSession+N'
				SELECT DISTINCT TMP.F01,
								ISNULL(OBJ.F29,'''') AS F29, 
								ISNULL(OBJ.F155,'''') AS F155, 
								ISNULL(OBJ.F22,'''') AS F22, 
								ISNULL(POS.F02,'''') AS F02,
								CONCAT(ISNULL(OBJ.F29,''''),'' '',ISNULL(OBJ.F155,''''),'' '',ISNULL(OBJ.F22,''''),'' '',ISNULL(POS.F02,'''')) AS ItmDescr,
								4 AS TablePriority,
								''COST_TAB'' AS SRC,
								CONCAT(''<PK>'',(Select ''Vendor id'' as d,COS.F27 as v for XML RAW(''F27'')),(Select ''Vendor Code'' as d,COS.F26 as v for XML RAW(''F26'')),''</PK>'') AS PK,
								''F26'' AS FLD, 
								RBF.F1454 AS DESCR, 
								CASE RBF.F1458
									WHEN ''dtString'' THEN ''string''
									WHEN ''dtDateTime'' THEN ''TS''
									WHEN ''dtCurrency'' THEN ''$''
									WHEN ''dtDouble'' THEN ''float''
									WHEN ''dtInteger'' THEN ''int''
									ELSE ''string''                        
									END AS DATATYPE, 
								COS.F26 AS VALUE, 
								''Multiple Items with Same Vendor Code'' AS REASON
				FROM '+@ITEM_ITM_FILTER_TABLE+N' TMP 
				LEFT JOIN OBJ_TAB OBJ ON OBJ.F01=TMP.F01 
				LEFT JOIN (SELECT DISTINCT F01, MAX(F02) AS F02 FROM POS_TAB WHERE @F1000 IS NULL OR F1000=@F1000 GROUP BY F01) POS ON POS.F01=TMP.F01
				JOIN COST_TAB COS ON COS.F01=TMP.F01 AND COS.F26<>'''' AND COS.F26 IN (SELECT F26 FROM COST_TAB WHERE (@F1000 IS NULL OR F1000=@F1000) GROUP BY F27,F26 HAVING COUNT(DISTINCT F01)>1) AND (@F1000 IS NULL OR COS.F1000=@F1000)  
				JOIN RB_FIELDS RBF ON RBF.F1452=''COST_TAB'' AND RBF.F1453=''F26'' 
			'
			EXEC sp_executesql @SQL, @PRM, @F1000, @TargetMode, @TargetBase
		END
		-- Price Questionable values
		IF ISNULL(@PriceValidation,1)=1 
		BEGIN 
			SET @SQL = N'
			INSERT INTO #ITEM_ITM_VALIDITY_CHECK'+@ExtGridSession+N'
				SELECT DISTINCT TMP.F01,
									ISNULL(OBJ.F29,'''') AS F29, 
									ISNULL(OBJ.F155,'''') AS F155, 
									ISNULL(OBJ.F22,'''') AS F22, 
									ISNULL(POS.F02,'''') AS F02,
									CONCAT(ISNULL(OBJ.F29,''''),'' '',ISNULL(OBJ.F155,''''),'' '',ISNULL(OBJ.F22,''''),'' '',ISNULL(POS.F02,'''')) AS ItmDescr,
									3 AS TablePriority,
									''PRICE_TAB'' AS SRC,
									CONCAT(''<PK>'',(Select ''Target Identifier'' as d,PRI.F1000 as v for XML RAW(''F1000'')),(Select ''Price level'' as d,PRI.F126 as v for XML RAW(''F126'')),''</PK>'') AS PK, 
									CASE WHEN ISNULL(PRI.F30,0)>9999 THEN ''F30''
										WHEN ISNULL(PRI.F62,0)>9999 THEN ''F62''
										WHEN ISNULL(PRI.F63,0)>9999 THEN ''F63''
										WHEN ISNULL(PRI.F135,0)>9999 THEN ''F135''
										WHEN ISNULL(PRI.F136,0)>9999 THEN ''F136''
										WHEN ISNULL(PRI.F140,0)>9999 THEN ''F140''
										WHEN ISNULL(PRI.F142,0)>9999 THEN ''F142''
										WHEN ISNULL(PRI.F181,0)>9999 THEN ''F181''
										WHEN ISNULL(PRI.F182,0)>9999 THEN ''F182''
										WHEN ISNULL(PRI.F1133,0)>9999 THEN ''F1133''
										WHEN ISNULL(PRI.F1012,0)>9999 THEN ''F1012''
										WHEN ISNULL(PRI.F1013,0)>9999 THEN ''F1013''
										WHEN ISNULL(PRI.F1006,0)>9999 THEN ''F1006''
										WHEN ISNULL(PRI.F1007,0)>9999 THEN ''F1007''
										ELSE NULL 
									END AS FLD, 
									RBF.F1454 AS DESCR, 
									CASE RBF.F1458	WHEN ''dtString'' THEN ''string''
													WHEN ''dtDateTime'' THEN ''TS''
													WHEN ''dtCurrency'' THEN ''$''
													WHEN ''dtDouble'' THEN ''float''
													WHEN ''dtInteger'' THEN ''int''
													ELSE ''string'' END AS DATATYPE,  
									CASE WHEN ISNULL(PRI.F30,0)>9999 THEN PRI.F30
										WHEN ISNULL(PRI.F62,0)>9999 THEN PRI.F62
										WHEN ISNULL(PRI.F63,0)>9999 THEN PRI.F63
										WHEN ISNULL(PRI.F135,0)>9999 THEN PRI.F135
										WHEN ISNULL(PRI.F136,0)>9999 THEN PRI.F136
										WHEN ISNULL(PRI.F140,0)>9999 THEN PRI.F140
										WHEN ISNULL(PRI.F142,0)>9999 THEN PRI.F142
										WHEN ISNULL(PRI.F181,0)>9999 THEN PRI.F181
										WHEN ISNULL(PRI.F182,0)>9999 THEN PRI.F182
										WHEN ISNULL(PRI.F1133,0)>9999 THEN PRI.F1133
										WHEN ISNULL(PRI.F1012,0)>9999 THEN PRI.F1012
										WHEN ISNULL(PRI.F1013,0)>9999 THEN PRI.F1013
										WHEN ISNULL(PRI.F1006,0)>9999 THEN PRI.F1006
										WHEN ISNULL(PRI.F1007,0)>9999 THEN PRI.F1007
										ELSE NULL 
									END AS VALUE, 	
									''Potential Invalid value'' AS REASON
							FROM '+@ITEM_ITM_FILTER_TABLE+N' TMP
							LEFT JOIN OBJ_TAB OBJ ON OBJ.F01=TMP.F01 
							LEFT JOIN (SELECT DISTINCT F01, MAX(F02) AS F02 FROM POS_TAB WHERE @F1000 IS NULL OR F1000=@F1000 GROUP BY F01) POS ON POS.F01=TMP.F01
							JOIN PRICE_TAB PRI ON PRI.F01=TMP.F01
							JOIN RB_FIELDS RBF ON RBF.F1452=''PRICE_TAB'' 
												AND RBF.F1453=CASE WHEN ISNULL(PRI.F30,0)>9999 THEN ''F30''
																WHEN ISNULL(PRI.F62,0)>9999 THEN ''F62''
																WHEN ISNULL(PRI.F63,0)>9999 THEN ''F63''
																WHEN ISNULL(PRI.F135,0)>9999 THEN ''F135''
																WHEN ISNULL(PRI.F136,0)>9999 THEN ''F136''
																WHEN ISNULL(PRI.F140,0)>9999 THEN ''F140''
																WHEN ISNULL(PRI.F142,0)>9999 THEN ''F142''
																WHEN ISNULL(PRI.F181,0)>9999 THEN ''F181''
																WHEN ISNULL(PRI.F182,0)>9999 THEN ''F182''
																WHEN ISNULL(PRI.F1133,0)>9999 THEN ''F1133''
																WHEN ISNULL(PRI.F1012,0)>9999 THEN ''F1012''
																WHEN ISNULL(PRI.F1013,0)>9999 THEN ''F1013''
																WHEN ISNULL(PRI.F1006,0)>9999 THEN ''F1006''
																WHEN ISNULL(PRI.F1007,0)>9999 THEN ''F1007''
																ELSE NULL 
															END
							WHERE PRI.F142>9999 OR PRI.F63>9999 OR PRI.F181>9999 OR PRI.F136>9999 OR PRI.F1133>9999 OR PRI.F182>9999 OR PRI.F135>9999 OR PRI.F1007>9999 
								OR PRI.F1006>9999 OR PRI.F1013>9999 OR PRI.F1012>9999OR PRI.F140>9999 OR PRI.F62>9999
			'
			EXEC sp_executesql @SQL, @PRM, @F1000, @TargetMode, @TargetBase
		END
	END

	IF @ExtGridOutput IS NULL
	BEGIN
		DECLARE @TempTableName NVARCHAR(100) = N'#ITEM_ITM_VALIDITY_CHECK'+@ExtGridSession
		IF @ExtGridStep = 5 
			exec dbo.eSuite_base_grid_summary @TempTableName=@TempTableName, @ExtGridGroup=@ExtGridGroup, @ExtGridSummary=@ExtGridSummary
		ELSE
			exec dbo.eSuite_base_grid_result @TempTableName=@TempTableName, @ExtGridStart=@ExtGridStart,
				@ExtMaxRecords=@ExtMaxRecords, @ExtGridSort=@ExtGridSort, @ExtKeyList=@ExtKeyList,
				@ExtLookUp=@ExtLookUp, @ExtLookUpStart=@ExtLookUpStart,@ExtGridFilter=@ExtGridFilter
	END
	ELSE
	BEGIN
		set @SQL = N'
			IF OBJECT_ID('''+@ExtGridOutput+N''') IS NOT NULL DROP TABLE '+@ExtGridOutput+N';
			SELECT * INTO '+@ExtGridOutput+N' FROM #ITEM_ITM_VALIDITY_CHECK'+@ExtGridSession
		Exec sp_executesql @SQL
		SELECT @ExtGridOutput as RESULT
	END
END