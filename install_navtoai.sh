#!/bin/bash

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

# Fixed configuration
BACKEND_REPO="https://github.com/thefreelight/myshop.git"
FRONTEND_REPO="https://github.com/thefreelight/navtoai.git"
DEPLOY_PATH="/var/www/medusa"
FRONTEND_PORT=8000
BACKEND_PORT=9000
DB_NAME="medusa"
DB_USER="postgres"
DB_PASSWORD="medusa123456"

# Print welcome banner
print_banner() {
    clear
    echo -e "${GREEN}
    ================================================
                NavToAi Platform Installer        
    ================================================
    This script will deploy:
    1. Medusa Backend (Port: 9000)
    2. NavToAi Frontend (Port: 8000)
    3. PostgreSQL Database (Port: 5432)
    4. Redis Cache (Port: 6379)
    5. Nginx Configuration
    ================================================${PLAIN}"
}

# Check root privileges
check_root() {
    if [ "$(whoami)" != "root" ]; then
        echo -e "${RED}Error: This script must be run as root!${PLAIN}"
        exit 1
    fi
}

# System check
check_system() {
    # 检查是否是 Linux 系统
    if [[ "$(uname)" != "Linux" ]]; then
        echo -e "${RED}Error: This script only supports Linux systems!${PLAIN}"
        exit 1
    fi

    # 使用更可靠的方式检测发行版
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        echo -e "${RED}Error: Cannot detect OS type!${PLAIN}"
        exit 1
    fi

    case "$OS" in
        "ubuntu"|"debian"|"linuxmint")
            PACKAGE_MANAGER="apt-get"
            ;;
        "centos"|"rhel"|"fedora"|"rocky"|"almalinux")
            PACKAGE_MANAGER="yum"
            ;;
        "opensuse"|"sles")
            PACKAGE_MANAGER="zypper"
            ;;
        "arch"|"manjaro")
            PACKAGE_MANAGER="pacman"
            ;;
        *)
            echo -e "${YELLOW}Warning: Unsupported distribution: $OS${PLAIN}"
            echo -e "${YELLOW}The script will try to continue, but some features might not work correctly.${PLAIN}"
            read -p "Do you want to continue? (y/n): " continue_install
            if [[ "$continue_install" != "y" && "$continue_install" != "Y" ]]; then
                exit 1
            fi
            ;;
    esac

    echo -e "${GREEN}Detected OS: $OS${PLAIN}"
    echo -e "${GREEN}Package Manager: $PACKAGE_MANAGER${PLAIN}"
}

# Check system requirements
check_requirements() {
    echo -e "${GREEN}Checking system requirements...${PLAIN}"
    
    # Check memory
    mem_total=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$mem_total" -lt 2 ]; then
        echo -e "${RED}Error: Minimum 2GB RAM required${PLAIN}"
        exit 1
    fi

    # Check disk space
    disk_total=$(df -h / | awk '/\//{print $4}' | sed 's/G//')
    if [ "$(echo "$disk_total < 10" | bc)" -eq 1 ]; then
        echo -e "${RED}Error: Minimum 10GB disk space required${PLAIN}"
        exit 1
    fi
}

# Get user input for domain
get_user_input() {
    while true; do
        read -p "Please enter your domain name (e.g., example.com): " DOMAIN_NAME
        if [ -z "$DOMAIN_NAME" ]; then
            echo -e "${RED}Domain name cannot be empty${PLAIN}"
        else
            break
        fi
    done

    # Show confirmation
    echo -e "\n${YELLOW}Configuration Summary:${PLAIN}"
    echo -e "Domain Name: ${GREEN}${DOMAIN_NAME}${PLAIN}"
    echo -e "Frontend Port: ${GREEN}${FRONTEND_PORT}${PLAIN}"
    echo -e "Backend Port: ${GREEN}${BACKEND_PORT}${PLAIN}"
    echo -e "Database Port: ${GREEN}5432${PLAIN}"
    
    read -p "Continue with these settings? (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        exit 1
    fi
}

# Install Docker and Docker Compose
install_docker() {
    echo -e "${GREEN}Installing Docker and Docker Compose...${PLAIN}"
    
    # Install Docker
    curl -fsSL https://get.docker.com | bash
    systemctl start docker
    systemctl enable docker
    
    # Install Docker Compose
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
}

# Clone projects
clone_projects() {
    echo -e "${GREEN}Cloning projects...${PLAIN}"
    mkdir -p $DEPLOY_PATH
    cd $DEPLOY_PATH
    
    echo "Cloning backend repository..."
    git clone $BACKEND_REPO backend
    
    echo "Cloning frontend repository..."
    git clone $FRONTEND_REPO frontend
}

# Setup backend
setup_backend() {
    echo -e "${GREEN}Configuring backend...${PLAIN}"
    cd $DEPLOY_PATH/backend
    
    # Create .env file
    cat > .env << EOF
DATABASE_URL=postgres://${DB_USER}:${DB_PASSWORD}@postgres:5432/${DB_NAME}
REDIS_URL=redis://redis:6379
PORT=${BACKEND_PORT}
STORE_CORS=http://${DOMAIN_NAME}:${FRONTEND_PORT}
ADMIN_CORS=http://${DOMAIN_NAME}:${FRONTEND_PORT}
EOF

    # Create docker-compose.yml
    cat > docker-compose.yml << EOF
version: "3.8"

services:
  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_USER: ${DB_USER}
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_DB: ${DB_NAME}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"
    networks:
      - medusa-network

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    networks:
      - medusa-network

  backend:
    build: .
    depends_on:
      - postgres
      - redis
    ports:
      - "${BACKEND_PORT}:${BACKEND_PORT}"
    env_file:
      - .env
    volumes:
      - .:/app
      - /app/node_modules
    networks:
      - medusa-network
    command: sh -c "npm install && npx medusa migrations run && npm run start"

networks:
  medusa-network:
    driver: bridge

volumes:
  postgres_data:
EOF

    # Create Dockerfile
    cat > Dockerfile << EOF
FROM node:18-alpine

WORKDIR /app

COPY package*.json ./

RUN npm install

COPY . .

EXPOSE ${BACKEND_PORT}

CMD ["npm", "start"]
EOF
}

# Setup frontend
setup_frontend() {
    echo -e "${GREEN}Configuring frontend...${PLAIN}"
    cd $DEPLOY_PATH/frontend
    
    # Create .env file
    cat > .env << EOF
NEXT_PUBLIC_MEDUSA_BACKEND_URL=http://${DOMAIN_NAME}:${BACKEND_PORT}
PORT=${FRONTEND_PORT}
EOF

    # Create docker-compose.yml
    cat > docker-compose.yml << EOF
version: "3.8"

services:
  frontend:
    build: .
    ports:
      - "${FRONTEND_PORT}:${FRONTEND_PORT}"
    env_file:
      - .env
    environment:
      - NODE_ENV=production
EOF

    # Create Dockerfile
    cat > Dockerfile << EOF
FROM node:18-alpine

WORKDIR /app

COPY package*.json ./

RUN npm install

COPY . .

RUN npm run build

EXPOSE ${FRONTEND_PORT}

CMD ["npm", "start"]
EOF
}

# Setup Nginx
setup_nginx() {
    echo -e "${GREEN}Configuring Nginx...${PLAIN}"
    
    case "$PACKAGE_MANAGER" in
        "apt-get")
            apt-get update
            apt-get install -y nginx
            ;;
        "yum")
            yum install -y nginx
            ;;
        "zypper")
            zypper install -y nginx
            ;;
        "pacman")
            pacman -Sy --noconfirm nginx
            ;;
        *)
            echo -e "${YELLOW}Warning: Unsupported package manager. Please install Nginx manually.${PLAIN}"
            read -p "Press Enter to continue after installing Nginx..."
            ;;
    esac

    # Create Nginx configuration
    cat > /etc/nginx/conf.d/medusa.conf << EOF
server {
    listen 80;
    server_name ${DOMAIN_NAME};

    location / {
        proxy_pass http://localhost:${FRONTEND_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }

    location /api {
        proxy_pass http://localhost:${BACKEND_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

    systemctl restart nginx
}

# Start services
start_services() {
    echo -e "${GREEN}Starting services...${PLAIN}"
    
    cd $DEPLOY_PATH/backend
    docker-compose up -d
    
    echo "Waiting for backend services to start..."
    sleep 30
    
    cd $DEPLOY_PATH/frontend
    docker-compose up -d
}

# Save connection information
save_connection_info() {
    echo -e "${GREEN}Saving connection information...${PLAIN}"
    
    cat > ${DEPLOY_PATH}/connection_info.txt << EOF
============================================
      Database Connection Info
============================================
Type: PostgreSQL
Host: localhost or Server IP
Port: 5432
Database: ${DB_NAME}
Username: ${DB_USER}
Password: ${DB_PASSWORD}

============================================
      Redis Connection Info
============================================
Host: localhost or Server IP
Port: 6379
No password
EOF
}

# Main function
main() {
    print_banner
    check_root
    check_system
    check_requirements
    get_user_input
    install_docker
    clone_projects
    setup_backend
    setup_frontend
    setup_nginx
    start_services
    save_connection_info
    
    echo -e "${GREEN}Installation completed successfully!${PLAIN}"
}

# Execute main function
main