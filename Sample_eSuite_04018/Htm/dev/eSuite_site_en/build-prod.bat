if not "%1"=="" cd %1Htm\dev\eSuite_site_en
call build-copy %1

if not "%1"=="" cd %1Htm\dev\eSuite_site_en
copy app-production.json ..\eSuite\app.json
copy index-production.html ..\eSuite\index.html

cd ..\eSuite\
rd build /s /q
md build

sencha app build production >build.txt

rd ..\..\eSuite\site\resources /s /q
md ..\..\eSuite\site\resources

xcopy SMSConsoleLogs.js ..\..\eSuite\site\ /y >nul
xcopy build\Production\SMS\*.* ..\..\eSuite\site /y >nul
xcopy build\Production\SMS\resources\*.* ..\..\eSuite\site\resources\ /s /y >nul

if not "%1"=="" cd %1
