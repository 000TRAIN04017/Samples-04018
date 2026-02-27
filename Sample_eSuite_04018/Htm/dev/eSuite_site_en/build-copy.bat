if not "%1"=="" cd %1Htm\dev\eSuite_site_en
if "%STOREMAN%"=="" set STOREMAN=..\..\..\..\

rd ..\eSuite\app\view /s /q
md ..\eSuite\app\view
rd ..\eSuite\resources /s /q
md ..\eSuite\resources

For /D %%a in ("..\eSuite\app\model\*.*") do RD /S /Q "%%a"
For /D %%a in ("..\eSuite\app\store\*.*") do RD /S /Q "%%a"

xcopy "..\eSuite_base_en\app\*.*" "..\eSuite\app\" /s /e /y /i
xcopy "..\eSuite_base_en\resources\*.*" "..\eSuite\resources\" /s /e /y /i

xcopy "..\eSuite_comp_en\app\*.*" "..\eSuite\app\" /s /e /y /i
xcopy "..\eSuite_comp_en\resources\*.*" "..\eSuite\resources\" /s /e /y /i

xcopy "..\eSuite_item_en\app\*.*" "..\eSuite\app\" /s /e /y /i
xcopy "..\eSuite_item_en\resources\*.*" "..\eSuite\resources\" /s /e /y /i

xcopy "..\eSuite_cust_en\app\*.*" "..\eSuite\app\" /s /e /y /i
xcopy "..\eSuite_cust_en\resources\*.*" "..\eSuite\resources\" /s /e /y /i

xcopy "..\eSuite_care_en\app\*.*" "..\eSuite\app\" /s /e /y /i
xcopy "..\eSuite_care_en\resources\*.*" "..\eSuite\resources\" /s /e /y /i

xcopy "..\eSuite_site_en\app\*.*" "..\eSuite\app\" /s /e /y /i
xcopy "..\eSuite_site_en\resources\*.*" "..\eSuite\resources\" /s /e /y /i

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%STOREMAN%Library\Install\Sencha\RefreshAppJs.ps1" "..\eSuite\app" "Application.js"

if not "%1"=="" cd %1
