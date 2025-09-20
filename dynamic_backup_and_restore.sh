root@Mysql-DB:/home/ubuntu# cat dynamic_backup_restore.sh
#!/bin/bash

echo "===== MySQL Docker Management Script ====="

# -----------------------------
# Choose operation
# -----------------------------
echo "Select operation:"
echo "1) Backup MySQL container(s)"
echo "2) Restore MySQL container from backup"
read -p "Enter choice (1/2): " OPERATION

if [[ "$OPERATION" != "1" && "$OPERATION" != "2" ]]; then
    echo "❌ Invalid choice!"
    exit 1
fi

# -----------------------------
# List running MySQL containers
# -----------------------------
MYSQL_CONTAINERS=($(docker ps --format "{{.Names}} {{.Image}}" | grep -E "mysql" | awk '{print $1}'))

if [ ${#MYSQL_CONTAINERS[@]} -eq 0 ]; then
    echo "⚠️ No running MySQL containers found!"
    exit 1
fi

echo "Running MySQL containers:"
for i in "${!MYSQL_CONTAINERS[@]}"; do
    echo "$((i+1))) ${MYSQL_CONTAINERS[$i]}"
done
echo ""

# -----------------------------
# MySQL credentials
# -----------------------------
read -p "Enter MySQL username (default: root): " MYSQL_USER
MYSQL_USER=${MYSQL_USER:-root}

read -sp "Enter MySQL password: " MYSQL_PASSWORD
echo ""

# -----------------------------
# Backup Operation
# -----------------------------
if [[ "$OPERATION" == "1" ]]; then
    echo "Enter container numbers to backup (comma-separated) or 'all' for all containers:"
    read -p "Selection: " SELECTION

    declare -a SELECTED_CONTAINERS
    if [[ "$SELECTION" == "all" ]]; then
        SELECTED_CONTAINERS=("${MYSQL_CONTAINERS[@]}")
    else
        IFS=',' read -ra NUMS <<< "$SELECTION"
        for n in "${NUMS[@]}"; do
            idx=$((n-1))
            if [[ $idx -ge 0 && $idx -lt ${#MYSQL_CONTAINERS[@]} ]]; then
                SELECTED_CONTAINERS+=("${MYSQL_CONTAINERS[$idx]}")
            else
                echo "⚠️ Invalid selection: $n"
            fi
        done
    fi

    if [ ${#SELECTED_CONTAINERS[@]} -eq 0 ]; then
        echo "❌ No valid containers selected. Exiting."
        exit 1
    fi

    echo "✅ Selected containers for backup: ${SELECTED_CONTAINERS[*]}"

    BACKUP_DIR="./mysql-backups"
    mkdir -p "$BACKUP_DIR"

    for CONTAINER_NAME in "${SELECTED_CONTAINERS[@]}"; do
        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        BACKUP_FILE="$BACKUP_DIR/${CONTAINER_NAME}_$TIMESTAMP.sql"

        echo "⏳ Taking backup of container '$CONTAINER_NAME'..."
        if docker exec "$CONTAINER_NAME" sh -c "exec mysqldump --all-databases -u$MYSQL_USER -p'$MYSQL_PASSWORD'" > "$BACKUP_FILE"; then
            echo "✅ Backup successful: $BACKUP_FILE"
            gzip "$BACKUP_FILE"
            echo "✅ Backup compressed: ${BACKUP_FILE}.gz"
        else
            echo "❌ Backup failed for container: $CONTAINER_NAME"
        fi
    done

    echo "===== Backup Operation Completed ====="
fi

# -----------------------------
# Restore Operation
# -----------------------------
if [[ "$OPERATION" == "2" ]]; then
    read -p "Enter the container number to restore into: " SELECTION
    idx=$((SELECTION-1))
    if [[ $idx -lt 0 || $idx -ge ${#MYSQL_CONTAINERS[@]} ]]; then
        echo "❌ Invalid selection!"
        exit 1
    fi
    CONTAINER_NAME=${MYSQL_CONTAINERS[$idx]}
    echo "✅ Selected container: $CONTAINER_NAME"

    BACKUP_DIR="./mysql-backups"
    if [ ! -d "$BACKUP_DIR" ]; then
        echo "❌ Backup directory '$BACKUP_DIR' does not exist!"
        exit 1
    fi

    BACKUPS=($(ls -1tr $BACKUP_DIR/*.sql.gz 2>/dev/null))
    if [ ${#BACKUPS[@]} -eq 0 ]; then
        echo "❌ No backup files found in '$BACKUP_DIR'"
        exit 1
    fi

    echo "Available backup files:"
    for i in "${!BACKUPS[@]}"; do
        echo "$((i+1))) ${BACKUPS[$i]##*/}"
    done
    echo ""

    read -p "Enter the backup number to restore: " BACKUP_SELECTION
    idx_backup=$((BACKUP_SELECTION-1))
    if [[ $idx_backup -lt 0 || $idx_backup -ge ${#BACKUPS[@]} ]]; then
        echo "❌ Invalid backup selection!"
        exit 1
    fi

    BACKUP_FILE=${BACKUPS[$idx_backup]}
    echo "✅ Selected backup: $BACKUP_FILE"

    read -p "⚠️ This will overwrite databases in container '$CONTAINER_NAME'. Proceed? (y/n): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "❌ Restore cancelled."
        exit 1
    fi

    echo "⏳ Restoring backup into container '$CONTAINER_NAME'..."
    gunzip -c "$BACKUP_FILE" | docker exec -i "$CONTAINER_NAME" sh -c "mysql -u$MYSQL_USER -p'$MYSQL_PASSWORD'"

    if [ $? -eq 0 ]; then
        echo "✅ Restore completed successfully!"
    else
        echo "❌ Restore failed!"
        exit 1
    fi
fi
