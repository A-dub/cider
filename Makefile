CC     = clang
CFLAGS = -framework Foundation -framework CoreData \
         -Wall -Wno-deprecated-declarations \
         -fobjc-arc
TARGET = cider
SRC    = cider.m

.PHONY: all clean install

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) -o $(TARGET) $(SRC)
	@echo "Built: ./$(TARGET)"

install: $(TARGET)
	cp $(TARGET) /usr/local/bin/$(TARGET)
	@echo "Installed to /usr/local/bin/$(TARGET)"

clean:
	rm -f $(TARGET)

# macOS specific: compile on remote mac and scp back
mac-build:
	scp -P 23 $(SRC) ad@99.99.29.248:/tmp/
	ssh -p 23 ad@99.99.29.248 'cd /tmp && clang -framework Foundation -framework CoreData -o cider cider.m && echo "Build OK"'
