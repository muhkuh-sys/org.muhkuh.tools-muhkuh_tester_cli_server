rem Run the lua5.1.exe in the path of this scrip file. Here is a way how to get the path of this script:
rem https://stackoverflow.com/questions/3827567/how-to-get-the-path-of-the-batch-script-in-windows
SET SELFBAT=%~dp0
SET SELFDIR=%SELFBAT:~0,-1%
%SELFDIR%\lua5.4 %SELFDIR%\cli_server.lua
