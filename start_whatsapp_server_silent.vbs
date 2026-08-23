Set WshShell = CreateObject("WScript.Shell")
strPath = WshShell.CurrentDirectory

' Get script folder
Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)

batPath = scriptDir & "\start_whatsapp_server.bat"

' Run batch file hidden (0 = hide window, False = don't wait for completion)
If fso.FileExists(batPath) Then
    WshShell.Run """" & batPath & """", 0, False
End If
