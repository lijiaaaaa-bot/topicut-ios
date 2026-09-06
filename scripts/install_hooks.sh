#!/usr/bin/env bash
# Installs scripts/gate.sh as the pre-commit hook. Re-run after cloning.
set -euo pipefail
root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
hook="$root/.git/hooks/pre-commit"
cat > "$hook" <<'EOF'
#!/usr/bin/env bash
exec bash "$(git rev-parse --show-toplevel)/scripts/gate.sh"
EOF
chmod +x "$hook"
echo "installed $hook"
