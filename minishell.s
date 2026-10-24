// ============================================================================
// SECCIÓN DE DATOS INICIALIZADOS (.data)
// Almacena cadenas constantes y estructuras estáticas para el entorno.
// ============================================================================
.section .data
    texto_prompt:           .asciz "MiniShell> "                        // Prompt principal del intérprete
    error_limite_args:      .asciz "Error: máximo 16 argumentos\n"      // Error cuando se superan las 16 palabras

    nombre_clear:           .asciz "clear"                              // Identificador del comando interno clear
    nombre_help:            .asciz "help"                               // Identificador del comando interno help
    nombre_echo:            .asciz "echo"                               // Identificador del comando interno echo
    nombre_exit:            .asciz "exit"                               // Identificador del comando interno exit

    texto_ayuda:            .asciz "Comandos internos disponibles:\n  help  - Muestra esta ayuda\n  clear - Limpia la pantalla\n  echo  - Imprime argumentos en consola\n  exit  - Cierra el MiniShell\nComandos externos soportados: ls, pwd, date, etc.\n"
    texto_limpiar:          .asciz "\033[2J\033[H"                      // Secuencia de escape ANSI para limpiar consola
    texto_desconocido:      .asciz "Comando desconocido: "              // Mensaje de error si el comando no existe
    texto_espacio:          .asciz " "                                  // Espacio separador para comando_echo
    texto_salto_linea:      .asciz "\n"                                 // Salto de línea estándar (Enter)

    prefijo_bin:            .asciz "/bin/"                              // Prefijo estándar para buscar binarios como ls, pwd, date
    error_clonar:           .asciz "Error: clone no pudo crear el proceso hijo.\n" // Error si falla la syscall 220
    error_esperar:          .asciz "Error: wait4 falló al esperar al hijo.\n"      // Error si falla la syscall 260

    .balign 8                                                           // Alinea a 8 bytes porque es un puntero de 64 bits
    entorno_vacio:          .quad 0                                     // Arreglo envp vacío terminado en NULL

// ============================================================================
// SECCIÓN DE DATOS NO INICIALIZADOS (.bss)
// Reserva espacio en RAM para lectura, arreglo de punteros, rutas y estado.
// ============================================================================
.section .bss
    .align 3                                                            // Alinea a 8 bytes (2^3)
    buffer_entrada:         .space 128                                  // 128 bytes para almacenar lo que escribe el usuario

    // Buffer para construir rutas como "/bin/ls" cuando el usuario solo escribe "ls"
    .align 3                                                            // Alinea a 8 bytes
    buffer_ruta:            .space 140                                  // Espacio para "/bin/" (5 bytes) + comando + '\0'

    .balign 8                                                           // Alineación estricta a 64 bits (8 bytes por puntero)
    arreglo_argv:           .skip 136                                   // 16 punteros de argumentos (128B) + 1 puntero NULL (8B)

    .balign 4                                                           // Alineación a 32 bits (4 bytes) porque wait4 escribe un entero
    estado_hijo:            .skip 4                                     // Entero de 4 bytes donde wait4 guarda cómo terminó el hijo

.section .text
.global _start                                                          

// ============================================================================
// Ciclo infinito: muestra prompt -> lee -> separa palabras -> ejecuta comando
// ============================================================================
_start:
ciclo_principal_shell:
    // Mostrar el prompt
    ldr x1, =texto_prompt                   // Carga en x1 la dirección de "MiniShell> "
    bl imprimir_cadena                      // Llama a imprimir_cadena para mostrar el prompt en pantalla

    // Leer comando desde teclado
    bl leer_linea                           // Limpia el buffer y ejecuta syscall read (63)
    cmp x0, #0                              // Verifica cuántos bytes leyó la syscall read
    b.le comando_exit                       // Si leyó <= 0 bytes (Ctrl+D / EOF o error), cierra el shell

    // Separar palabras y construir arreglo_argv 
    ldr x0, =buffer_entrada                 // Parámetro 1 (x0): dirección del texto ingresado
    ldr x1, =arreglo_argv                   // Parámetro 2 (x1): dirección del arreglo de punteros a llenar
    mov x2, #16                             // Parámetro 3 (x2): máximo 16 argumentos permitidos
    bl separar_argumentos                   // Corta las palabras; retorna en x0 la cantidad (argc) o -1 si excede 16

    // Validación de línea vacía o exceso de argumentos
    cmp x0, #0                              // Compara la cantidad de palabras detectadas (en x0) con 0
    b.lt error_demasiados_argumentos        // Si x0 < 0 (-1), salta a mostrar error de límite de argumentos
    b.eq ciclo_principal_shell              // Si x0 == 0 (solo presionó Enter o espacios), vuelve a mostrar el prompt

    // Enrutar a comando interno o lanzar proceso externo 
    ldr x0, =arreglo_argv                   // Parámetro 1 (x0): dirección del arreglo de punteros arreglo_argv
    bl enrutar_comando                      // Ejecuta comando interno o delega a ejecutar_comando_externo
    b ciclo_principal_shell                 // Al finalizar el comando, regresa al inicio del ciclo principal

error_demasiados_argumentos:
    ldr x1, =error_limite_args              // Carga en x1 el mensaje de error por más de 16 argumentos
    bl imprimir_cadena                      // Imprime el error en consola
    b ciclo_principal_shell                 // Regresa al ciclo principal


// ============================================================================
// FUNCIÓN 1 (Con Stack Frame): leer_linea
// Descripción: Limpia buffer_entrada y captura hasta 127 caracteres del teclado.
// Parámetros: Ninguno (void)
// Retorna: x0 = bytes leídos por syscall read (0 si EOF, <0 si error)
// Manejo de Stack: Preserva x29 (fp) y x30 (lr) con STP/LDP porque invoca limpiar_entrada.
// ============================================================================
leer_linea:
    stp x29, x30, [sp, #-16]!               // Reserva 16 bytes en el stack y guarda Frame Pointer (x29) y Link Register (x30)
    mov x29, sp                             // Actualiza el Frame Pointer al nivel actual del Stack Pointer

    bl limpiar_entrada                      // Llama a limpiar_entrada para borrar restos del comando anterior

    mov x0, #0                              // Parámetro 1 (x0): descriptor 0 (stdin / teclado)
    ldr x1, =buffer_entrada                 // Parámetro 2 (x1): dirección donde se guardará el texto leído
    mov x2, #127                          // Parámetro 3 (x2): leer máximo 127 bytes (deja 1 byte para '\0')
    mov x8, #63                             // Syscall 63: read en Linux ARM64
    svc #0                                  // Llama al kernel; retorna en x0 el número de bytes leídos

    ldp x29, x30, [sp], #16                 // Restaura x29 y x30 desde el stack y libera los 16 bytes
    ret                                     // Retorna a ciclo_principal_shell


// ============================================================================
// FUNCIÓN HOJA 1 (Sin Stack Frame): limpiar_entrada
// Descripción: Pone en cero los 128 bytes de buffer_entrada en bloques de 8 bytes.
// Parámetros: Ninguno (void)
// Retorna: Nada (void)
// ============================================================================
limpiar_entrada:
    ldr x1, =buffer_entrada                 // Carga en x1 la dirección inicial de buffer_entrada
    mov x2, #0                              // Inicializa el contador de bloques de 8 bytes en 0
ciclo_limpiar_entrada:
    cmp x2, #16                             // Verifica si ya se recorrieron los 16 bloques (16 * 8 = 128 bytes)
    b.ge fin_limpiar_entrada                // Si x2 >= 16, termina la limpieza
    str xzr, [x1], #8                       // Escribe 8 bytes en cero (xzr) en [x1] y avanza x1 en 8 bytes
    add x2, x2, #1                          // Incrementa el contador de bloques en 1
    b ciclo_limpiar_entrada                 // Repite hasta limpiar todo el buffer
fin_limpiar_entrada:
    ret                                     // Retorna a leer_linea


// ============================================================================
// FUNCIÓN HOJA 2 (Sin Stack Frame): separar_argumentos
// Descripción: Divide el buffer por espacios/tabs/enter usando '\0' y llena arreglo_argv.
// Parámetros:
//   x0 = dirección de buffer_entrada
//   x1 = dirección de arreglo_argv
//   x2 = máximo de argumentos permitidos (16)
// Retorna:
//   x0 = cantidad de argumentos (argc) o -1 si hubo desbordamiento
// ============================================================================
separar_argumentos:
    mov x3, x0                              // x3 recorre buffer_entrada carácter por carácter
    mov x4, #0                              // x4 cuenta la cantidad de palabras encontradas (argc = 0)
    mov x5, x1                              // x5 apunta a la casilla actual dentro de arreglo_argv

saltar_espacios:
    ldrb w6, [x3]                           // Lee el byte actual del buffer en w6
    cbz w6, fin_separar_argumentos          // Si es '\0' (0), terminó la cadena y finaliza la función
    cmp w6, #' '                            // Compara si el carácter es espacio (' ')
    b.eq borrar_separador                   // Si es espacio, salta a reemplazarlo por '\0'
    cmp w6, #9                              // Compara si el carácter es tabulación ('\t')
    b.eq borrar_separador                   // Si es tabulación, salta a reemplazarlo por '\0'
    cmp w6, #10                             // Compara si el carácter es salto de línea ('\n')
    b.eq borrar_separador                   // Si es Enter, salta a reemplazarlo por '\0'

    // Se encontró la primera letra de una palabra válida
    cmp x4, x2                              // Verifica si ya alcanzamos el límite de 16 argumentos
    b.ge desbordamiento_argumentos          // Si x4 >= 16, salta a error de desbordamiento
    str x3, [x5]                            // Guarda la dirección donde inicia la palabra en arreglo_argv[x4]
    add x5, x5, #8                          // Avanza el puntero de arreglo_argv en 8 bytes (siguiente casilla)
    add x4, x4, #1                          // Incrementa el contador de argumentos (argc++)

escanear_palabra:
    ldrb w6, [x3]                           // Lee el siguiente carácter de la palabra actual
    cbz w6, fin_separar_argumentos          // Si es '\0', terminó toda la línea
    cmp w6, #' '                            // Verifica si llegó a un espacio delimitador
    b.eq borrar_separador                   // Si es espacio, salta a inyectar '\0'
    cmp w6, #9                              // Verifica si llegó a una tabulación
    b.eq borrar_separador                   // Si es tabulación, salta a inyectar '\0'
    cmp w6, #10                             // Verifica si llegó al salto de línea '\n'
    b.eq borrar_separador                   // Si es '\n', salta a inyectar '\0'
    add x3, x3, #1                          // Si es una letra normal, avanza al siguiente byte
    b escanear_palabra                      // Continúa escaneando la palabra actual

borrar_separador:
    strb wzr, [x3]                          // Sobrescribe el separador con '\0' (0) para cortar la palabra
    add x3, x3, #1                          // Avanza el puntero al siguiente carácter del buffer
    b saltar_espacios                       // Regresa a buscar el inicio de la próxima palabra

fin_separar_argumentos:
    str xzr, [x5]                           // Escribe NULL (0 de 64 bits) al final de arreglo_argv como exige execve
    mov x0, x4                              // Retorna la cantidad de argumentos (argc) en x0
    ret                                     // Regresa a ciclo_principal_shell

desbordamiento_argumentos:
    str xzr, [x5]                           // Asegura que arreglo_argv termine en NULL
    mov x0, #-1                             // Retorna -1 en x0 para indicar error de límite
    ret                                     // Regresa a ciclo_principal_shell


// ============================================================================
// FUNCIÓN 2 (Con Stack Frame): enrutar_comand
// Descripción: Identifica si argv[0] es comando interno; si no, lo lanza como externo.
// Parámetros:
//   x0 = dirección base de arreglo_argv
// Retorna:
//   x0 = 1 si ejecutó un comando interno, 0 si fue manejado como externo
// Manejo de Stack: Preserva x19 (callee-saved) y x30 (lr) con STP/LDP.
// ============================================================================
enrutar_comando:
    stp x19, x30, [sp, #-16]!               // Reserva 16 bytes en el stack y guarda x19 y x30 (lr)
    mov x19, x0                             // Guarda en x19 la dirección base de arreglo_argv para no perderla
    ldr x0, [x19]                           // Carga en x0 la dirección de la primera palabra (argv[0])
    cbz x0, fin_enrutar_comando             // Si argv[0] es NULL, termina y retorna

    // Verificar si es "help"
    ldr x1, =nombre_help                    // Carga en x1 la dirección de la cadena "help"
    bl comparar_cadenas                     // Compara argv[0] con "help"
    cbnz x0, ejecutar_help                  // Si retorna 1, salta a ejecutar_help

    // Verificar si es "echo"
    ldr x0, [x19]                           // Recarga argv[0] en x0
    ldr x1, =nombre_echo                    // Carga en x1 la dirección de la cadena "echo"
    bl comparar_cadenas                     // Compara argv[0] con "echo"
    cbnz x0, ejecutar_echo                  // Si retorna 1, salta a ejecutar_echo

    // Verificar si es "clear"
    ldr x0, [x19]                           // Recarga argv[0] en x0
    ldr x1, =nombre_clear                   // Carga en x1 la dirección de la cadena "clear"
    bl comparar_cadenas                     // Compara argv[0] con "clear"
    cbnz x0, ejecutar_clear                 // Si retorna 1, salta a ejecutar_clear

    // Verificar si es "exit" 
    ldr x0, [x19]                           // Recarga argv[0] en x0
    ldr x1, =nombre_exit                    // Carga en x1 la dirección de la cadena "exit"
    bl comparar_cadenas                     // Compara argv[0] con "exit"
    cbnz x0, ejecutar_exit                  // Si retorna 1, salta a cerrar el shell

    // No es comando interno, intentar ejecutar como comando externo
    mov x0, x19                             // Parámetro 1 (x0): pasa arreglo_argv a ejecutar_comando_externo
    bl ejecutar_comando_externo             // Crea un proceso hijo e intenta ejecutar el binario con execve
    mov x0, #0                              // Retorna 0 indicando que fue procesado como comando externo
    b fin_enrutar_comando                   // Salta al final de la función para restaurar el stack

ejecutar_help:
    bl comando_help                         // Llama a la función del comando interno help
    b comando_reconocido                    // Salta a retornar 1

ejecutar_echo:
    mov x0, x19                             // Pasa la dirección de arreglo_argv en x0
    bl comando_echo                         // Llama a la función del comando interno echo
    b comando_reconocido                    // Salta a retornar 1

ejecutar_clear:
    bl comando_clear                        // Llama a la función del comando interno clear
    b comando_reconocido                    // Salta a retornar 1

ejecutar_exit:
    bl comando_exit                         // Llama a la función comando_exit (termina el programa)

comando_reconocido:
    mov x0, #1                              // Retorna 1 indicando que se ejecutó un comando interno
fin_enrutar_comando:
    ldp x19, x30, [sp], #16                 // Restaura x19 y x30 desde el stack liberando 16 bytes
    ret                                     // Regresa a ciclo_principal_shell


// ============================================================================
// FUNCIÓN 3 (Con Stack Frame): ejecutar_comando_externo
// Descripción: Clona el proceso actual (clone), ejecuta el binario en el hijo
//              (execve) y hace que el padre espere a que termine (wait4).
// Parámetros:
//   x0 = dirección base de arreglo_argv
// Retorna: Nada (void)
// Manejo de Stack: Preserva x19, x20, x29 y x30 reservando 32 bytes en el stack.
// ============================================================================
ejecutar_comando_externo:
    stp x29, x30, [sp, #-32]!               // Reserva 32 bytes en el stack y guarda Frame Pointer (x29) y Link Register (x30)
    mov x29, sp                             // Establece el Frame Pointer actual
    stp x19, x20, [sp, #16]                 // Guarda x19 y x20 en los segundos 16 bytes del stack frame

    mov x20, x0                             // Guarda en x20 la dirección base de arreglo_argv

    // Crear proceso hijo con syscall clone
    mov x0, #17                             // Parámetro 1 (x0): flags = 17 (SIGCHLD para avisar al padre al terminar)
    mov x1, #0                              // Parámetro 2 (x1): stack = 0 (el hijo duplica y usa la pila actual)
    mov x2, #0                              // Parámetro 3 (x2): parent_tid = NULL (no se usa)
    mov x3, #0                              // Parámetro 4 (x3): tls = NULL (no se usa)
    mov x4, #0                              // Parámetro 5 (x4): child_tid = NULL (no se usa)
    mov x8, #220                            // Número de syscall 220: clone en Linux ARM64 (equivalente a fork)
    svc #0                                  // Invoca al kernel: aquí el proceso se divide en PADRE e HIJO

    cmp x0, #0                              // Analiza el valor retornado por clone en x0
    b.lt fallo_clonacion                    // Si x0 < 0, hubo error al clonar y continúa en el padre
    cbz x0, proceso_hijo                    // Si x0 == 0, somos el PROCESO HIJO y saltamos a proceso_hijo

    // Código del PROCESO PADRE (x0 > 0 contiene el PID del hijo)
    mov x19, x0                             // Guarda el PID del proceso hijo en el registro seguro x19
esperar_proceso_hijo:
    mov x0, x19                             // Parámetro 1 (x0): PID del hijo al que queremos esperar
    ldr x1, =estado_hijo                    // Parámetro 2 (x1): dirección donde se guardará el estado de salida
    mov x2, #0                              // Parámetro 3 (x2): options = 0 (esperar hasta que termine)
    mov x3, #0                              // Parámetro 4 (x3): rusage = NULL (sin datos de recursos)
    mov x8, #260                            // Número de syscall 260: wait4 en Linux ARM64
    svc #0                                  // El padre se pausa aquí hasta que el hijo finalice

    cmp x0, #-4                             // Compara retorno con -4 (-EINTR: espera interrumpida por señal)
    b.eq esperar_proceso_hijo               // Si fue interrumpido, repite la espera
    cmp x0, #0                              // Verifica si hubo otro código de error negativo
    b.lt fallo_espera                       // Si x0 < 0, salta a imprimir error de wait4

    b fin_comando_externo                   // El hijo terminó; el padre salta al epílogo para volver al prompt

    // Código del PROCESO HIJO (ejecuta execve)
proceso_hijo:
    // Intento 1: Ejecutar argv[0] directamente (por si escribió "/bin/ls" o "./programa")
    ldr x0, [x20]                           // Parámetro 1 (x0): ruta del programa = argv[0]
    mov x1, x20                             // Parámetro 2 (x1): arreglo de argumentos terminado en NULL
    ldr x2, =entorno_vacio                  // Parámetro 3 (x2): entorno vacío terminado en NULL
    mov x8, #221                            // Número de syscall 221: execve en Linux ARM64
    svc #0                                  // Si funciona, el hijo se transforma en el comando y NUNCA regresa

    // Intento 2: Si falló, el usuario escribió un comando corto como "ls", "pwd" o "date"
    ldr x0, [x20]                           // Parámetro 1 (x0): dirección del nombre del comando (argv[0])
    ldr x1, =buffer_ruta                    // Parámetro 2 (x1): buffer donde se armará "/bin/<comando>"
    bl construir_ruta_bin                   // Une "/bin/" + argv[0] dentro de buffer_ruta

    ldr x0, =buffer_ruta                    // Parámetro 1 (x0): dirección de "/bin/<comando>"
    mov x1, x20                             // Parámetro 2 (x1): arreglo de argumentos original
    ldr x2, =entorno_vacio                  // Parámetro 3 (x2): entorno vacío terminado en NULL
    mov x8, #221                            // Número de syscall 221: execve en Linux ARM64
    svc #0                                  // Intenta ejecutar nuevamente desde /bin/

    // Si el segundo execve también retorna, el comando no existe en el sistema
    ldr x0, [x20]                           // Pasa en x0 el nombre del comando inválido (argv[0])
    bl imprimir_comando_desconocido         // Imprime "Comando desconocido: <cmd>"

    mov x0, #1                              // Código de salida 1 (indica error al padre)
    mov x8, #93                             // Número de syscall 93: exit en Linux ARM64
    svc #0                                  // Destruye únicamente al proceso hijo

fallo_clonacion:
    ldr x1, =error_clonar                   // Carga mensaje de error de clone
    bl imprimir_cadena                      // Lo muestra en consola
    b fin_comando_externo                   // Sale de la función

fallo_espera:
    ldr x1, =error_esperar                  // Carga mensaje de error de wait4
    bl imprimir_cadena                      // Lo muestra en consola

fin_comando_externo:
    ldp x19, x20, [sp, #16]                 // Restaura los registros callee-saved x19 y x20
    ldp x29, x30, [sp], #32                 // Restaura Frame Pointer (x29) y Link Register (x30) y libera 32 bytes
    ret                                     // Retorna a enrutar_comando


// ============================================================================
// FUNCIÓN HOJA 3 (Sin Stack Frame): construir_ruta_bin
// Descripción: Concatena "/bin/" con el comando en argv[0] dentro de buffer_ruta.
// Parámetros:
//   x0 = dirección de la cadena del comando (argv[0], ej. "ls")
//   x1 = dirección del buffer destino (buffer_ruta)
// Retorna: Nada (buffer_ruta queda con "/bin/ls\0")
// ============================================================================
construir_ruta_bin:
    ldr x2, =prefijo_bin                    // Carga en x2 la dirección de la cadena "/bin/"
ciclo_copiar_prefijo:
    ldrb w3, [x2], #1                       // Lee un byte de "/bin/" y avanza x2
    cbz w3, ciclo_copiar_comando            // Al llegar al '\0' de "/bin/", salta a copiar el comando
    strb w3, [x1], #1                       // Escribe el byte en buffer_ruta y avanza x1
    b ciclo_copiar_prefijo                  // Repite hasta copiar todo "/bin/"
ciclo_copiar_comando:
    ldrb w3, [x0], #1                       // Lee un byte de argv[0] y avanza x0
    strb w3, [x1], #1                       // Escribe el byte (incluido el '\0' final) en buffer_ruta
    cbnz w3, ciclo_copiar_comando           // Si no era '\0', sigue copiando letras
    ret                                     // Retorna a proceso_hijo


// ============================================================================
// FUNCIÓN 4 (Con Stack Frame): imprimir_comando_desconocido
// Descripción: Imprime "Comando desconocido: <nombre>\n" cuando falla execve.
// Parámetros:
//   x0 = dirección de la cadena con el nombre del comando (argv[0])
// Retorna: Nada (void)
// Manejo de Stack: Preserva x19 y x30 (lr) con STP/LDP porque invoca imprimir_cadena.
// ============================================================================
imprimir_comando_desconocido:
    stp x19, x30, [sp, #-16]!               // Reserva 16 bytes en el stack y guarda x19 y x30 (lr)
    mov x19, x0                             // Preserva la dirección del nombre del comando en x19

    ldr x1, =texto_desconocido              // Carga en x1 la dirección de "Comando desconocido: "
    bl imprimir_cadena                      // Imprime el prefijo de error

    mov x1, x19                             // Coloca en x1 la dirección del comando no reconocido
    cbz x1, salto_comando_desconocido       // Verifica que no sea nulo por seguridad
    bl imprimir_cadena                      // Imprime el nombre del comando que falló

salto_comando_desconocido:
    ldr x1, =texto_salto_linea              // Carga en x1 la dirección de "\n"
    bl imprimir_cadena                      // Imprime el salto de línea final

    ldp x19, x30, [sp], #16                 // Restaura x19 y x30 desde el stack y libera los 16 bytes
    ret                                     // Retorna a proceso_hijo


// ============================================================================
// FUNCIÓN HOJA 4 (Sin Stack Frame): comparar_cadenas
// Descripción: Compara dos cadenas terminadas en nulo byte por byte.
// Parámetros:
//   x0 = dirección de cadena 1
//   x1 = dirección de cadena 2
// Retorna:
//   x0 = 1 si son idénticas, 0 si son diferentes
// ============================================================================
comparar_cadenas:
ciclo_comparar_byte:
    ldrb w2, [x0]                           // Lee byte actual de la cadena 1 en w2
    ldrb w3, [x1]                           // Lee byte actual de la cadena 2 en w3
    cmp w2, w3                              // Compara ambos bytes
    b.ne cadenas_diferentes                 // Si son distintos, salta a retornar 0
    cbz w2, cadenas_iguales                 // Si son iguales y llegaron a '\0', las cadenas son idénticas
    add x0, x0, #1                          // Avanza al siguiente byte de la cadena 1
    add x1, x1, #1                          // Avanza al siguiente byte de la cadena 2
    b ciclo_comparar_byte                   // Repite la comparación
cadenas_iguales:
    mov x0, #1                              // Retorna 1 (iguales)
    ret                                     // Regresa a enrutar_comando
cadenas_diferentes:
    mov x0, #0                              // Retorna 0 (diferentes)
    ret                                     // Regresa a enrutar_comando


// ============================================================================
// FUNCIÓN HOJA 5 (Sin Stack Frame): comando_help
// Descripción: Muestra la ayuda de comandos internos del MiniShell.
// Parámetros: Ninguno (void)
// Retorna: x0 = bytes escritos
// ============================================================================
comando_help:
    ldr x1, =texto_ayuda                    // Carga en x1 la dirección del mensaje de ayuda
    b imprimir_cadena                       // Salto directo (Tail-Call) a imprimir_cadena


// ============================================================================
// FUNCIÓN HOJA 6 (Sin Stack Frame): comando_clear
// Descripción: Limpia la consola mediante códigos de escape ANSI.
// Parámetros: Ninguno (void)
// Retorna: x0 = bytes escritos
// ============================================================================
comando_clear:
    ldr x1, =texto_limpiar                  // Carga en x1 la secuencia "\033[2J\033[H"
    b imprimir_cadena                       // Salto directo (Tail-Call) a imprimir_cadena


// ============================================================================
// FUNCIÓN 5 (Con Stack Frame): comando_echo
// Descripción: Imprime en pantalla las palabras desde argv[1] separadas por espacio.
// Parámetros:
//   x0 = dirección base de arreglo_argv
// Retorna: Nada (void)
// Manejo de Stack: Preserva x19 y x30 (lr) con STP/LDP porque llama a imprimir_cadena.
// ============================================================================
comando_echo:
    stp x19, x30, [sp, #-16]!               // Reserva 16 bytes en el stack y guarda x19 y x30 (lr)
    add x19, x0, #8                         // Inicializa x19 apuntando a argv[1] (salta "echo")
ciclo_imprimir_palabra:
    ldr x1, [x19]                           // Carga en x1 la dirección de la palabra actual
    cbz x1, imprimir_salto_echo             // Si el puntero es NULL, termina e imprime salto de línea
    bl imprimir_cadena                      // Imprime la palabra actual en consola
    add x19, x19, #8                        // Avanza el puntero al siguiente argumento en arreglo_argv
    ldr x0, [x19]                           // Revisa si existe una palabra siguiente
    cbz x0, imprimir_salto_echo             // Si el siguiente es NULL, no imprime espacio extra
    ldr x1, =texto_espacio                  // Carga en x1 la dirección del espacio " "
    bl imprimir_cadena                      // Imprime el espacio separador
    b ciclo_imprimir_palabra                // Repite para la siguiente palabra
imprimir_salto_echo:
    ldr x1, =texto_salto_linea              // Carga en x1 la dirección de "\n"
    bl imprimir_cadena                      // Imprime el salto de línea final
    ldp x19, x30, [sp], #16                 // Restaura x19 y x30 liberando 16 bytes del stack
    ret                                     // Regresa a enrutar_comando


// ============================================================================
// FUNCIÓN HOJA 7 (Sin Stack Frame): comando_exit
// Descripción: Finaliza la ejecución del MiniShell con código de salida 0.
// Parámetros: Ninguno (void)
// Retorna: No retorna
// ============================================================================
comando_exit:
    mov x0, #0                              // Código de salida 0 (éxito)
    mov x8, #93                             // Número de syscall 93: exit en Linux ARM64
    svc #0                                  // Termina el proceso en el kernel


// ============================================================================
// FUNCIÓN HOJA 8 (Sin Stack Frame): imprimir_cadena
// Descripción: Calcula el largo de una cadena terminada en '\0' y la escribe en stdout.
// Parámetros:
//   x1 = dirección de la cadena terminada en '\0'
// Retorna:
//   x0 = cantidad de bytes escritos
// ============================================================================
imprimir_cadena:
    mov x2, #0                              // Inicializa el contador de longitud en 0
    mov x3, x1                              // Copia el puntero de inicio en x3 para recorrerlo
ciclo_contar_bytes:
    ldrb w4, [x3]                           // Lee el byte actual en w4
    cbz w4, escribir_en_consola             // Si es '\0', salta a invocar la syscall write
    add x3, x3, #1                          // Avanza al siguiente carácter
    add x2, x2, #1                          // Incrementa el contador de longitud
    b ciclo_contar_bytes                    // Repite el ciclo de conteo
escribir_en_consola:
    mov x0, #1                              // Parámetro 1 (x0): descriptor 1 (stdout / pantalla)
    mov x8, #64                             // Número de syscall 64: write en Linux ARM64
    svc #0                                  // Escribe x2 bytes desde la dirección x1
    ret                                     // Regresa al llamador