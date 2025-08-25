#!/bin/bash

# Azure MySQL PMM Setup Script
# Replace the variables below with your actual Azure MySQL details

# =============================================================================
# CONFIGURATION - UPDATE THESE VALUES
# =============================================================================

# Your Azure MySQL server details
AZURE_MYSQL_HOST="myus.mysql.database.azure.com"
AZURE_MYSQL_PORT="3306"
AZURE_MYSQL_USERNAME="pmm_monitor"
AZURE_MYSQL_PASSWORD="admin"
SERVICE_NAME="my-azure-mysql"

# PMM Server details (usually don't need to change)
PMM_SERVER_URL="https://admin:admin@localhost:443"

# =============================================================================
# DO NOT MODIFY BELOW THIS LINE
# =============================================================================

echo "=== Azure MySQL PMM Monitoring Setup ==="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check if variables are set
check_variables() {
    if [[ "$AZURE_MYSQL_HOST" == "YOUR_SERVER_NAME.mysql.database.azure.com" ]] || 
       [[ "$AZURE_MYSQL_USERNAME" == "pmm_monitor@YOUR_SERVER_NAME" ]]; then
        echo -e "${RED}ERROR: Please update the configuration variables in this script first!${NC}"
        echo "Edit the variables at the top of this script with your actual Azure MySQL details."
        exit 1
    fi
}

# Function to test MySQL connection
test_mysql_connection() {
    echo -e "${YELLOW}Step 1: Testing MySQL connection...${NC}"
    
    # Test connection (username is already set correctly)
    if mysql -h "$AZURE_MYSQL_HOST" -P "$AZURE_MYSQL_PORT" -u "$AZURE_MYSQL_USERNAME" -p"$AZURE_MYSQL_PASSWORD" --ssl-mode=REQUIRED -e "SELECT 'Connection successful' as Status, VERSION() as Version;" 2>/dev/null; then
        echo -e "${GREEN}✓ MySQL connection successful!${NC}"
        return 0
    else
        echo -e "${RED}✗ MySQL connection failed!${NC}"
        echo "Please check:"
        echo "  - Hostname: $AZURE_MYSQL_HOST"
        echo "  - Username: $AZURE_MYSQL_USERNAME"
        echo "  - Password: [hidden]"
        echo "  - Azure firewall settings"
        return 1
    fi
}

# Function to verify PMM Server
verify_pmm_server() {
    echo -e "${YELLOW}Step 2: Verifying PMM Server...${NC}"
    
    if curl -k -s "https://localhost:443" > /dev/null; then
        echo -e "${GREEN}✓ PMM Server is accessible${NC}"
        return 0
    else
        echo -e "${RED}✗ Cannot access PMM Server at https://localhost:443${NC}"
        echo "Please make sure PMM Server is running:"
        echo "  docker ps --filter name=pmm-server"
        return 1
    fi
}

# Function to add MySQL to PMM
add_mysql_to_pmm() {
    echo -e "${YELLOW}Step 3: Adding MySQL to PMM monitoring...${NC}"
    
    # Add MySQL service to PMM
    docker run --rm -it --entrypoint pmm-admin --network host percona/pmm-client:3 \
        add mysql \
        --server-insecure-tls \
        --server-url="$PMM_SERVER_URL" \
        --username="$AZURE_MYSQL_USERNAME" \
        --password="$AZURE_MYSQL_PASSWORD" \
        --service-name="$SERVICE_NAME" \
        --host="$AZURE_MYSQL_HOST" \
        --port="$AZURE_MYSQL_PORT" \
        --query-source=perfschema \
        --tls
        
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ MySQL service added to PMM successfully!${NC}"
        return 0
    else
        echo -e "${RED}✗ Failed to add MySQL service to PMM${NC}"
        return 1
    fi
}

# Function to show next steps
show_next_steps() {
    echo ""
    echo -e "${GREEN}=== Setup Complete! ===${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Open your browser and go to: https://localhost:443"
    echo "2. Login with username: admin, password: admin"
    echo "3. Navigate to 'MySQL' dashboards to see your Azure MySQL metrics"
    echo "4. Check 'Query Analytics' for query performance data"
    echo ""
    echo "Your Azure MySQL service is now being monitored with the name: $SERVICE_NAME"
}

# Main execution
main() {
    check_variables
    
    if test_mysql_connection && verify_pmm_server; then
        if add_mysql_to_pmm; then
            show_next_steps
        else
            echo -e "${RED}Setup failed at the PMM configuration step.${NC}"
            exit 1
        fi
    else
        echo -e "${RED}Setup failed during connectivity checks.${NC}"
        exit 1
    fi
}

# Run main function
main

# =============================================================================
# TROUBLESHOOTING TIPS
# =============================================================================
#
# If you encounter issues:
#
# 1. Connection refused:
#    - Check Azure MySQL firewall rules
#    - Verify your IP is allowed
#    - Confirm the hostname is correct
#
# 2. Authentication failed:
#    - Verify username format (might need @servername suffix)
#    - Check password
#    - Ensure pmm_monitor user exists and has proper privileges
#
# 3. PMM Server issues:
#    - Check if PMM Server is running: docker ps --filter name=pmm-server
#    - Restart PMM Server if needed: docker restart pmm-server
#
# 4. SSL/TLS issues:
#    - Azure MySQL typically requires SSL
#    - Remove --tls if you have SSL configured
#
# =============================================================================
