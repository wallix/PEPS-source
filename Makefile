RELEASE_TAG = 0.9.9
EXE = peps.exe
PACKNAME =
MAINSRC =
PCKDIR = ./plugins/
PCK = tablesorter.opx \
	html5.notifications.opx \
	mailparser.opx \
	bootstrap.treeview.opx \
	resumable.opx \
	html2text.opx \
	tweetnacl.server.opx \
	tweetnacl.client.opx

PLUGIN =
PLUGINDIR =
OTHER_DEPENDS = resources/*
PARSERS = $(shell awk '{ printf "--parser %s ", $$0 }' peps.syntax)
OPAOPT ?= --opx-dir $(PWD)/_build --warn-error pattern --slicer-check low --no-warn unused --warn-error dbgen.mongo --parser js-like $(PARSERS) --force-server
MONGOREMOTE=localhost:27017
RUN_OPT ?= $(DEBUG_OPT) --db-remote:webmail $(MONGOREMOTE) --db-remote:rawdata $(MONGOREMOTE) --db-remote:sessions $(MONGOREMOTE) --db-remote:tokens $(MONGOREMOTE) --smtp-server-port 2626 --no-ssl false -p 4443 --http-server-port 4443
SRC = $(shell cat peps.conf | grep "src")

POPKG=

OPADIR ?= /usr/local

CONF_FILE = peps.conf

COMPILOPT = $(POPKG)

# Compiler variables
export OPACOMPILER ?= opa
MINIMAL_VERSION = 4419
FLAG = --minimal-version $(MINIMAL_VERSION)

# Build exe
default: exe

# Run Server
run: exe
	./$(EXE) $(RUN_OPT) || true # prevent make error 130 :)

all: clean exe

# Webmail version (hash of active commit). The version is inserted into the static package.
PEPS_VERSION = `git log -n 1 --pretty=format:"%H"`
PEPS_TAG = `git describe --always --tag`
PEPS_VERSION_FILE = src/view/version.opa

TOOLIMPORTS=--import-package stdlib.web.client --import-package stdlib.apis.mongo --import-package stdlib.io.file --import-package stdlib.widgets.dateprinter
TOOLSRC=src/tools/text.opa src/tools/solr.opa src/tools/utils.opa src/tools/path.opa src/tools/search_query.opa src/tools/exim_control.opa src/tools/references.opa

lang/com.mlstate.webmail.tools.translation.opa: $(TOOLSRC)
	@if [ -e _build/com.mlstate.webmail.tools.opx ]; then mv _build/com.mlstate.webmail.tools.opx _build/com.mlstate.webmail.tools.opx.saved; fi
	! $(OPA) --rebuild --i18n-template-opa --i18n-dir lang $(TOOLIMPORTS) --opx-dir $(BUILDDIR) -I $(BUILDDIR) --build-dir $(BUILDDIR)/$(EXE) $(TOOLSRC) -o dummy
	@if [ ! -e _build/com.mlstate.webmail.tools.opx -a -e _build/com.mlstate.webmail.tools.opx.saved ]; then mv _build/com.mlstate.webmail.tools.opx.saved _build/com.mlstate.webmail.tools.opx; fi
	@rm -rf _build/com.mlstate.webmail.tools.opx.broken
	@if [ -e dummy ]; then rm dummy; fi

TOOLVIEWIMPORTS=--import-package com.mlstate.webmail.tools
TOOLVIEWSRC=src/tools/view/form.opa src/tools/view/misc.opa

lang/com.mlstate.webmail.tools.view.translation.opa: $(TOOLVIEWSRC)
	@if [ -e _build/com.mlstate.webmail.tools.view.opx ]; then mv _build/com.mlstate.webmail.tools.view.opx _build/com.mlstate.webmail.tools.view.opx.saved; fi
	! $(OPA) --rebuild --i18n-template-opa --i18n-dir lang $(TOOLVIEWIMPORTS) --opx-dir $(BUILDDIR) -I $(BUILDDIR) --build-dir $(BUILDDIR)/$(EXE) $(TOOLVIEWSRC) -o dummy
	@if [ ! -e _build/com.mlstate.webmail.tools.view.opx -a -e _build/com.mlstate.webmail.tools.view.opx.saved ]; then mv _build/com.mlstate.webmail.tools.view.opx.saved _build/com.mlstate.webmail.tools.view.opx; fi
	@rm -rf _build/com.mlstate.webmail.tools.view.opx.broken
	@if [ -e dummy ]; then rm dummy; fi

STATICIMPORTS=--import-package com.mlstate.webmail.tools --import-package stdlib.crypto --import-package stdlib.io.file
STATICSRC=src/static/text.opa src/static/config.opa src/static/parameters.opa src/static/private.opa

lang/com.mlstate.webmail.static.translation.opa: $(STATICSRC)
	@if [ -e _build/com.mlstate.webmail.static.opx ]; then mv _build/com.mlstate.webmail.static.opx _build/com.mlstate.webmail.static.opx.saved; fi
	! $(OPA) --rebuild --i18n-template-opa --i18n-dir lang $(STATICIMPORTS) --opx-dir $(BUILDDIR) -I $(BUILDDIR) --build-dir $(BUILDDIR)/$(EXE) $(STATICSRC) -o dummy
	@if [ ! -e _build/com.mlstate.webmail.static.opx -a -e _build/com.mlstate.webmail.static.opx.saved ]; then mv _build/com.mlstate.webmail.static.opx.saved _build/com.mlstate.webmail.static.opx; fi
	@rm -rf _build/com.mlstate.webmail.static.opx.broken
	@if [ -e dummy ]; then rm dummy; fi

MODELIMPORTS=--import-package sso --import-package stdlib.web.client --import-package stdlib.web.client --import-package stdlib.web.mail --import-package stdlib.web.mail.smtp.client --import-package stdlib.crypto --import-package stdlib.system --import-package com.mlstate.webmail.tools --import-package com.mlstate.webmail.static --import-package stdlib.apis.mongo --import-package stdlib.database.mongo --import-package stdlib.widgets.bootstrap --import-package bootstrap.treeview --import-package stdlib.apis.oauth
MODELSRC=src/model/db.opa src/model/user.opa src/model/team.opa src/model/contact.opa src/model/sso_client.opa src/model/raw_file.opa src/model/file.opa src/model/file_token.opa src/model/directory.opa src/model/share.opa src/model/share_log.opa src/model/label.opa src/model/search/solr_search.opa src/model/search/solr_journal.opa src/model/search/mongo_search.opa src/model/message.opa src/model/cache.opa src/model/box.opa src/model/smtp.opa src/model/admin.opa src/model/suggest.opa src/model/logger.opa src/model/backup.opa src/model/seqno_session.opa src/model/login.opa src/model/filter.opa src/model/webmailuser.opa src/model/webmailcontact.opa src/model/mode.opa src/model/app.opa src/model/topbar.opa src/model/sidebar.opa src/model/journal.opa src/model/auth.opa src/model/session.opa src/model/oauth.opa src/model/tokens.opa src/model/urn.opa src/model/onboard.opa

lang/com.mlstate.webmail.model.translation.opa: $(MODELSRC)
	@if [ -e _build/com.mlstate.webmail.model.opx ]; then mv _build/com.mlstate.webmail.model.opx _build/com.mlstate.webmail.model.opx.saved; fi
	! $(OPA) --rebuild --i18n-template-opa --i18n-dir lang $(MODELIMPORTS) --opx-dir $(BUILDDIR) -I $(BUILDDIR) --build-dir $(BUILDDIR)/$(EXE) $(MODELSRC) -o dummy
	@if [ ! -e _build/com.mlstate.webmail.model.opx -a -e _build/com.mlstate.webmail.model.opx.saved ]; then mv _build/com.mlstate.webmail.model.opx.saved _build/com.mlstate.webmail.model.opx; fi
	@rm -rf _build/com.mlstate.webmail.model.opx.broken
	@if [ -e dummy ]; then rm dummy; fi

CONTROLLERIMPORTS=--import-package stdlib.core.rpc.core --import-package stdlib.web.client --import-package stdlib.web.mail --import-package stdlib.web.mail.smtp.client --import-package stdlib.widgets.core --import-package stdlib.widgets.loginbox --import-package stdlib.widgets.bootstrap --import-package stdlib.widgets.bootstrap.modal --import-package stdlib.crypto --import-package stdlib.components.login --import-package stdlib.tools.iconv --import-package com.mlstate.webmail.tools --import-package com.mlstate.webmail.static --import-package com.mlstate.webmail.model --import-package stdlib.apis.oauth --import-package mailparser --import-package html2text --import-package tweetnacl
CONTROLLERSRC=src/controller/login.opa src/controller/smtp.opa src/controller/message.opa src/controller/label.opa src/controller/team.opa src/controller/folder.opa src/controller/handler.opa src/controller/complete.opa src/controller/admin.opa src/controller/contact.opa src/controller/file.opa src/controller/settings.opa src/controller/notification.opa src/controller/user.opa src/controller/search.opa src/controller/suggest.opa src/controller/session.opa src/controller/oauth.opa

lang/com.mlstate.webmail.controller.translation.opa: $(CONTROLLERSRC)
	@if [ -e _build/com.mlstate.webmail.controller.opx ]; then mv _build/com.mlstate.webmail.controller.opx _build/com.mlstate.webmail.controller.opx.saved; fi
	! $(OPA) --rebuild --i18n-template-opa --i18n-dir lang $(CONTROLLERIMPORTS) --opx-dir $(BUILDDIR) -I $(BUILDDIR) --build-dir $(BUILDDIR)/$(EXE) $(CONTROLLERSRC) -o dummy
	@if [ ! -e _build/com.mlstate.webmail.controller.opx -a -e _build/com.mlstate.webmail.controller.opx.saved ]; then mv _build/com.mlstate.webmail.controller.opx.saved _build/com.mlstate.webmail.controller.opx; fi
	@rm -rf _build/com.mlstate.webmail.controller.opx.broken
	@if [ -e dummy ]; then rm dummy; fi

VIEWIMPORTS=--import-package stdlib.web.client --import-package stdlib.web.mail --import-package stdlib.components.login --import-package stdlib.widgets.bootstrap --import-package stdlib.widgets.dateprinter --import-package stdlib.crypto --import-package stdlib.widgets.bootstrap.button --import-package stdlib.widgets.bootstrap.transition --import-package stdlib.widgets.bootstrap.collapse --import-package stdlib.widgets.bootstrap.dropdown --import-package stdlib.widgets.bootstrap.modal --import-package stdlib.widgets.bootstrap.tooltip --import-package stdlib.widgets.bootstrap.popover --import-package stdlib.widgets.bootstrap.tab --import-package stdlib.widgets.bootstrap.tooltip --import-package html5.notifications --import-package tablesorter --import-package resumable --import-package bootstrap.treeview --import-package com.mlstate.webmail.tools --import-package com.mlstate.webmail.tools.view --import-package com.mlstate.webmail.static --import-package com.mlstate.webmail.model --import-package com.mlstate.webmail.controller
VIEWSRC=src/view/topbar.opa src/view/sidebar.opa src/view/footer.opa src/view/content.opa src/view/admin.opa src/view/label.opa src/view/label_chooser.opa src/view/team.opa src/view/tree_chooser.opa src/view/folder.opa src/view/contact.opa src/view/settings.opa src/view/file.opa src/view/file_chooser.opa src/view/upload.opa src/view/share.opa src/view/message.opa src/view/compose.opa src/view/notification.opa src/view/search.opa src/view/user.opa src/view/user_chooser.opa src/view/suggest.opa src/view/people.opa src/view/directory.opa src/view/table.opa src/view/onboard.opa

lang/com.mlstate.webmail.view.translation.opa: $(VIEWSRC)
	@if [ -e _build/com.mlstate.webmail.view.opx ]; then mv _build/com.mlstate.webmail.view.opx _build/com.mlstate.webmail.view.opx.saved; fi
	! $(OPA) --rebuild --i18n-template-opa --i18n-dir lang $(VIEWIMPORTS) --opx-dir $(BUILDDIR) -I $(BUILDDIR) --build-dir $(BUILDDIR)/$(EXE) $(VIEWSRC) -o dummy
	@if [ ! -e _build/com.mlstate.webmail.view.opx -a -e _build/com.mlstate.webmail.view.opx.saved ]; then mv _build/com.mlstate.webmail.view.opx.saved _build/com.mlstate.webmail.view.opx; fi
	@rm -rf _build/com.mlstate.webmail.view.opx.broken
	@if [ -e dummy ]; then rm dummy; fi

TOPIMPORTS=--import-package stdlib.web.mail --import-package stdlib.web.mail.smtp.server --import-package stdlib.components.login --import-package stdlib.themes.bootstrap.css --import-package stdlib.widgets.bootstrap --import-package com.mlstate.webmail.tools --import-package com.mlstate.webmail.static --import-package com.mlstate.webmail.model --import-package com.mlstate.webmail.controller --import-package com.mlstate.webmail.view --import-package stdlib.apis.common --import-package stdlib.web.client --import-package mailparser
TOPSRC=src/smtp_server.opa src/init.opa src/main.opa src/rest_api.opa

lang/com.mlstate.webmail.translation.opa: $(TOPSRC)
	@if [ -e _build/com.mlstate.webmail.opx ]; then mv _build/com.mlstate.webmail.opx _build/com.mlstate.webmail.opx.saved; fi
	! $(OPA) --rebuild --i18n-template-opa --i18n-dir lang $(TOPIMPORTS) --opx-dir $(BUILDDIR) -I $(BUILDDIR) --build-dir $(BUILDDIR)/$(EXE) $(TOPSRC) -o dummy
	@if [ ! -e _build/com.mlstate.webmail.opx -a -e _build/com.mlstate.webmail.opx.saved ]; then mv _build/com.mlstate.webmail.opx.saved _build/com.mlstate.webmail.opx; fi
	@rm -rf _build/com.mlstate.webmail.opx.broken
	@if [ -e dummy ]; then rm dummy; fi

.PHONEY: translation po_update clean_i18n
translation: _build/com.mlstate.webmail.tools.translation.opx _build/com.mlstate.webmail.tools.view.translation.opx _build/com.mlstate.webmail.static.translation.opx _build/com.mlstate.webmail.model.translation.opx _build/com.mlstate.webmail.controller.translation.opx _build/com.mlstate.webmail.view.translation.opx _build/com.mlstate.webmail.translation.opx

_build/com.mlstate.webmail.tools.view.translation.opx: lang/com.mlstate.webmail.tools.view.translation.opa
	opa --no-server --parser classic --opx-dir $(BUILDDIR) $<
	@touch $@

_build/com.mlstate.webmail.%.translation.opx: lang/com.mlstate.webmail.%.translation.opa
	opa --no-server --parser classic --opx-dir $(BUILDDIR) $<
	@touch $@

_build/com.mlstate.webmail.translation.opx: lang/com.mlstate.webmail.translation.opa
	opa --no-server --parser classic --opx-dir $(BUILDDIR) $<
	@touch $@

clean_i18n:
	find . -name com.mlstate.webmail.*.\[0-9\]* -print -a -exec rm {} \;

style: resources/css/style.less
	lessc resources/css/style.less resources/css/style.css

clean::
	rm -rf *.opx
	rm -rf *.opx.broken
	rm -rf *.log

version:
	@echo "package com.mlstate.webmail.view\npeps_version=\"$(PEPS_VERSION)\"\npeps_tag=\"$(PEPS_TAG)\"" > $(PEPS_VERSION_FILE)

include Makefile.common
