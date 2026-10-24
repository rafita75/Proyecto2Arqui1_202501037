AS = aarch64-linux-gnu-as
LD = aarch64-linux-gnu-ld
QEMU = qemu-aarch64

BUILD = build
SRC ?= minishell.s

PROGRAM := $(patsubst %.s,%,$(SRC))
OBJ := $(BUILD)/$(PROGRAM).o
TARGET := $(BUILD)/$(PROGRAM)
DEP := $(OBJ:.o=.d)

ASFLAGS ?= -g -I $(dir $(SRC)) -I .
LDFLAGS ?=

.PHONY: all run gdb-vscode clean info

all: $(TARGET)

$(OBJ): $(SRC)
	@mkdir -p $(@D)
	$(AS) $(ASFLAGS) --MD $(DEP) -o $@ $<

$(TARGET): $(OBJ)
	$(LD) $(LDFLAGS) -o $@ $<

run: $(TARGET)
	$(QEMU) $(TARGET)

gdb-vscode: $(TARGET)
	@echo "Iniciando QEMU y esperando conexión de GDB en el puerto 1234..."
	@{ sleep 0.1; echo "QEMU_GDB_READY"; } & exec $(QEMU) -g 1234 $(TARGET)

clean:
	rm -rf $(BUILD)

info:
	@echo "Comandos disponibles:"
	@echo "  make            -> Compila el proyecto en build/minishell"
	@echo "  make run        -> Compila y ejecuta el MiniShell en QEMU"
	@echo "  make gdb-vscode -> Inicia el servidor GDB en el puerto 1234"
	@echo "  make clean      -> Elimina la carpeta build/"

-include $(DEP)