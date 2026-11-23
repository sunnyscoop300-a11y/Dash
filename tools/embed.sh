#!/bin/sh
# Lægger dsh' runtime (og JJGui's motor, viper/) ind i cmd/dsh/rtsrc.ha, så
# Violet kan bygge programmer uden at kildekoden skal ligge ved siden af.
# Køres af Makefile.
cd "$(dirname "$0")/../cmd/dsh" || exit 1
out=rtsrc.ha.tmp
lit() {
	sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/	/\\t/g' -e 's/^/\t"/' -e 's/$/\\n"/' "$1"
	echo '	,'
}
{
	echo "// Lavet af tools/embed.sh — rediger ikke. dsh' runtime til Violet."
	printf 'const RT_NAMES: [_]str = ['
	for f in *.ha *.s; do
		case "$f" in main.ha|build.ha|rtsrc.ha|compile.ha|types.ha|miguel.ha) continue ;; esac
		printf '"%s", ' "$f"
	done
	echo '];'
	echo 'const RT_SRCS: [_]str = ['
	for f in *.ha *.s; do
		case "$f" in main.ha|build.ha|rtsrc.ha|compile.ha|types.ha|miguel.ha) continue ;; esac
		lit "$f"
	done
	echo '];'
	printf 'const VIPER_NAMES: [_]str = ['
	for f in ../../viper/*.ha; do
		case "$f" in *+test.ha) continue ;; esac
		printf '"%s", ' "$(basename "$f")"
	done
	echo '];'
	echo 'const VIPER_SRCS: [_]str = ['
	for f in ../../viper/*.ha; do
		case "$f" in *+test.ha) continue ;; esac
		lit "$f"
	done
	echo '];'
} > "$out"
if ! cmp -s "$out" rtsrc.ha 2>/dev/null; then mv "$out" rtsrc.ha; else rm "$out"; fi
