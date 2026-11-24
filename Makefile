HARE = hare

# JJGui (vinduer og grafik) er med som standard: Wayland i ren Hare + SDL2 til X11.
#   make HARE_ONLY=1   kun Wayland, ingen SDL2
#   make NOJJ=1        helt uden JJGui (som før 0.10)
ifdef NOJJ
JJFLAGS = -T +nojj
else ifdef HARE_ONLY
JJFLAGS = -T +nosdl
else
JJFLAGS = -lSDL2
endif

# tools/embed (Hare) lægger runtime'en ind i cmd/dsh/rtsrc.ha til Violet
dsh-hare: cmd/dsh/*.ha cmd/dsh/*.s viper/*.ha tools/embed/main.ha
	@$(HARE) run tools/embed/
	$(HARE) build -lc $(JJFLAGS) -o $@ cmd/dsh/

test: dsh-hare
	./dsh-hare tests/run.Dash

bench: dsh-hare
	./dsh-hare bench.Dash

install: dsh-hare
	install -Dm755 dsh-hare $(HOME)/.local/bin/dsh-hare

# Gør dsh-hare til "dsh". Python-prototypen bliver ved som dsh-py.
# (rm først: ~/.local/bin/dsh er et symlink til dsh.py, som ellers ville
# blive overskrevet.)
install-dsh: dsh-hare
	rm -f $(HOME)/.local/bin/dsh
	install -Dm755 dsh-hare $(HOME)/.local/bin/dsh
	ln -sf dsh $(HOME)/.local/bin/violet
	ln -sf dsh $(HOME)/.local/bin/violet-run
	ln -sf dsh $(HOME)/.local/bin/miguel
	@if [ -f $(HOME)/dsh/dsh.py ]; then ln -sf $(HOME)/dsh/dsh.py $(HOME)/.local/bin/dsh-py; fi
	@echo "⚡ dsh er nu Hare-versionen ($$($(HOME)/.local/bin/dsh --version | grep -o '[0-9.]*-hare'))"

# Farver til .Dash i nano, Kate/KWrite og xed/gedit/Pluma (GtkSourceView)
NANO_DIR = $(HOME)/.local/share/nano
KATE_DIR = $(HOME)/.local/share/org.kde.syntax-highlighting/syntax
install-syntax:
	install -Dm644 syntax/dash.nanorc $(NANO_DIR)/dash.nanorc
	@touch $(HOME)/.nanorc
	@grep -qs 'dash.nanorc' $(HOME)/.nanorc || echo 'include "$(NANO_DIR)/dash.nanorc"' >> $(HOME)/.nanorc
	install -Dm644 syntax/dash.xml $(KATE_DIR)/dash.xml
	install -Dm644 syntax/dash.lang $(HOME)/.local/share/gtksourceview-4/language-specs/dash.lang
	install -Dm644 syntax/dash.lang $(HOME)/.local/share/gtksourceview-3.0/language-specs/dash.lang
	install -Dm644 syntax/dash.lang $(HOME)/.local/share/gtksourceview-5/language-specs/dash.lang
	@echo "🎨 farver installeret — åbn en .Dash-fil i nano, Kate eller xed"

# Miguel 🎸 i Kate: LSP-klienten får at vide, at .Dash-filer har Miguel.
# (Har du allerede egne servere i settings.json, så sæt "dash"-delen ind selv.)
KATE_LSP = $(HOME)/.config/kate/lspclient/settings.json
install-miguel: install-dsh install-syntax
	@if [ -f $(KATE_LSP) ] && ! grep -qs '"dash"' $(KATE_LSP); then \
		echo "⚠ $(KATE_LSP) findes allerede — sæt indholdet af syntax/miguel-kate.json ind i den selv"; \
	else \
		install -Dm644 syntax/miguel-kate.json $(KATE_LSP); \
		echo "🎸 Miguel spiller nu med i Kate (Indstillinger → LSP-klient)"; \
	fi

# Miguel 🎸 i xed: et plugin, der viser fejl fra dsh check i .Dash-filer.
# Slå det til i xed: Rediger → Indstillinger → Udvidelsesmoduler → Miguel (Dash).
XED_PLUGINS = $(HOME)/.local/share/xed/plugins
install-xed: install-dsh install-syntax
	install -Dm644 syntax/xed/miguel.plugin $(XED_PLUGINS)/miguel.plugin
	install -Dm644 syntax/xed/miguel.py $(XED_PLUGINS)/miguel.py
	@echo "🎸 Miguel-pluginet er i xed — slå det til under Indstillinger → Udvidelsesmoduler"

clean:
	rm -f dsh-hare

.PHONY: test bench install install-dsh install-syntax install-miguel install-xed clean
