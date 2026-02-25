CC     = clang
CFLAGS = -framework Foundation -framework CoreData \
         -Wall -Wno-deprecated-declarations \
         -fobjc-arc
TARGET = cider
SRC    = main.m core.m notes.m reminders.m sync.m

.PHONY: all clean install test test-sync

all: $(TARGET)

$(TARGET): $(SRC) cider.h
	$(CC) $(CFLAGS) -o $(TARGET) $(SRC)
	@echo "Built: ./$(TARGET)"

install: $(TARGET)
	cp $(TARGET) /usr/local/bin/$(TARGET)
	@echo "Installed to /usr/local/bin/$(TARGET)"

test: $(TARGET)
	./test.sh ./$(TARGET)

test-sync: $(TARGET)
	./test-sync.sh ./$(TARGET)

clean:
	rm -f $(TARGET)
