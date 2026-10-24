# MiniShell - Intérprete de Comandos en ARM-64 Puro

Este proyecto implementa un intérprete de comandos (shell) escrito íntegramente en ensamblador ARM-64 puro para Linux, utilizando el ensamblador GAS y sin dependencias de bibliotecas externas de C. Interactúa directamente con el sistema operativo a través de *syscalls* (read, write, clone, execve, wait4, exit).

## Requisitos del Sistema
- Entorno Linux ARM64 (Nativo o emulado vía QEMU `qemu-aarch64`).
- Toolchain de GNU (`aarch64-linux-gnu-as`, `aarch64-linux-gnu-ld`).
- GNU Make.

## Instrucciones de Compilación

El proyecto incluye un `Makefile` automatizado. Para compilar el código fuente y generar el ejecutable, abre la terminal en el directorio raíz del proyecto y ejecuta un solo comando:

```bash
make

## Instrucciones de Ejecución

make run
