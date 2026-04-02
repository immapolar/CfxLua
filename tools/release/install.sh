#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [ -d "$SCRIPT_DIR/runtime" ] && [ -d "$SCRIPT_DIR/bin" ] && [ -d "$SCRIPT_DIR/vm" ]; then
  ROOT_DIR="$SCRIPT_DIR"
else
  ROOT_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
fi
PREFIX="${PREFIX:-/usr/local}"

install -d "$PREFIX/lib/cfxlua"
cp -a "$ROOT_DIR/bin" "$PREFIX/lib/cfxlua/"
cp -a "$ROOT_DIR/runtime" "$PREFIX/lib/cfxlua/"
cp -a "$ROOT_DIR/vm" "$PREFIX/lib/cfxlua/"

install -d "$PREFIX/bin"
LIB_DIR="$PREFIX/lib/cfxlua"
cat > "$PREFIX/bin/cfxlua" <<WRAP
#!/usr/bin/env bash
set -euo pipefail
exec "$LIB_DIR/bin/cfxlua" "\$@"
WRAP
chmod +x "$PREFIX/bin/cfxlua"

echo "Installed cfxlua to $PREFIX/bin/cfxlua"
echo "Run: cfxlua --version"
