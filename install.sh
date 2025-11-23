#!/bin/sh
# shellcheck shell=sh
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  1.0.0
##@Author            :  CasjaysDev
##@Contact           :  casjay@yahoo.com
##@License           :  MIT
##@ReadME            :  install-xen-orchestra.sh --help
##@Copyright         :  Copyright (c) 2025, CasjaysDev
##@Created           :  Sunday, Nov 23, 2025 00:00 EST
##@File              :  install-xen-orchestra.sh
##@Description       :  Install Xen Orchestra from source on XCP-ng server
##@Changelog         :  Initial Release
##@TODO              :  Refactor/Rewrite when needed
##@Notes             :  This script installs Xen Orchestra from source with all pro features
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# POSIX compliant shell script for XCP-ng
# Supports CentOS/RHEL/Rocky/Alma 7.x/8.x/9.x and Debian/Ubuntu
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Script variables
SCRIPT_NAME="$(basename "$0" 2>/dev/null)"
INSTALL_DIR="${XO_INSTALL_DIR:-/opt/xen-orchestra}"
XO_USER="${XO_USER:-xo}"
XO_PORT="${XO_PORT:-80}"
NODE_VERSION="${NODE_VERSION:-20}"
REDIS_ENABLE="${REDIS_ENABLE:-true}"

# Colors for output
if [ -t 1 ]; then
  RED="\\033[0;31m"
  GREEN="\\033[0;32m"
  YELLOW="\\033[0;33m"
  BLUE="\\033[0;34m"
  NC="\\033[0m"
else
  RED=""
  GREEN=""
  YELLOW=""
  BLUE=""
  NC=""
fi

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Functions

# Print colored messages
print_msg() {
  printf "%b%s%b\\n" "$2" "$1" "${NC}"
}

print_error() {
  print_msg "ERROR: $1" "${RED}" >&2
}

print_success() {
  print_msg "SUCCESS: $1" "${GREEN}"
}

print_info() {
  print_msg "INFO: $1" "${BLUE}"
}

print_warn() {
  print_msg "WARN: $1" "${YELLOW}"
}

# Check if running as root
check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    print_error "This script must be run as root"
    exit 1
  fi
}

# Detect OS
detect_os() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID="${ID}"
    OS_VERSION="${VERSION_ID}"
    OS_LIKE="${ID_LIKE}"
  elif [ -f /etc/redhat-release ]; then
    OS_ID="rhel"
    OS_VERSION="$(sed 's/.*release \([0-9]\).*/\1/' /etc/redhat-release)"
  else
    print_error "Cannot detect operating system"
    exit 1
  fi

  case "${OS_ID}" in
    centos|rhel|rocky|almalinux)
      PKG_MGR="yum"
      if command -v dnf >/dev/null 2>&1; then
        PKG_MGR="dnf"
      fi
      ;;
    debian|ubuntu)
      PKG_MGR="apt-get"
      ;;
    *)
      print_error "Unsupported OS: ${OS_ID}"
      exit 1
      ;;
  esac

  print_info "Detected OS: ${OS_ID} ${OS_VERSION}"
  print_info "Package manager: ${PKG_MGR}"
}

# Install system dependencies
install_dependencies() {
  print_info "Installing system dependencies..."

  case "${PKG_MGR}" in
    yum|dnf)
      ${PKG_MGR} install -y epel-release 2>/dev/null || true
      ${PKG_MGR} install -y \
        curl \
        git \
        gcc \
        gcc-c++ \
        make \
        openssl-devel \
        redis \
        libpng-devel \
        python3 \
        nfs-utils \
        lvm2 \
        cifs-utils || {
          print_error "Failed to install dependencies"
          exit 1
        }
      ;;
    apt-get)
      apt-get update || {
        print_error "Failed to update package lists"
        exit 1
      }
      apt-get install -y \
        curl \
        git \
        build-essential \
        libssl-dev \
        redis-server \
        libpng-dev \
        python3 \
        nfs-common \
        lvm2 \
        cifs-utils || {
          print_error "Failed to install dependencies"
          exit 1
        }
      ;;
  esac

  print_success "Dependencies installed"
}

# Install Node.js
install_nodejs() {
  print_info "Installing Node.js ${NODE_VERSION}..."

  # Check if Node.js is already installed
  if command -v node >/dev/null 2>&1; then
    CURRENT_VERSION="$(node --version | sed 's/v//' | cut -d. -f1)"
    if [ "${CURRENT_VERSION}" -eq "${NODE_VERSION}" ]; then
      print_info "Node.js ${NODE_VERSION} already installed"
      return 0
    fi
  fi

  # Install Node.js from NodeSource
  curl -fsSL "https://rpm.nodesource.com/setup_${NODE_VERSION}.x" | bash - 2>/dev/null || \
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}.x" | bash - 2>/dev/null || {
    print_error "Failed to setup Node.js repository"
    exit 1
  }

  case "${PKG_MGR}" in
    yum|dnf)
      ${PKG_MGR} install -y nodejs || {
        print_error "Failed to install Node.js"
        exit 1
      }
      ;;
    apt-get)
      apt-get install -y nodejs || {
        print_error "Failed to install Node.js"
        exit 1
      }
      ;;
  esac

  # Verify installation
  if ! command -v node >/dev/null 2>&1; then
    print_error "Node.js installation failed"
    exit 1
  fi

  # Install yarn
  npm install -g yarn || {
    print_error "Failed to install yarn"
    exit 1
  }

  print_success "Node.js $(node --version) and Yarn $(yarn --version) installed"
}

# Create XO user
create_xo_user() {
  print_info "Creating XO user..."

  if id "${XO_USER}" >/dev/null 2>&1; then
    print_info "User ${XO_USER} already exists"
  else
    useradd -r -s /bin/bash -d "${INSTALL_DIR}" -m "${XO_USER}" || {
      print_error "Failed to create user ${XO_USER}"
      exit 1
    }
    print_success "User ${XO_USER} created"
  fi
}

# Clone and build Xen Orchestra
install_xen_orchestra() {
  print_info "Installing Xen Orchestra from source..."

  # Create installation directory
  if [ ! -d "${INSTALL_DIR}" ]; then
    mkdir -p "${INSTALL_DIR}" || {
      print_error "Failed to create directory ${INSTALL_DIR}"
      exit 1
    }
  fi

  # Clone or update repository
  if [ -d "${INSTALL_DIR}/.git" ]; then
    print_info "Updating existing Xen Orchestra installation..."
    cd "${INSTALL_DIR}" || exit 1
    su - "${XO_USER}" -c "cd ${INSTALL_DIR} && git pull" || {
      print_error "Failed to update repository"
      exit 1
    }
  else
    print_info "Cloning Xen Orchestra repository..."
    # Remove directory if it exists but is not a git repo
    if [ -d "${INSTALL_DIR}" ]; then
      rm -rf "${INSTALL_DIR}"
    fi
    git clone https://github.com/vatesfr/xen-orchestra "${INSTALL_DIR}" || {
      print_error "Failed to clone repository"
      exit 1
    }
  fi

  # Set ownership
  chown -R "${XO_USER}:${XO_USER}" "${INSTALL_DIR}"

  # Build Xen Orchestra
  print_info "Building Xen Orchestra (this may take several minutes)..."
  cd "${INSTALL_DIR}" || exit 1

  su - "${XO_USER}" -c "cd ${INSTALL_DIR} && yarn" || {
    print_error "Failed to install dependencies"
    exit 1
  }

  su - "${XO_USER}" -c "cd ${INSTALL_DIR} && yarn build" || {
    print_error "Failed to build Xen Orchestra"
    exit 1
  }

  print_success "Xen Orchestra built successfully"
}

# Configure Xen Orchestra
configure_xen_orchestra() {
  print_info "Configuring Xen Orchestra..."

  CONFIG_FILE="${INSTALL_DIR}/packages/xo-server/.xo-server.toml"

  # Create config if it doesn't exist
  if [ ! -f "${CONFIG_FILE}" ]; then
    cat > "${CONFIG_FILE}" <<EOF
# Xen Orchestra Configuration
# Generated by ${SCRIPT_NAME}

# HTTP listen address
[http]
listen = [
  { port = ${XO_PORT} }
]

# Redis configuration
[redis]
uri = "redis://localhost:6379/0"

# Authentication
[authentication]
defaultTokenValidity = "30 days"

# Logs
[logs]
level = "info"
EOF
    chown "${XO_USER}:${XO_USER}" "${CONFIG_FILE}"
    print_success "Configuration file created: ${CONFIG_FILE}"
  else
    print_info "Configuration file already exists: ${CONFIG_FILE}"
  fi
}

# Setup Redis
setup_redis() {
  if [ "${REDIS_ENABLE}" = "true" ]; then
    print_info "Configuring Redis..."

    # Start and enable Redis
    if command -v systemctl >/dev/null 2>&1; then
      systemctl enable redis 2>/dev/null || systemctl enable redis-server 2>/dev/null || true
      systemctl start redis 2>/dev/null || systemctl start redis-server 2>/dev/null || true
    fi

    print_success "Redis configured"
  fi
}

# Create systemd service
create_systemd_service() {
  print_info "Creating systemd service..."

  SERVICE_FILE="/etc/systemd/system/xo-server.service"

  cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=Xen Orchestra Server
After=network.target redis.service
Wants=redis.service

[Service]
Type=simple
User=${XO_USER}
WorkingDirectory=${INSTALL_DIR}/packages/xo-server
ExecStart=/usr/bin/yarn start
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=xo-server

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload || {
    print_error "Failed to reload systemd"
    exit 1
  }

  systemctl enable xo-server || {
    print_error "Failed to enable xo-server service"
    exit 1
  }

  print_success "Systemd service created"
}

# Configure firewall
configure_firewall() {
  print_info "Configuring firewall..."

  # Skip if behind nginx proxy
  if [ "${XO_PORT}" = "80" ] || [ "${XO_PORT}" = "443" ]; then
    print_warn "Skipping firewall configuration (using standard ports - assume nginx proxy)"
    return 0
  fi

  # Configure firewall based on system
  if command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port="${XO_PORT}/tcp" 2>/dev/null || true
    firewall-cmd --reload 2>/dev/null || true
    print_success "Firewall configured (firewalld)"
  elif command -v ufw >/dev/null 2>&1; then
    ufw allow "${XO_PORT}/tcp" 2>/dev/null || true
    print_success "Firewall configured (ufw)"
  else
    print_warn "No firewall detected, skipping configuration"
  fi
}

# Start service
start_service() {
  print_info "Starting Xen Orchestra service..."

  systemctl start xo-server || {
    print_error "Failed to start xo-server service"
    exit 1
  }

  sleep 5

  if systemctl is-active --quiet xo-server; then
    print_success "Xen Orchestra service started successfully"
  else
    print_error "Xen Orchestra service failed to start"
    systemctl status xo-server
    exit 1
  fi
}

# Print nginx configuration example
print_nginx_config() {
  cat <<EOF

${GREEN}Installation Complete!${NC}

Xen Orchestra is now running on port ${XO_PORT}

${YELLOW}Nginx Reverse Proxy Configuration:${NC}

Add this to your nginx configuration:

${BLUE}upstream xen_orchestra {
    server 127.0.0.1:${XO_PORT};
}

server {
    listen 80;
    server_name xo.yourdomain.com;

    # Redirect to HTTPS
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name xo.yourdomain.com;

    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    client_max_body_size 0;

    location / {
        proxy_pass http://xen_orchestra;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffering off;
        proxy_read_timeout 86400;
    }
}${NC}

${YELLOW}Default Credentials:${NC}
  Email: admin@admin.net
  Password: admin

${RED}IMPORTANT:${NC} Change the default password immediately after first login!

${YELLOW}Service Management:${NC}
  Start:   systemctl start xo-server
  Stop:    systemctl stop xo-server
  Restart: systemctl restart xo-server
  Status:  systemctl status xo-server
  Logs:    journalctl -u xo-server -f

${YELLOW}Configuration:${NC}
  Config file: ${CONFIG_FILE}
  Install dir: ${INSTALL_DIR}

${YELLOW}Updates:${NC}
  cd ${INSTALL_DIR}
  git pull
  yarn
  yarn build
  systemctl restart xo-server

EOF
}

# Show help
show_help() {
  cat <<EOF
${SCRIPT_NAME} - Install Xen Orchestra from source on XCP-ng

Usage: ${SCRIPT_NAME} [OPTIONS]

Options:
  -d, --dir DIR        Installation directory (default: /opt/xen-orchestra)
  -u, --user USER      User to run XO as (default: xo)
  -p, --port PORT      Port to listen on (default: 80)
  -n, --node VERSION   Node.js version (default: 20)
  --no-redis           Disable Redis installation
  -h, --help           Show this help message

Environment Variables:
  XO_INSTALL_DIR       Installation directory
  XO_USER              User to run XO as
  XO_PORT              Port to listen on
  NODE_VERSION         Node.js version to install
  REDIS_ENABLE         Enable/disable Redis (true/false)

Examples:
  # Install with defaults
  ${SCRIPT_NAME}

  # Install to custom directory on custom port
  ${SCRIPT_NAME} --dir /usr/local/xen-orchestra --port 8080

  # Install with custom user and Node.js version
  ${SCRIPT_NAME} --user xenorchestra --node 18

EOF
  exit 0
}

# Parse command line arguments
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -d|--dir)
        INSTALL_DIR="$2"
        shift 2
        ;;
      -u|--user)
        XO_USER="$2"
        shift 2
        ;;
      -p|--port)
        XO_PORT="$2"
        shift 2
        ;;
      -n|--node)
        NODE_VERSION="$2"
        shift 2
        ;;
      --no-redis)
        REDIS_ENABLE="false"
        shift
        ;;
      -h|--help)
        show_help
        ;;
      *)
        print_error "Unknown option: $1"
        show_help
        ;;
    esac
  done
}

# Main installation function
main() {
  print_info "Starting Xen Orchestra installation from source"

  check_root
  parse_args "$@"
  detect_os
  install_dependencies
  install_nodejs
  create_xo_user
  install_xen_orchestra
  configure_xen_orchestra
  setup_redis
  create_systemd_service
  configure_firewall
  start_service
  print_nginx_config
}

# Run main function
main "$@"

exit 0
