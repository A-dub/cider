CC     = clang
CFLAGS = -framework Foundation -framework CoreData \
         -Wall -Wno-deprecated-declarations \
         -fobjc-arc
TARGET = cider
SRCDIR = src
SRC    = $(SRCDIR)/main.m $(SRCDIR)/core.m $(SRCDIR)/notes.m \
         $(SRCDIR)/reminders.m $(SRCDIR)/sync.m

.PHONY: all clean install test test-sync

all: $(TARGET)

$(TARGET): $(SRC) $(SRCDIR)/cider.h
	$(CC) $(CFLAGS) -I$(SRCDIR) -o $(TARGET) $(SRC)
	@echo "Built: ./$(TARGET)"

install: $(TARGET)
	cp $(TARGET) /usr/local/bin/$(TARGET)
	@echo "Installed to /usr/local/bin/$(TARGET)"

test: $(TARGET)
	./tests/test.sh ./$(TARGET)

test-sync: $(TARGET)
	./tests/test-sync.sh ./$(TARGET)

clean:
	rm -f $(TARGET)
