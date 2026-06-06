CC      = gcc
CFLAGS  = -Iinc -DPROJ_BUILD=1 -DVERSION=\"0.1\" -std=c99 -Wall -Wextra
LDFLAGS =

SOURCES = src/main.c src/util.c
OBJECTS = $(SOURCES:.c=.o)
TARGET  = proj

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(OBJECTS)
	$(CC) $(LDFLAGS) -o $@ $^

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

clean:
	rm -f $(OBJECTS) $(TARGET)
