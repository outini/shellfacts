CONFIGDIR = etc/shellfacts
BINDIR    = usr/bin
DOCDIR    = usr/share/doc/shellfacts
MANDIR    = usr/share/man/man8

build:

install:
	mkdir -p $(DESTDIR)/$(CONFIGDIR)
	mkdir -p $(DESTDIR)/$(BINDIR)
	mkdir -p $(DESTDIR)/$(MANDIR)

	cp -R facts.d $(DESTDIR)/$(CONFIGDIR)/
	cp -R shellfacts $(DESTDIR)/$(BINDIR)/
	cp -R manpages/* $(DESTDIR)/$(MANDIR)/

	install -D -m 644 debian/copyright $(DESTDIR)/$(DOCDIR)/copyright
clean:

package:
	debuild -us -uc --lintian-opts -X po-debconf
