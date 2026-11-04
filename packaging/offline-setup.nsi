Unicode true
Name "ii-windows end4 native preview"
OutFile "${OUTPUT}"
RequestExecutionLevel user
SetCompressor zlib
SetCompress off
ShowInstDetails show
BrandingText "Windows native development preview"
Page instfiles

Section
    InitPluginsDir
    SetOutPath "$PLUGINSDIR"
    DetailPrint "Preparing the bundled installer and offline package..."
    File /oname=ii-windows-setup.exe "${SETUP}"
    File /oname=payload.zip "${PACKAGE}"
    DetailPrint "Opening ii-windows Setup. Review the installation there."
    ClearErrors
    ExecWait '"$PLUGINSDIR\ii-windows-setup.exe" --package "$PLUGINSDIR\payload.zip" --no-self-update' $0
    IfErrors launch_failed
    SetErrorLevel $0
    Goto done
launch_failed:
    MessageBox MB_OK|MB_ICONSTOP "Could not open the bundled ii-windows installer."
    SetErrorLevel 1
done:
SectionEnd
