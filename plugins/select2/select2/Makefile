########################################
# USER VARIABLES
MKLIB = opa-plugin-builder
PLUGNAME = select2.opp
SRC = select2.js dist/js/select2.full.js
CONF =

########################################
# MAKEFILE VARIABLES
ifeq ($(origin BUILDDIR), undefined)
	PWD := $(shell pwd)
	BUILDDIR := $(PWD)/_build/
	export BUILDDIR
endif

########################################
# PLUGIN BUILDING
$(PLUGNAME) : $(SRC)
	@echo "### Building plugin $(PLUGNAME)"
	$(MKLIB) --js-validator-off -o $(@:%.opp=%) $? $(CONF) --build-dir $(BUILDDIR)

########################################
# EXTERNAL SOURCES
select2.min.js:
	curl http://cdnjs.cloudflare.com/ajax/libs/select2/3.5.2/select2.min.js -o select2.min.js

########################################
# CLEANING
clean :
	@echo "### Cleaning plugin $(PLUGNAME)"
	@rm -rf select2.min.js $(BUILDDIR)/$(PLUGNAME)
