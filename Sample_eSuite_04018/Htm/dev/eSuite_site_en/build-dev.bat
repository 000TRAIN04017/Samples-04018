if not "%1"=="" cd %1Htm\dev\eSuite_site_en
call build-copy %1

if not "%1"=="" cd %1Htm\dev\eSuite_site_en
copy app-production.json ..\eSuite\app.json
copy index-production.html ..\eSuite\index.html

cd ..\eSuite\
sencha app build development >build.txt

if not "%1"=="" cd %1
