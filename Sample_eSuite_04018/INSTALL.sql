/* EXECUTED ONLY WHEN THE OPTION IS INSTALLED */
@FMT(CMP,@WIZGET(INSTALL_STEP)<3,'®FMT(CHR,26)');

/* copy the eSuite demo */
@EXEC(EXE='xcopy.exe "@RUNSamples\@WIZGET(INSTALL_OPTION)\Htm\eSuite\*.*" "@OfficeHtm\eSuite\" /E /Y');

/* exit if base is not installed */
@fmt(CMP,@dbHot(FindFirst,@OfficeHtm\dev\eSuite\app\Application.js)=,'®fmt(CHR,26)');

/* CLEANUP FIRST */
@exec(EXE='cmd.exe /c rmdir /S /Q @OfficeHtm\dev\eSuite_site_en');
@exec(EXE='cmd.exe /c rmdir /S /Q @OfficeHtm\dev\eSuite_site_es');
@exec(EXE='cmd.exe /c rmdir /S /Q @OfficeHtm\dev\eSuite_site_fr');

/* copy the site forms */
@EXEC(EXE='xcopy.exe "@RUNSamples\@WIZGET(INSTALL_OPTION)\Htm\dev\*.*" "@OfficeHtm\dev\" /E /Y');

/* execute build */
@EXEC(EXE='@OfficeHtm\dev\eSuite_site_en\build-dev.bat @Office');

/* RESULT */
@WIZRPL(DIR=@OfficeHtm\dev\eSuite\);
@WIZRPL(FILE=BUILD.TXT);
@FMT(CMP,'@msgFILE(FINDINFILE,[ERR])=','®WIZRPL(SUBJECT=SENCHA BUILD SUCCESS)','®WIZRPL(X-PRIORITY=1)®WIZRPL(SUBJECT=SENCHA BUILD ERROR)');
@WIZCLR(DIR);
@WIZCLR(FILE);

@WIZRPL(TARGET=@TER);
@EXEC(SQT=@OfficeHtm\dev\eSuite\BUILD.TXT);
