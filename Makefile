.DEFAULT_GOAL := all
BUILD_DIR=build
BINARY_NAME=TbMM
BSC_FLAGS=--aggressive-conditions -vdir $(BUILD_DIR) -bdir $(BUILD_DIR) -simdir $(BUILD_DIR) -o 
TOP_MODULE=mkTb
BSV_FILES_TRACKED=TbMM.bsv

.PHONY: clean all $(BINARY_NAME)


$(BINARY_NAME):
	mkdir -p $(BUILD_DIR)
	bsc $(BSC_FLAGS) $@ -sim -g $(TOP_MODULE) -u $@.bsv
	bsc $(BSC_FLAGS) $@ -sim -e $(TOP_MODULE)

clean:
	rm -rf $(BUILD_DIR)
	rm -f $(BINARY_NAME)
	rm -f *.so

all: clean $(BINARY_NAME)

