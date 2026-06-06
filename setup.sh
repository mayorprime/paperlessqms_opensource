#!/usr/bin/env bash
# PaperlessQMS — Setup & Run Script
# Usage: ./setup.sh [command]

set -euo pipefail

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
header()  { echo -e "\n${BOLD}${BLUE}▶ $*${NC}"; }

# ─── Script location ──────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPRING_DIR="$SCRIPT_DIR/paperlessqms-spring"
ANGULAR_DIR="$SCRIPT_DIR/paperlessqms-spring-client"
FLUTTER_DIR="$SCRIPT_DIR/paperlessqms-flutter"

# ─── Usage ────────────────────────────────────────────────────────────────────
usage() {
  echo -e "${BOLD}PaperlessQMS — Setup & Run Script${NC}"
  echo ""
  echo -e "${BOLD}Usage:${NC}  ./setup.sh <command>"
  echo ""
  echo -e "${BOLD}Commands:${NC}"
  echo "  check          Check all required tools are installed"
  echo "  setup          Install all dependencies (Maven, npm, Flutter pub get)"
  echo ""
  echo "  dev            Start full stack in dev mode (backend + Angular frontend)"
  echo "  backend        Start Spring Boot backend only (H2, port 8080)"
  echo "  frontend       Start Angular frontend only (port 9000)"
  echo "  db             Start PostgreSQL via Docker Compose (port 15432)"
  echo ""
  echo "  flutter-get    Run flutter pub get on all Flutter packages"
  echo "  flutter-run    Run a Flutter app interactively (prompts for which one)"
  echo "  flutter-build  Build all Flutter web apps"
  echo ""
  echo "  stop           Stop all background services started by this script"
  echo "  logs           Tail logs of running background services"
  echo ""
  echo -e "${BOLD}Examples:${NC}"
  echo "  ./setup.sh check          # Verify prerequisites"
  echo "  ./setup.sh setup          # First-time install"
  echo "  ./setup.sh backend        # Run backend alone (for Flutter dev)"
  echo "  ./setup.sh dev            # Run backend + Angular UI together"
  echo "  ./setup.sh flutter-run    # Run a Flutter app against the backend"
}

# ─── Prerequisite checker ─────────────────────────────────────────────────────
check_command() {
  local cmd="$1" label="$2" install_hint="$3"
  if command -v "$cmd" &>/dev/null; then
    success "$label: $(command -v "$cmd")"
    return 0
  else
    error "$label not found. $install_hint"
    return 1
  fi
}

cmd_check() {
  header "Checking prerequisites"
  local all_ok=true

  check_command java     "Java (17+)"   "Install from https://adoptium.net" || all_ok=false
  check_command node     "Node.js (18+)" "Install from https://nodejs.org" || all_ok=false
  check_command npm      "npm"           "Comes with Node.js" || all_ok=false
  check_command flutter  "Flutter"       "Install from https://flutter.dev" || all_ok=false
  check_command docker   "Docker"        "Install from https://docker.com (needed for PostgreSQL)" || true  # optional
  check_command docker   "docker compose" "Install Docker Desktop" || true

  echo ""
  if [ "$SPRING_DIR/mvnw" ]; then
    success "Maven wrapper: $SPRING_DIR/mvnw"
  fi

  # Version checks
  echo ""
  header "Version info"
  java -version 2>&1 | head -1 && true
  node --version && true
  flutter --version 2>&1 | head -1 && true

  if $all_ok; then
    echo ""
    success "All required tools are present."
  else
    echo ""
    warn "Some required tools are missing. See errors above."
    exit 1
  fi
}

# ─── Setup / install dependencies ─────────────────────────────────────────────
cmd_setup() {
  header "Installing Spring Boot dependencies"
  cd "$SPRING_DIR"
  ./mvnw dependency:resolve -q
  success "Maven dependencies resolved."

  header "Installing Angular frontend dependencies"
  cd "$ANGULAR_DIR"
  npm ci
  success "npm dependencies installed."

  header "Installing Flutter dependencies"
  cd "$FLUTTER_DIR"
  bash pubget.sh
  success "Flutter pub get complete."

  echo ""
  success "Setup complete. Run './setup.sh dev' to start the stack."
}

# ─── Start PostgreSQL ──────────────────────────────────────────────────────────
cmd_db() {
  header "Starting PostgreSQL 16.1 (Docker)"
  cd "$SPRING_DIR"
  docker compose -f src/main/docker/postgresql.yml up -d
  success "PostgreSQL started on 127.0.0.1:15432"
  info  "User: paperlessqms | Password: (none, trust auth)"
}

# ─── Start Spring Boot backend ────────────────────────────────────────────────
cmd_backend() {
  header "Starting Spring Boot backend (dev profile, H2, port 8080)"
  cd "$SPRING_DIR"
  info "Logs: $SPRING_DIR/spring.log"
  ./mvnw -ntp spring-boot:run \
    -Dspring-boot.run.profiles=dev \
    2>&1 | tee spring.log
}

# ─── Start Angular frontend ───────────────────────────────────────────────────
cmd_frontend() {
  header "Starting Angular frontend (port 9000, proxies API to :8080)"
  cd "$ANGULAR_DIR"
  npm start
}

# ─── Start backend + frontend together ────────────────────────────────────────
cmd_dev() {
  header "Starting full dev stack"

  # Start backend in background
  info "Starting Spring Boot backend in background..."
  cd "$SPRING_DIR"
  ./mvnw -ntp spring-boot:run -Dspring-boot.run.profiles=dev \
    > "$SPRING_DIR/spring.log" 2>&1 &
  BACKEND_PID=$!
  echo $BACKEND_PID > "$SCRIPT_DIR/.pids/backend.pid"
  mkdir -p "$SCRIPT_DIR/.pids"
  echo $BACKEND_PID > "$SCRIPT_DIR/.pids/backend.pid"
  info "Backend PID: $BACKEND_PID (logs: paperlessqms-spring/spring.log)"

  # Wait for backend to be ready
  info "Waiting for backend on port 8080..."
  local retries=0
  until curl -sf http://localhost:8080/management/health/readiness &>/dev/null; do
    sleep 3
    retries=$((retries+1))
    if [ $retries -ge 40 ]; then
      error "Backend did not start after 2 minutes. Check spring.log."
      exit 1
    fi
    echo -n "."
  done
  echo ""
  success "Backend is ready at http://localhost:8080"

  # Start Angular frontend in foreground
  info "Starting Angular frontend (port 9000)..."
  cd "$ANGULAR_DIR"
  npm start
}

# ─── Flutter pub get ──────────────────────────────────────────────────────────
cmd_flutter_get() {
  header "Running flutter pub get on all packages"
  cd "$FLUTTER_DIR"
  bash pubget.sh
  success "Done."
}

# ─── Flutter run (interactive) ────────────────────────────────────────────────
cmd_flutter_run() {
  header "Flutter app runner"

  echo "Which app do you want to run?"
  echo "  1) paperlessqms-client  (Customer app)"
  echo "  2) paperlessqms-admin   (Admin app)"
  echo "  3) paperlessqms-call    (Agent/counter app)"
  echo ""
  read -rp "Enter choice [1-3]: " choice

  case "$choice" in
    1) APP_DIR="$FLUTTER_DIR/paperlessqms-client" ;;
    2) APP_DIR="$FLUTTER_DIR/paperlessqms-admin" ;;
    3) APP_DIR="$FLUTTER_DIR/paperlessqms-call" ;;
    *) error "Invalid choice."; exit 1 ;;
  esac

  echo ""
  info "Available devices:"
  flutter devices
  echo ""
  read -rp "Enter device ID (or press Enter for default): " device

  cd "$APP_DIR"
  if [ -n "$device" ]; then
    flutter run -d "$device"
  else
    flutter run
  fi
}

# ─── Flutter build all web ────────────────────────────────────────────────────
cmd_flutter_build() {
  header "Building all Flutter web apps"
  cd "$FLUTTER_DIR"
  bash buildweb.sh
  success "All Flutter web builds complete."
}

# ─── Stop background services ─────────────────────────────────────────────────
cmd_stop() {
  header "Stopping background services"
  local pid_dir="$SCRIPT_DIR/.pids"

  if [ -f "$pid_dir/backend.pid" ]; then
    local pid
    pid=$(cat "$pid_dir/backend.pid")
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid"
      success "Backend (PID $pid) stopped."
    else
      warn "Backend PID $pid is not running."
    fi
    rm -f "$pid_dir/backend.pid"
  else
    warn "No backend PID file found."
  fi
}

# ─── Tail logs ────────────────────────────────────────────────────────────────
cmd_logs() {
  local log="$SPRING_DIR/spring.log"
  if [ -f "$log" ]; then
    tail -f "$log"
  else
    error "No log file found at $log. Is the backend running?"
    exit 1
  fi
}

# ─── Entrypoint ───────────────────────────────────────────────────────────────
mkdir -p "$SCRIPT_DIR/.pids"

case "${1:-help}" in
  check)         cmd_check ;;
  setup)         cmd_setup ;;
  dev)           cmd_dev ;;
  backend)       cmd_backend ;;
  frontend)      cmd_frontend ;;
  db)            cmd_db ;;
  flutter-get)   cmd_flutter_get ;;
  flutter-run)   cmd_flutter_run ;;
  flutter-build) cmd_flutter_build ;;
  stop)          cmd_stop ;;
  logs)          cmd_logs ;;
  help|--help|-h) usage ;;
  *)
    error "Unknown command: ${1}"
    echo ""
    usage
    exit 1
    ;;
esac
