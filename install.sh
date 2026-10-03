#!/bin/bash
# Tesla Mac Widget installer.  Run it from Terminal:   ./install.sh
# Safe to run again any time (it skips what's already done and rebuilds the app).
set -euo pipefail
cd "$(dirname "$0")"
REPO="$PWD"
DIR="$HOME/.tesla-widget"

bold() { printf "\n\033[1m%s\033[0m\n" "$*"; }
ok()   { printf "  ✅ %s\n" "$*"; }
info() { printf "  ℹ️  %s\n" "$*"; }
die()  { printf "\n  ❌ %s\n\n" "$*"; exit 1; }
ask()  { local a; read -r -p "  👉 $1 [y/n] " a; [[ "$a" =~ ^[Yy] ]]; }
setting() { grep -E "^$1=" "$DIR/credentials.env" 2>/dev/null | head -1 | cut -d= -f2- | tr -d ' "' || true; }

bold "🚗  Tesla Mac Widget installer"

# ── 1. The basics ─────────────────────────────────────────────────────────────
bold "Step 1 of 7 · Checking your Mac"
[[ "$(uname)" == Darwin ]] || die "This only works on a Mac."
(( $(sw_vers -productVersion | cut -d. -f1) >= 15 )) || die "You need macOS 15 (Sequoia) or newer."
xcodebuild -version >/dev/null 2>&1 || die "Install Xcode from the App Store (it's free), open it once and click Install if it asks, then run ./install.sh again."
ok "macOS and Xcode are ready"

command -v brew >/dev/null || die "Install Homebrew first: open https://brew.sh, copy the one line shown there into Terminal, press Return, then run ./install.sh again."
for tool in xcodegen go gh; do
  command -v "$tool" >/dev/null || { info "Installing $tool…"; brew install "$tool" >/dev/null; }
done
ok "Helper tools are installed"

# ── 2. Your Apple developer team (a free Apple ID is enough) ──────────────────
bold "Step 2 of 7 · Finding your Apple developer account"
mkdir -p "$DIR/overrides" "$DIR/logs"; chmod 700 "$DIR"
[[ -f "$DIR/build.env" ]] && source "$DIR/build.env"
if [[ -z "${TEAM_ID:-}" ]]; then
  TEAM_ID=$(security find-certificate -c "Apple Development" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p' || true)
  [[ -n "$TEAM_ID" ]] || die "No Apple developer certificate yet. In Xcode: Settings → Accounts → + → sign in with your Apple ID.
     Select your name → Manage Certificates… → + → Apple Development → Done. Then run ./install.sh again."
fi
BUNDLE_PREFIX="${BUNDLE_PREFIX:-io.github.teslamacwidget.$(echo "$TEAM_ID" | tr 'A-Z' 'a-z')}"
printf 'TEAM_ID=%s\nBUNDLE_PREFIX=%s\n' "$TEAM_ID" "$BUNDLE_PREFIX" > "$DIR/build.env"
ok "Using Apple team $TEAM_ID"

# ── 3. Keys ───────────────────────────────────────────────────────────────────
bold "Step 3 of 7 · Making your car keys"
if [[ ! -f "$DIR/private-key.pem" ]]; then
  openssl ecparam -name prime256v1 -genkey -noout -out "$DIR/private-key.pem"
  openssl ec -in "$DIR/private-key.pem" -pubout -out "$DIR/public-key.pem" 2>/dev/null
  chmod 600 "$DIR/private-key.pem"
fi
if [[ ! -f "$DIR/tls-cert.pem" ]]; then
  openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -keyout "$DIR/tls-key.pem" -out "$DIR/tls-cert.pem" \
    -sha256 -days 3650 -subj "/CN=localhost" -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" -addext "extendedKeyUsage=serverAuth" 2>/dev/null
  chmod 600 "$DIR/tls-key.pem"
fi
ok "Keys are in ~/.tesla-widget (the private key never leaves your Mac)"

if [[ ! -x "$DIR/bin/tesla-http-proxy" ]]; then
  info "Building Tesla's official command helper (about a minute)…"
  rm -rf "$DIR/src"
  git clone -q --depth 1 https://github.com/teslamotors/vehicle-command "$DIR/src"
  (cd "$DIR/src" && go build -p 2 -o "$DIR/bin/tesla-http-proxy" ./cmd/tesla-http-proxy)
fi
ok "Command helper is ready"

# ── 4. Settings file ─────────────────────────────────────────────────────────
if [[ ! -f "$DIR/credentials.env" ]]; then
  cat > "$DIR/credentials.env" <<'EOF'
# Fill these in from developer.tesla.com (see the README), then save.
TESLA_CLIENT_ID=
TESLA_CLIENT_SECRET=
TESLA_WEBSITE=
EOF
  chmod 600 "$DIR/credentials.env"
fi

# ── 5. Free website for your public key (GitHub Pages) ───────────────────────
bold "Step 4 of 7 · Your free website (Tesla needs it to trust your app)"
SITE=$(setting TESLA_WEBSITE)
if [[ -z "$SITE" ]]; then
  if ! gh auth status >/dev/null 2>&1; then
    info "Log in to GitHub (a browser window opens; make a free account if you don't have one)."
    gh auth login --web --git-protocol https || die "GitHub login didn't finish. Run ./install.sh again."
  fi
  USER_LOGIN=$(gh api user --jq .login)
  SITE="$(echo "$USER_LOGIN" | tr 'A-Z' 'a-z').github.io"
  ask "Put your public key on https://$SITE ? (it's meant to be public)" || die "OK, stopped. Run ./install.sh again when you're ready."
  TMP=$(mktemp -d)
  if gh repo view "$USER_LOGIN/$SITE" >/dev/null 2>&1; then
    gh repo clone "$USER_LOGIN/$SITE" "$TMP/site" -- -q
  else
    gh repo create "$USER_LOGIN/$SITE" --public --description "My website" >/dev/null
    git init -q -b main "$TMP/site"
    (cd "$TMP/site" && git remote add origin "https://github.com/$USER_LOGIN/$SITE.git")
  fi
  mkdir -p "$TMP/site/.well-known/appspecific" "$TMP/site/tesla-callback"
  cp "$DIR/public-key.pem" "$TMP/site/.well-known/appspecific/com.tesla.3p.public-key.pem"
  cp "$REPO/website/tesla-callback/index.html" "$TMP/site/tesla-callback/index.html"
  touch "$TMP/site/.nojekyll"
  [[ -f "$TMP/site/index.html" ]] || echo '<!doctype html><title>Hi</title><p>Hello!</p>' > "$TMP/site/index.html"
  (cd "$TMP/site" && git add -A && git commit -qm "Add Tesla public key and sign-in page" && git push -q -u origin HEAD:main)
  rm -rf "$TMP"
  sed -i '' "s/^TESLA_WEBSITE=.*/TESLA_WEBSITE=$SITE/" "$DIR/credentials.env"
fi
ok "Website: https://$SITE"
info "Checking it's online (GitHub can take a minute or two)…"
for _ in {1..24}; do
  curl -fs -o /dev/null "https://$SITE/.well-known/appspecific/com.tesla.3p.public-key.pem" && { ok "Your public key is online"; break; }
  sleep 5
done

# ── 6. Optional: Tesla's real look, for your own copy only ───────────────────
bold "Step 5 of 7 · Make it look like Tesla's app (optional)"
if [[ ! -f "$DIR/overrides/AppIcon.png" ]] && ask "Download Tesla's app icon from the App Store for your Mac only?"; then
  URL=$(curl -fs "https://itunes.apple.com/lookup?bundleId=com.teslamotors.TeslaApp&country=us" \
        | python3 -c 'import sys,json; print(json.load(sys.stdin)["results"][0]["artworkUrl512"].replace("512x512bb","1024x1024bb"))')
  curl -fs -o "$DIR/overrides/AppIcon.png" "$URL" && ok "Got Tesla's icon"
fi
APP_ICON=AppIcon
if [[ -f "$DIR/overrides/AppIcon.png" ]]; then
  swift tools/make-icon.swift "$DIR/overrides/AppIcon.png" "App/Assets.xcassets/AppIconCustom.appiconset" >/dev/null
  APP_ICON=AppIconCustom
fi
ls "$DIR"/overrides/icon-*.png >/dev/null 2>&1 && ok "Using your own button icons" \
  || info "Want Tesla's button icons too? See \"Tesla's real look\" in the README."

# ── 7. Build and install ─────────────────────────────────────────────────────
bold "Step 6 of 7 · Building the app"
FREE=$(memory_pressure -Q 2>/dev/null | awk -F': ' '/free percentage/{print $2+0}')
if [[ -n "$FREE" && "$FREE" -lt 30 ]]; then
  info "Your Mac only has $FREE% memory free. Closing big apps first makes this faster."
  ask "Build anyway?" || die "OK, stopped. Close some apps and run ./install.sh again."
fi
export TEAM_ID BUNDLE_PREFIX APP_ICON
xcodegen generate --quiet
xcodebuild -project TeslaWidget.xcodeproj -scheme TeslaWidget -configuration Release -derivedDataPath build \
  -allowProvisioningUpdates -jobs 2 build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true
APP="build/Build/Products/Release/Tesla Widget.app"
[[ -d "$APP" ]] || die "The build failed. Open TeslaWidget.xcodeproj in Xcode, pick your team under Signing & Capabilities, and try again."

bold "Step 7 of 7 · Installing"
pkill -x "Tesla Widget" 2>/dev/null && sleep 2 || true
rm -rf "/Applications/Tesla Widget.app"
ditto "$APP" "/Applications/Tesla Widget.app"
pluginkit -r "$REPO/$APP/Contents/PlugIns/TeslaWidgetExtension.appex" 2>/dev/null || true
pkill -f TeslaWidgetExtension 2>/dev/null || true
open "/Applications/Tesla Widget.app"
ok "Installed in Applications. Look for the 🚗 in your menu bar."

bold "🎉  Done! Now follow \"Part 2\" in the README to connect your Tesla."
