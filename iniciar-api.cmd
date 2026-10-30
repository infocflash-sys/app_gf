@echo off
title API Portal Clientes - Grupo Flash
cd /d "%~dp0api"
echo Iniciando la API en http://192.168.110.17:3000 ...
echo (dejar esta ventana abierta mientras se prueba la app; cerrarla apaga la API)
echo.
node src/server.js
pause
