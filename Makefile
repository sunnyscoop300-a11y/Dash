HARE = hare

dsh-hare: cmd/dsh/*.ha cmd/dsh/*.s
	$(HARE) build -lc -o $@ cmd/dsh/

test: dsh-hare
	./tests/run.sh

bench: dsh-hare
	./bench.sh

install: dsh-hare
	install -Dm755 dsh-hare $(HOME)/.local/bin/dsh-hare

# Gør dsh-hare til "dsh". Python-prototypen bliver ved som dsh-py.
# (rm først: ~/.local/bin/dsh er et symlink til dsh.py, som ellers ville
# blive overskrevet.)
install-dsh: dsh-hare
	rm -f $(HOME)/.local/bin/dsh
	install -Dm755 dsh-hare $(HOME)/.local/bin/dsh
	@if [ -f $(HOME)/dsh/dsh.py ]; then ln -sf $(HOME)/dsh/dsh.py $(HOME)/.local/bin/dsh-py; fi
	@echo "⚡ dsh er nu Hare-versionen ($$($(HOME)/.local/bin/dsh --version | grep -o '0\.[0-9]*-hare'))"

# Farver til .Dash i nano og Kate/KWrite
NANO_DIR = $(HOME)/.local/share/nano
KATE_DIR = $(HOME)/.local/share/org.kde.syntax-highlighting/syntax
install-syntax:
	install -Dm644 syntax/dash.nanorc $(NANO_DIR)/dash.nanorc
	@touch $(HOME)/.nanorc
	@grep -qs 'dash.nanorc' $(HOME)/.nanorc || echo 'include "$(NANO_DIR)/dash.nanorc"' >> $(HOME)/.nanorc
	install -Dm644 syntax/dash.xml $(KATE_DIR)/dash.xml
	@echo "🎨 farver installeret — åbn en .Dash-fil i nano eller Kate"

clean:
	rm -f dsh-hare

.PHONY: test bench install install-dsh install-syntax clean
