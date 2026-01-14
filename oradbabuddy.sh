#!/bin/bash
# December 2025 Sandeep Reddy Narani
#
# Interactive database picker
# Displays menu of databases defined in oratab then asks which one to use then uses oraenv to set env variables
# Enhanced Oracle Database Health Check Utility (V22)

############################################
# ANSI Color Codes
############################################
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color
UNDERLINE='\033[4m'
REVERSE='\033[7m'

############################################
# Configuration & Globals
############################################
# Credentials for DBA Mode (Option 2)
# The user is still often hardcoded, but the password is not.
DBA_USER="dbadeeds"
DBA_PASS=""
# NEW WAY (Reading from environment variable)
DBA_PASS=$DBA_PASS
# Or more robustly, check if the variable exists:
# DBA_PASS=${DBA_PASS:?"Error: DBA_PASS environment variable not set"}

# Path to the oratab file
if [ -f /etc/oratab ]; then
    ORATAB=/etc/oratab
elif [ -f /var/opt/oracle/oratab ]; then
    ORATAB=/var/opt/oracle/oratab
else
    echo -e "${RED}ERROR: oratab file not found. Exiting.${NC}"
    exit 1
fi

# Global variable to hold the SERVICE NAME or instance name (used for the connect string)
CONNECT_STRING=""
# Global variable to hold the SYSDBA connection string (used only for SYSDBA mode and PDB listing)
SYSDBA_CONNECT="/ as sysdba"

# Global array to hold consolidated PDB/CDB selection list: FORMAT: CDB_SID::PDB_SERVICE_NAME
VALID_PDB_MAP=()


############################################
# Discover running SIDs and Set Environments
############################################
# Discover SIDS (Instance Names) using the ora_pmon method
DATABASE_SIDS=$(ps -ef | egrep 'ora_pmon' | egrep -v 'grep|egrep' | awk '{print $8}' | cut -d'_' -f3 | sort)

declare -A INSTANCES
VALID_SIDS=()

for SID_FULL in $DATABASE_SIDS; do
    ORACLE_HOME=""
    DB_NAME_ORATAB=""

    # Strategy 1: Attempt prefix match (for RAC/Data Guard instances like aeac004n1 -> aeac004n)
    # This removes the last two characters (e.g., 'p1', 'n1', 'i2') to get a strong prefix.
    DB_PREFIX=$(echo "$SID_FULL" | sed 's/.\{2\}$//')

    # Search ORATAB for an entry starting with this prefix
    ORATAB_LINE=$(grep -E "^${DB_PREFIX}" "${ORATAB}" | grep -v '^#' | head -n 1)

    if [ -n "$ORATAB_LINE" ]; then
        # Prefix match succeeded (e.g., aeac004n matched aeac004nbash)
        DB_NAME_ORATAB=$(echo "$ORATAB_LINE" | cut -d':' -f1)
        ORACLE_HOME=$(echo "$ORATAB_LINE" | cut -d':' -f2)
    else
        # Strategy 2: Attempt exact full SID match (for SIDs like hrbproci or single instance)
        ORATAB_LINE=$(grep -E "^${SID_FULL}:" "${ORATAB}" | grep -v '^#' | head -n 1)
        if [ -n "$ORATAB_LINE" ]; then
            # Exact match succeeded (e.g., hrbproci matched hrbproci)
            DB_NAME_ORATAB=$(echo "$ORATAB_LINE" | cut -d':' -f1)
            ORACLE_HOME=$(echo "$ORATAB_LINE" | cut -d':' -f2)
        fi
    fi

    if [ -z "$ORACLE_HOME" ] || [ ! -d "$ORACLE_HOME" ]; then
        echo -e "${YELLOW}WARNING: ORACLE_HOME not found in ${ORATAB} or path invalid for running SID **$SID_FULL**. Skipping.${NC}"
        continue
    fi

    # Store the running instance name, its ORATAB name (which is the Service Name/DB Name), and its Home
    VALID_SIDS+=("$SID_FULL")
    INSTANCES["$SID_FULL",DB_NAME]="$DB_NAME_ORATAB" # This is the service name used for DBA connections
    INSTANCES["$SID_FULL",HOME]="$ORACLE_HOME"
done

if [ ${#VALID_SIDS[@]} -eq 0 ]; then
    echo -e "${YELLOW}WARNING: No running Oracle instances found that successfully matched an ORACLE_HOME entry. SQL checks will be skipped.${NC}"
fi

set_env_for_sid() {
    local SID=$1
    if [ -z "$SID" ]; then return 1; fi

    ORACLE_SID=$SID
    ORACLE_HOME=${INSTANCES["$SID",HOME]}

    export ORACLE_SID ORACLE_HOME
    export PATH=$ORACLE_HOME/bin:$PATH
    export LD_LIBRARY_PATH=$ORACLE_HOME/lib
    unset TWO_TASK
    return 0
}

############################################
# PDB Selection Utility
############################################

# NEW FUNCTION: Populate the VALID_PDB_MAP array
populate_pdb_map() {
    VALID_PDB_MAP=()
    if [ ${#VALID_SIDS[@]} -eq 0 ]; then
        return 1
    fi

    for SID in "${VALID_SIDS[@]}"; do
        # Temporarily set environment for the current SID
        set_env_for_sid "$SID" || continue
        CDB_NAME="${INSTANCES["$SID",DB_NAME]}"

        # 1. Add the Root Container/CDB itself
        VALID_PDB_MAP+=("$SID::$CDB_NAME")

        # 2. Query available PDBs (MUST use SYSDBA to query v$pdbs in the root container)
        PDB_LIST=$(sqlplus -s "$SYSDBA_CONNECT" <<EOF
SET HEAD OFF FEEDBACK OFF
SELECT name FROM v\$pdbs WHERE con_id > 2;
EXIT;
EOF
)
        PDB_ARRAY=($(echo "$PDB_LIST"))

        # 3. Add PDBs to the map
        for PDB_NAME in "${PDB_ARRAY[@]}"; do
            VALID_PDB_MAP+=("$SID::$PDB_NAME")
        done
    done
    return 0
}

# REVERTED FUNCTION: Select and set PDB/CDB (Vertical Display)
select_and_set_pdb() {
    CONNECT_STRING=""

    # 1. Ensure the map is populated
    populate_pdb_map || return 1

    if [ ${#VALID_PDB_MAP[@]} -eq 0 ]; then
        echo -e "${RED}ERROR: No connectable database services (CDBs or PDBs) found. Cannot proceed.${NC}"
        return 1
    fi

    clear
    echo -e "======================================"
    echo -e " ${BOLD}${CYAN}PDB Selection for DBA Checks${NC}"
    echo -e "======================================"

    # 2. Display the consolidated list vertically
    echo -e "${BOLD}Select Database Service to connect to:${NC}"

    for i in "${!VALID_PDB_MAP[@]}"; do
        MAP_ENTRY="${VALID_PDB_MAP[$i]}"
        DISPLAY_NAME=$(echo "$MAP_ENTRY" | awk -F'::' '{print $2}')
        CDB_SID=$(echo "$MAP_ENTRY" | awk -F'::' '{print $1}')
        CDB_SERVICE="${INSTANCES["$CDB_SID",DB_NAME]}"

        # Determine if it's the CDB or a PDB
        if [ "$DISPLAY_NAME" == "$CDB_SERVICE" ]; then
            TYPE="CDB (Root)"
        else
            TYPE="PDB"
        fi

        # Display vertically
        echo -e " ${YELLOW}$((i + 1)).${NC} ${DISPLAY_NAME} - ${TYPE} (Instance: ${CDB_SID})"
    done
    echo ""

    # 3. Get user choice
    read -p "Enter number for database service: " choice
    CHOICE_INDEX=$((choice - 1))

    if [[ "$CHOICE_INDEX" -lt 0 || "$CHOICE_INDEX" -ge ${#VALID_PDB_MAP[@]} ]]; then
        echo -e "${RED}Invalid choice. Returning to main menu.${NC}"
        wait_for_return
        return 1
    fi

    # 4. Set environment based on selection
    SELECTED_ENTRY="${VALID_PDB_MAP[$CHOICE_INDEX]}"

    # Extract the SID and the final service name
    SELECTED_SID=$(echo "$SELECTED_ENTRY" | awk -F'::' '{print $1}')
    SELECTED_SERVICE=$(echo "$SELECTED_ENTRY" | awk -F'::' '{print $2}')

    # Set the environment for the appropriate CDB
    set_env_for_sid "$SELECTED_SID" || return 1

    # Set the global connection string to the PDB/CDB service name
    CONNECT_STRING="$SELECTED_SERVICE"

    echo -e "\n${GREEN}Using connection: $CONNECT_STRING (via Instance: $SELECTED_SID).${NC}"

    return 0
}

############################################
# Common SQL runner (With Connection Check and Formatting)
############################################
run_sql() {
    local QUERY_STRING=$1
    local COLUMN_FORMATTING=$2
    local CONN_TYPE=$3 # 'SYSDBA' or 'DBA_USER'

    if [ "$CONN_TYPE" == "DBA_USER" ]; then
        CONNECT_STRING_FULL="${DBA_USER}/${DBA_PASS}@${CONNECT_STRING}"
    else
        # For SYSDBA checks, we still need the environment (SID/HOME) set,
        # but the connection string itself is always the local SYSDBA connection.
        CONNECT_STRING_FULL="$SYSDBA_CONNECT"
    fi

    # Perform a silent connection check first
    if ! sqlplus -L -s "$CONNECT_STRING_FULL" <<< "EXIT" > /dev/null 2>&1; then
        echo -e "${RED}ERROR: Could not connect as $CONN_TYPE using connection string: $CONNECT_STRING_FULL.${NC}"
        echo "       Check listener, service name, and user credentials."
        return 1
    fi

    # If connection is successful, run the query
    sqlplus -s "$CONNECT_STRING_FULL" <<EOF
SET LINESIZE 300
SET PAGESIZE 100
SET FEEDBACK OFF
SET HEADING ON
SET COLSEP " | "

-- Standard Column Formats
COLUMN NAME FORMAT A30
COLUMN OPEN_MODE FORMAT A15
COLUMN DATABASE_ROLE FORMAT A15
COLUMN USED_MB FORMAT 999,999,999
COLUMN LIMIT_MB FORMAT 999,999,999
COLUMN SQL_TEXT_PART FORMAT A60
COLUMN ELAPSED_SEC FORMAT 999,999.00
COLUMN STATUS FORMAT A10
COLUMN STATE FORMAT A10

-- Query-specific formatting passed by the calling function
$COLUMN_FORMATTING

$QUERY_STRING

-- Disconnection Command
EXIT
EOF
}

############################################
# SYSDBA Functions (Use SYSDBA_CONNECT)
############################################
status_database() {
    if [ ${#VALID_SIDS[@]} -eq 0 ]; then echo "No database instances found to check."; return; fi
    for SID in "${VALID_SIDS[@]}"; do
        set_env_for_sid "$SID" || continue
        echo -e "---- ${CYAN}Database status for SID: **$SID** (DB: ${INSTANCES["$SID",DB_NAME]})${NC} ----"
        run_sql "SELECT name, open_mode, database_role FROM v\$database;" "" "SYSDBA"
    done
}

# UPDATED: Use srvctl to get services status
rac_services_status() {
    if [ ${#VALID_SIDS[@]} -eq 0 ]; then echo "No database instances found to check."; return; fi

    echo -e "---- ${CYAN}RAC Services Status (using srvctl status service)${NC} ----"

    declare -A CHECKED_DBS

    for SID in "${VALID_SIDS[@]}"; do
        set_env_for_sid "$SID" || continue
        local DB_NAME_FULL="${INSTANCES["$SID",DB_NAME]}"

        if [[ -n "${CHECKED_DBS[$DB_NAME_FULL]}" ]]; then
            continue
        fi

        echo -e "\n${BOLD}Checking services for Database: $DB_NAME_FULL (Instance: $SID)${NC}"

        if command -v srvctl >/dev/null 2>&1; then
            srvctl status service -d "$DB_NAME_FULL" -v
            CHECKED_DBS["$DB_NAME_FULL"]=1
        else
            echo -e "${RED}ERROR: srvctl command not found in the current \$PATH for SID $SID.${NC}"
            echo -e "${YELLOW}Falling back to querying V\$SERVICES for SID: $SID...${NC}"
            # Fallback to the old method if srvctl is missing
            run_sql "SELECT name, network_name FROM v\$services;" "COLUMN NAME FORMAT A30; COLUMN NETWORK_NAME FORMAT A30;" "SYSDBA"
            CHECKED_DBS["$DB_NAME_FULL"]=1
        fi
    done
}

status_pdbs() {
    if [ ${#VALID_SIDS[@]} -eq 0 ]; then echo "No database instances found to check."; return; fi
    for SID in "${VALID_SIDS[@]}"; do
        set_env_for_sid "$SID" || continue
        echo -e "---- ${CYAN}PDBs for SID: **$SID** (DB: ${INSTANCES["$SID",DB_NAME]})${NC} ----"

        CDB_CHECK=$(run_sql "SELECT cdb FROM v\$database;" "" "SYSDBA" | grep -i YES)
        if [ -n "$CDB_CHECK" ]; then
            run_sql "SELECT name, open_mode FROM v\$pdbs;" "COLUMN NAME FORMAT A30; COLUMN OPEN_MODE FORMAT A15;" "SYSDBA"
        else
            echo "Instance **$SID** is not a Container Database (CDB)."
        fi
    done
}

asm_diskgroups() {
    echo -e "${CYAN}Checking ASM status across the server...${NC}"
    if command -v asmcmd >/dev/null 2>&1; then
        echo -e "---- ${CYAN}ASM Diskgroup Usage (via asmcmd)${NC} ----"
        asmcmd lsdg
    else
        echo -e "---- ${CYAN}ASM Diskgroup Usage (via SQL - requires connection)${NC} ----"
        if [ ${#VALID_SIDS[@]} -ne 0 ]; then
            set_env_for_sid "${VALID_SIDS[0]}" || return
            run_sql "SELECT name, total_mb, free_mb, state FROM v\$asm_diskgroup;" "COLUMN TOTAL_MB FORMAT 999,999,999; COLUMN FREE_MB FORMAT 999,999,999;" "SYSDBA"
        else
            echo "ASM commands not found and no database instances running to check via SQL."
        fi
    fi
}

check_filesystem() {
    echo -e "---- ${CYAN}Filesystem Usage (df -h)${NC} ----"
    df -h
    echo ""
    echo -e "---- ${CYAN}Mounted Filesystem Health Check (Critical Only)${NC} ----"
    if ! mount | grep " / " >/dev/null; then
        echo -e "${RED}CRITICAL: Root filesystem (/) not mounted!${NC}"
    fi
    if ! mount | grep "/tmp" >/dev/null; then
        echo -e "${YELLOW}WARNING: /tmp not mounted or not found in mount output.${NC}"
    fi
}

check_cpu() {
    echo -e "---- ${CYAN}CPU Utilization (mpstat 1 5)${NC} ----"
    if command -v mpstat >/dev/null 2>&1; then
        mpstat 1 5
    else
        echo -e "${YELLOW}WARNING: mpstat command not found. Install sysstat package to use this check.${NC}"
    fi
}

rac_cluster_status() {
    echo -e "---- ${CYAN}RAC/Clusterware Status Check${NC} ----"

    GRID_HOME=$(grep -E "^\+ASM" ${ORATAB} | cut -d':' -f2 -s)

    if [ -n "$GRID_HOME" ] && [ -d "$GRID_HOME/bin" ]; then
        export PATH=$GRID_HOME/bin:$PATH
    fi

    if ! command -v crsctl >/dev/null 2>&1 && ! command -v oifcfg >/dev/null 2>&1; then
        echo -e "${RED}WARNING: Clusterware commands (crsctl/oifcfg) not found in \$PATH even after checking Grid Home.${NC}"
        echo "This host may not be a cluster member or the environment is not fully set."
        return
    fi

    if command -v oifcfg >/dev/null 2>&1; then
        echo -e "${BOLD}**Cluster Interconnect Status (oifcfg)**${NC}"
        oifcfg getif
    else
        echo -e "${YELLOW}WARNING: oifcfg command not found.${NC}"
    fi

    if command -v crsctl >/dev/null 2>&1; then
        echo -e "${BOLD}**Cluster Resource Status (crsctl)**${NC}"
        crsctl status resource -t
    else
        echo -e "${YELLOW}WARNING: crsctl command not available.${NC}"
    fi
}

restore_points() {
    if [ ${#VALID_SIDS[@]} -eq 0 ]; then echo "No database instances found to check."; return; fi
    for SID in "${VALID_SIDS[@]}"; do
        set_env_for_sid "$SID" || continue
        echo -e "---- ${CYAN}Restore Points for SID: **$SID** (DB: ${INSTANCES["$SID",DB_NAME]})${NC} ----"
        run_sql "SELECT name, scn, time, guaranteed_flashback_on FROM v\$restore_point;" "COLUMN NAME FORMAT A30; COLUMN TIME FORMAT A30;" "SYSDBA"
    done
}

# New function for RMAN backup status
backup_status() {
    if [ ${#VALID_SIDS[@]} -eq 0 ]; then echo "No database instances found to check."; return; fi
    for SID in "${VALID_SIDS[@]}"; do
        set_env_for_sid "$SID" || continue
        echo -e "---- ${CYAN}RMAN Backup Status (Last 24 Hours) for SID: **$SID**${NC} ----"
        # Query targets both FULL and INCREMENTAL backups completed since sysdate - 1
        local BACKUP_QUERY="
SELECT
    SESSION_KEY,
    INPUT_TYPE,
    STATUS,
    TO_CHAR(START_TIME,'YYYY-MM-DD HH24:MI:SS') AS START_TIME,
    TO_CHAR(END_TIME,'YYYY-MM-DD HH24:MI:SS') AS END_TIME,
    round(ELAPSED_SECONDS/60, 2) AS ELAPSED_MINUTES
FROM
    V\$RMAN_BACKUP_JOB_DETAILS
WHERE
    START_TIME >= SYSDATE - 1
    AND INPUT_TYPE IN ('DB INCR', 'DB FULL')
ORDER BY
    START_TIME DESC;
"
        local BACKUP_FORMATTING="
COLUMN INPUT_TYPE FORMAT A10
COLUMN STATUS FORMAT A10
COLUMN START_TIME FORMAT A20
COLUMN END_TIME FORMAT A20
COLUMN ELAPSED_MINUTES FORMAT 999.00
"
        run_sql "$BACKUP_QUERY" "$BACKUP_FORMATTING" "SYSDBA"
    done
}

# NEW FUNCTION: Data Guard Status and Lag Check
dataguard_status() {
    if [ ${#VALID_SIDS[@]} -eq 0 ]; then echo "No database instances found to check."; return; fi

    for SID in "${VALID_SIDS[@]}"; do
        set_env_for_sid "$SID" || continue
        echo -e "---- ${CYAN}Data Guard Status and Lag for SID: **$SID**${NC} ----"

        # Check if Data Guard is enabled (DB_ROLE <> PRIMARY/STANDBY implies single instance or no DG)
        local ROLE=$(run_sql "SELECT database_role FROM v\$database;" "" "SYSDBA" | grep -v DATABASE_ROLE | awk 'NF>0 {print $1}')

        if [ "$ROLE" == "PRIMARY" ] || [ "$ROLE" == "PHYSICAL STANDBY" ] || [ "$ROLE" == "LOGICAL STANDBY" ]; then
            echo -e "${GREEN}INFO: Data Guard Role Detected: **$ROLE**${NC}"

            # Query the required information
            local DG_QUERY="
SELECT
    NAME,
    DATABASE_ROLE,
    D.LOG_ARCHIVE_DEST_STATUS AS STATUS,
    C.APPLY_LAG,
    C.TRANSPORT_LAG
FROM
    V\$DATABASE D,
    (SELECT NAME, VALUE AS APPLY_LAG, NULL AS TRANSPORT_LAG FROM V\$DATAGUARD_STATS WHERE NAME = 'apply lag'
     UNION ALL
     SELECT NAME, NULL AS APPLY_LAG, VALUE AS TRANSPORT_LAG FROM V\$DATAGUARD_STATS WHERE NAME = 'transport lag') C
WHERE
    1=1;
"

            local DG_FORMATTING="
COLUMN NAME FORMAT A20
COLUMN DATABASE_ROLE FORMAT A15
COLUMN STATUS FORMAT A10
COLUMN APPLY_LAG FORMAT A20
COLUMN TRANSPORT_LAG FORMAT A20
"
            # Run the query using SYSDBA
            run_sql "$DG_QUERY" "$DG_FORMATTING" "SYSDBA"
        else
            echo -e "${YELLOW}WARNING: Database Role is **$ROLE**. Data Guard may not be enabled or configured.${NC}"
        fi
    done
}

############################################
# DBA Functions (Use DBA_USER/DBA_PASS@SERVICE_NAME)
############################################

# NEW CHECK: Check Profile Idle Time
check_profile_idle() {
    if [ -z "$CONNECT_STRING" ]; then echo "DB connection required. Please select a database service first."; return; fi
    echo -e "---- ${CYAN}Database Profiles IDLE_TIME Limits${NC} ----"
    run_sql "SELECT profile, resource_name, limit FROM dba_profiles WHERE resource_name ='IDLE_TIME';" "COLUMN PROFILE FORMAT A20; COLUMN RESOURCE_NAME FORMAT A20; COLUMN LIMIT FORMAT A15;" "DBA_USER"
}

# NEW CHECK: Check Triggers
check_triggers() {
    if [ -z "$CONNECT_STRING" ]; then echo "DB connection required. Please select a database service first."; return; fi
    echo -e "---- ${CYAN}Database Triggers (HDM, LOGON, INCON related)${NC} ----"
    run_sql "SELECT owner, trigger_name, trigger_type, triggering_event, status FROM dba_triggers WHERE trigger_name LIKE '%HDM%' OR trigger_name LIKE '%LOGON%' OR trigger_name LIKE '%INCON%' ORDER BY owner, trigger_name;" "COLUMN OWNER FORMAT A15; COLUMN TRIGGER_NAME FORMAT A30; COLUMN TRIGGER_TYPE FORMAT A15; COLUMN TRIGGERING_EVENT FORMAT A20; COLUMN STATUS FORMAT A10;" "DBA_USER"
}

# MOVED AND UPDATED: FRA Usage
fra_usage_dba() {
    if [ -z "$CONNECT_STRING" ]; then echo "DB connection required. Please select a database service first."; return; fi
    echo -e "---- ${CYAN}FRA Usage (Total/Used/Available in GB)${NC} ----"
    local FRA_QUERY="
SELECT
    ROUND(SUM(space_limit) / 1024 / 1024 / 1024, 2) AS \"Total Size (GB)\",
    ROUND(SUM(space_used) / 1024 / 1024 / 1024, 2) AS \"Used Space (GB)\",
    ROUND((SUM(space_limit) - SUM(space_used)) / 1024 / 1024 / 1024, 2) AS \"Available Space (GB)\"
FROM
    v\$recovery_file_dest;
"
    local FRA_FORMATTING="
COLUMN \"Total Size (GB)\" FORMAT 999,999.00
COLUMN \"Used Space (GB)\" FORMAT 999,999.00
COLUMN \"Available Space (GB)\" FORMAT 999,999.00
"
    run_sql "$FRA_QUERY" "$FRA_FORMATTING" "DBA_USER"
}

# NEW CHECK: DB Size
db_size() {
    if [ -z "$CONNECT_STRING" ]; then echo "DB connection required. Please select a database service first."; return; fi
    echo -e "---- ${CYAN}DB Size, Allocated vs Used (GB)${NC} ----"

    local DB_SIZE_QUERY_1="
SELECT SYSDATE DATED, A.HOST_NAME, A.INSTANCE_NAME, A.VERSION, C.TOTAL_ALLOCATED_GB, B.USED_GB, D.FREE_GB FROM V\$INSTANCE A,
(SELECT SUM(BYTES)/1024/1024/1024 USED_GB FROM DBA_SEGMENTS) B,
(SELECT SUM(BYTES)/1024/1024/1024 TOTAL_ALLOCATED_GB FROM DBA_DATA_FILES) C,
(SELECT SUM(BYTES)/1024/1024/1024 FREE_GB FROM DBA_FREE_SPACE) D;
"
    local DB_SIZE_FORMATTING_1="
COLUMN HOST_NAME FORMAT A20
COLUMN INSTANCE_NAME FORMAT A15
COLUMN VERSION FORMAT A15
COLUMN TOTAL_ALLOCATED_GB FORMAT 999,999.00
COLUMN USED_GB FORMAT 999,999.00
COLUMN FREE_GB FORMAT 999,999.00
"
    run_sql "$DB_SIZE_QUERY_1" "$DB_SIZE_FORMATTING_1" "DBA_USER"

    echo -e "\n${BOLD}--- Reserved vs Free Space ---${NC}"
}

# NEW CHECK: Tablespace Usage > 85%
tablespace_usage_high() {
    if [ -z "$CONNECT_STRING" ]; then echo "DB connection required. Please select a database service first."; return; fi
    echo -e "---- ${CYAN}Tablespaces with > 85% Usage (Check for AutoExtend)${NC} ----"

    local TS_USAGE_QUERY="
SELECT
    d.tablespace_name,
    d.status,
    ROUND(MAX(d.bytes) / (1024 * 1024 * 1024), 2) AS total_gb,
    ROUND(SUM(DECODE(f.free_gb, NULL, 0, f.free_gb)), 2) AS free_gb,
    ROUND(((MAX(d.bytes) - SUM(DECODE(f.free_gb, NULL, 0, f.free_gb))) / MAX(d.bytes)) * 100, 2) AS percent_used
FROM
    (SELECT tablespace_name, status, SUM(bytes) bytes FROM dba_data_files GROUP BY tablespace_name, status) d,
    (SELECT tablespace_name, ROUND(SUM(bytes) / (1024 * 1024 * 1024), 2) AS free_gb FROM dba_free_space GROUP BY tablespace_name) f
WHERE
    d.tablespace_name = f.tablespace_name(+)
    AND d.status = 'ONLINE'
HAVING
    ROUND(((MAX(d.bytes) - SUM(DECODE(f.free_gb, NULL, 0, f.free_gb))) / MAX(d.bytes)) * 100, 2) > 85
GROUP BY
    d.tablespace_name, d.status
ORDER BY
    percent_used DESC;
"
    local TS_USAGE_FORMATTING="
COLUMN TABLESPACE_NAME FORMAT A25
COLUMN STATUS FORMAT A10
COLUMN TOTAL_GB FORMAT 999.00
COLUMN FREE_GB FORMAT 999.00
COLUMN PERCENT_USED FORMAT 999.00
"
    run_sql "$TS_USAGE_QUERY" "$TS_USAGE_FORMATTING" "DBA_USER"
}

# NEW CHECK: SGA/PGA and Advisor Info
sga_pga_advisor() {
    if [ -z "$CONNECT_STRING" ]; then echo "DB connection required. Please select a database service first."; return; fi
    echo -e "---- ${CYAN}SGA/PGA Limits & SGA Target Advice${NC} ----"

    local ADVISOR_QUERY="
WITH
    MAX_PGA AS (
        SELECT ROUND(value/1024/1024,1) AS max_pga
        FROM v\$pgastat
        WHERE name = 'maximum PGA allocated'
    ),
    MGA_CURR AS (
        SELECT ROUND(value/1024/1024,1) AS mga_curr
        FROM v\$pgastat
        WHERE name = 'MGA allocated (under PGA)'
    ),
    MAX_UTIL AS (
        SELECT max_utilization AS max_util
        FROM v\$resource_limit
        WHERE resource_name = 'processes'
    ),
    SGA_TARGET_ADVICE AS (
        SELECT
            sga_size,
            sga_size_factor,
            estd_db_time_factor
        FROM
            v\$sga_target_advice
    )
SELECT
    a.max_pga AS \"Max PGA (MB)\",
    b.mga_curr AS \"Current MGA (MB)\",
    c.max_util AS \"Max # of processes\",
    ROUND(((a.max_pga - b.mga_curr) + (c.max_util * 5)) * 1.1, 1) AS \"New PGA_AGGREGATE_LIMIT (MB)\",
    sga.sga_size AS \"SGA Size (MB)\",
    sga.sga_size_factor AS \"SGA Size Factor\",
    sga.estd_db_time_factor AS \"Estimated DB Time Factor\"
FROM
    MAX_PGA a,
    MGA_CURR b,
    MAX_UTIL c,
    SGA_TARGET_ADVICE sga
WHERE 1 = 1
ORDER BY sga.sga_size_factor;
"
    local ADVISOR_FORMATTING="
COLUMN \"Max PGA (MB)\" FORMAT 999,999.0
COLUMN \"Current MGA (MB)\" FORMAT 999,999.0
COLUMN \"Max # of processes\" FORMAT 999,999
COLUMN \"New PGA_AGGREGATE_LIMIT (MB)\" FORMAT 999,999.0
COLUMN \"SGA Size (MB)\" FORMAT 999,999
COLUMN \"SGA Size Factor\" FORMAT 9.00
COLUMN \"Estimated DB Time Factor\" FORMAT 9.00
"
    run_sql "$ADVISOR_QUERY" "$ADVISOR_FORMATTING" "DBA_USER"
}

# EXISTING DBA CHECKS
long_running_sqls() {
    if [ ${#VALID_SIDS[@]} -eq 0 ]; then echo "No database instances found to check."; return; fi
    echo -e "---- ${CYAN}Long-running SQLs (Elapsed time > 300 sec)${NC} ----"
    run_sql "SELECT sql_id, substr(sql_text, 1, 60) AS sql_text_part, elapsed_time/1000000 AS elapsed_sec
             FROM v\$sql WHERE elapsed_time/1000000 > 300
             ORDER BY elapsed_sec DESC;" "COLUMN SQL_ID FORMAT A13; COLUMN ELAPSED_SEC FORMAT 999,999.00;" "DBA_USER"
}

sql_monitoring() {
    if [ ${#VALID_SIDS[@]} -eq 0 ]; then echo "No database instances found to check."; return; fi

    echo -e "---- ${CYAN}1. Active/Pending V\$SQL_MONITOR Status${NC} ----"
    # Original V$SQL_MONITOR check
    run_sql "SELECT sql_id, status, elapsed_time/1000000 AS elapsed_sec, module
             FROM v\$sql_monitor WHERE status IN ('EXECUTING', 'QUEUED');" "COLUMN SQL_ID FORMAT A13; COLUMN MODULE FORMAT A25;" "DBA_USER"

    echo -e "\n---- ${CYAN}2. Active Session & SQL Status ('Poor Man''s Script')${NC} ----"
    # New comprehensive monitoring script from the blog
    local POOR_MAN_QUERY="
SELECT
    x.inst_id,
    x.sid,
    x.username,
    x.sql_id,
    sqlarea.DISK_READS,
    sqlarea.BUFFER_GETS,
    x.event,
    x.status,
    x.BLOCKING_SESSION,
    x.machine,
    x.program,
    x.LAST_CALL_ET,
    ltrim(to_char(floor(x.LAST_CALL_ET/3600), '09')) || ':'
    || ltrim(to_char(floor(mod(x.LAST_CALL_ET, 3600)/60), '09')) || ':'
    || ltrim(to_char(mod(x.LAST_CALL_ET, 60), '09')) AS RUNNING_SINCE
FROM
    gv\$sqlarea sqlarea,
    gv\$session x
WHERE
    x.sql_hash_value = sqlarea.hash_value
    AND x.sql_address = sqlarea.address
    AND x.inst_id = sqlarea.inst_id
    AND x.status = 'ACTIVE'
    AND x.username IS NOT NULL
    AND sqlarea.sql_text NOT LIKE '%gv\$sqlarea sqlarea%' -- Exclude this script itself
ORDER BY
    RUNNING_SINCE DESC"

    local POOR_MAN_FORMATTING="
COLUMN DISK_READS FORMAT 999,999,999
COLUMN BUFFER_GETS FORMAT 999,999,999
COLUMN USERNAME FORMAT A10
COLUMN SQL_ID FORMAT A13
COLUMN EVENT FORMAT A20
COLUMN MACHINE FORMAT A20
COLUMN PROGRAM FORMAT A20
COLUMN BLOCKING_SESSION FORMAT 99999
COLUMN LAST_CALL_ET FORMAT 99999
COLUMN RUNNING_SINCE FORMAT A12
"
    run_sql "$POOR_MAN_QUERY" "$POOR_MAN_FORMATTING" "DBA_USER"
}

# DataPump Jobs
datapump_jobs() {
    if [ ${#VALID_SIDS[@]} -eq 0 ]; then echo "No database instances found to check."; return; fi
    echo -e "---- ${CYAN}DataPump Job Progress${NC} ----"
    run_sql "SELECT
    sl.sid,
    sl.serial#,
    sl.sofar,
    sl.totalwork,
    ROUND((sl.sofar/sl.totalwork)*100, 2) AS percent_complete,
    dp.owner_name,
    dp.state,
    dp.job_mode,
    sl.machine
FROM
    gv\$session_longops sl,
    gv\$datapump_job dp
WHERE
    sl.opname = dp.job_name
    AND sl.sofar != sl.totalwork
    AND sl.opname LIKE 'Data Pump%';" "COLUMN sid FORMAT 99999; COLUMN serial# FORMAT 99999; COLUMN sofar FORMAT 999999999; COLUMN totalwork FORMAT 999999999; COLUMN owner_name FORMAT A20; COLUMN state FORMAT A15; COLUMN job_mode FORMAT A15; COLUMN machine FORMAT A30; COLUMN percent_complete FORMAT 999.99;" "DBA_USER"
}

# Sessions per Machine
sessions_per_machine() {
    if [ ${#VALID_SIDS[@]} -eq 0 ]; then echo "No database instances found to check."; return; fi
    echo -e "---- ${CYAN}Sessions per Machine (Active/Inactive)${NC} ----"
    run_sql "SELECT
    inst_id,
    machine AS machine_name,
    SUM(CASE WHEN status = 'ACTIVE' THEN 1 ELSE 0 END) AS active_sessions,
    SUM(CASE WHEN status = 'INACTIVE' THEN 1 ELSE 0 END) AS inactive_sessions,
    COUNT(sid) AS total_sessions
FROM
    gv\$session
GROUP BY
    inst_id, machine
ORDER BY
    inst_id, total_sessions DESC;" "COLUMN machine_name FORMAT A30; COLUMN inst_id FORMAT 99; COLUMN active_sessions FORMAT 9999; COLUMN inactive_sessions FORMAT 9999; COLUMN total_sessions FORMAT 9999;" "DBA_USER"
}


# Blocking Sessions (Main Summary - Query 1 & 2 combined)
blocking_sessions() {
    if [ ${#VALID_SIDS[@]} -eq 0 ]; then echo "No database instances found to check."; return; fi
    echo -e "---- ${CYAN}Blocking Sessions and Wait Time (Query 1 & 2)${NC} ----"

    # Find Blocking and Blocked Sessions (Query 1)
    echo -e "\n${BOLD}--- 1. Blocking/Blocked Session Summary ---${NC}"
    run_sql "SELECT
    SESLCK.USERNAME || '@INST' || SESLCK.INST_ID || ' (SID=' || SESLCK.SID || ' SERIAL=' || SESLCK.SERIAL# || ')' AS blocker_info,
    SEWT.USERNAME || '@INST' || SEWT.INST_ID || ' (SID=' || SEWT.SID || ' SERIAL=' || SEWT.SERIAL# || ')' AS blocked_info,
    SEWT.EVENT AS wait_event
FROM
    GV\$LOCK LCKR
JOIN
    GV\$LOCK WT ON LCKR.ID1 = WT.ID1 AND LCKR.ID2 = WT.ID2
JOIN
    GV\$SESSION SESLCK ON LCKR.SID = SESLCK.SID AND LCKR.INST_ID = SESLCK.INST_ID
JOIN
    GV\$SESSION SEWT ON WT.SID = SEWT.SID AND WT.INST_ID = SEWT.INST_ID
WHERE
    LCKR.BLOCK = 1
    AND WT.REQUEST > 0
ORDER BY
    SEWT.SECONDS_IN_WAIT DESC;" "COLUMN blocker_info FORMAT A55; COLUMN blocked_info FORMAT A55; COLUMN wait_event FORMAT A30;" "DBA_USER"

    # Find Blocking SQL and Wait Details (Query 2)
    echo -e "\n${BOLD}--- 2. Blocking Session Details and Wait Time ---${NC}"
    run_sql "SELECT
    BLOCKED.INST_ID,
    BLOCKED.SID AS blocked_session,
    BLOCKED.SECONDS_IN_WAIT / 60 AS wait_time_minutes,
    BLOCKER.SID AS blocking_session,
    BLOCKER.SQL_ID AS blocker_sql_id,
    BLOCKER.USERNAME AS blocker_username,
    BLOCKER.MACHINE AS blocker_machine
FROM
    GV\$SESSION BLOCKED
JOIN
    GV\$SESSION BLOCKER ON BLOCKED.BLOCKING_SESSION = BLOCKER.SID AND BLOCKED.BLOCKING_INSTANCE = BLOCKER.INST_ID
WHERE
    BLOCKED.BLOCKING_SESSION IS NOT NULL
ORDER BY
    wait_time_minutes DESC;" "COLUMN blocking_session FORMAT 99999; COLUMN blocked_session FORMAT 99999; COLUMN wait_time_minutes FORMAT 99999.00; COLUMN blocker_sql_id FORMAT A13; COLUMN blocker_username FORMAT A20; COLUMN blocker_machine FORMAT A25;" "DBA_USER"

}

# Find Blocking SQL Text (Manual Check - Query 3)
find_blocking_sql_text() {
    if [ ${#VALID_SIDS[@]} -eq 0 ]; then echo "No database instances found to check."; return; fi
    echo -e "---- ${CYAN}Find Blocking SQL Text (Manual Input Required)${NC} ----"
    echo -e "${YELLOW}NOTE: This query requires INST_ID and SQL_ID from the previous check.${NC}"

    read -p "Enter Blocking INST_ID: " blocker_inst_id
    read -p "Enter Blocking SQL_ID: " blocker_sql_id

    if [ -z "$blocker_inst_id" ] || [ -z "$blocker_sql_id" ]; then
        echo -e "${RED}INST_ID or SQL_ID cannot be empty. Aborting.${NC}"
        return
    fi

    # Use variables in the SQL query
    run_sql "
    SET LONG 2000
    SELECT
        sql_fulltext
    FROM
        gv\$sql
    WHERE
        inst_id = $blocker_inst_id
        AND sql_id = '$blocker_sql_id';" "COLUMN sql_fulltext FORMAT A150 WORD_WRAP;" "DBA_USER"
}

# Helper function to dynamically discover the APP_ADMIN schema name
get_app_schema() {
    local CONN_STRING_FULL="${DBA_USER}/${DBA_PASS}@${CONNECT_STRING}"

    # Use sqlplus to query the database for the schema name
    local SCHEMA_NAME=$(sqlplus -s "$CONN_STRING_FULL" <<EOF
SET HEAD OFF FEEDBACK OFF PAGESIZE 0
SELECT username FROM dba_users WHERE username LIKE '%APP_ADMIN%';
EXIT;
EOF
)
    # Clean up whitespace and return the found schema name
    echo "$SCHEMA_NAME" | tr -d ' '
}

# Application LRQ
invalid_objects() {
    if [ ${#VALID_SIDS[@]} -eq 0 ]; then echo "No database instances found to check."; return; fi
    echo -e "---- ${CYAN}Invalid Objects${NC} ----"
    run_sql "SELECT owner, object_name, object_type, subobject_name, status FROM dba_objects WHERE status='INVALID';" "COLUMN OWNER FORMAT A15; COLUMN OBJECT_NAME FORMAT A30; COLUMN OBJECT_TYPE FORMAT A15; COLUMN SUBOBJECT_NAME FORMAT A20;" "DBA_USER"
}
unusable_indexes() {
    if [ ${#VALID_SIDS[@]} -eq 0 ]; then echo "No database instances found to check."; return; fi
    echo -e "---- ${CYAN}Unusable Indexes${NC} ----"
    run_sql "SELECT owner, index_name, tablespace_name, status FROM dba_indexes WHERE status='UNUSABLE';" "COLUMN OWNER FORMAT A15; COLUMN INDEX_NAME FORMAT A30; COLUMN TABLESPACE_NAME FORMAT A15;" "DBA_USER"
}
failed_jobs() {
    if [ ${#VALID_SIDS[@]} -eq 0 ]; then echo "No database instances found to check."; return; fi
    echo -e "---- ${CYAN}Failed Scheduler Jobs (Past 24H)${NC} ----"
    run_sql "SELECT log_date, owner, job_name, status, error# FROM dba_scheduler_job_run_details WHERE log_date > sysdate-1 AND status <> 'SUCCEEDED' ORDER BY log_date DESC;" "COLUMN LOG_DATE FORMAT A20; COLUMN OWNER FORMAT A15; COLUMN JOB_NAME FORMAT A25; COLUMN ERROR# FORMAT 99999;" "DBA_USER"
}
############################################
# HTH Upgrade Check Function (New)
############################################
common_db_chk_menu() {
    if [ -z "$CONNECT_STRING" ]; then echo "DB connection required. Please select a database service first."; return; fi

    # Dynamically retrieve the application schema name (assumes get_app_schema is defined elsewhere)
    local APP_SCHEMA=$(get_app_schema)

    if [ -z "$APP_SCHEMA" ]; then
        echo -e "${RED}ERROR: Could not find an application schema matching '%APP_ADMIN%'. Aborting check.${NC}"
        return
    fi

    echo -e "---- ${CYAN}Checking for BINARY_DOUBLE columns (Schema: $APP_SCHEMA, PDB: $CONNECT_STRING)${NC} ----"

    # 1. Define the pre-SQL commands to set the container and schema
    local PRE_SQL_COMMANDS="
ALTER SESSION SET CONTAINER=$CONNECT_STRING;
ALTER SESSION SET CURRENT_SCHEMA=$APP_SCHEMA;
"
    # 2. Define the Query
    # The expected result is 'no rows selected', meaning no BINARY_DOUBLE columns were found.
    local BINARY_DOUBLE_QUERY="
keep your routine work
"
    local FORMATTING="
COLUMN TABLE_NAME FORMAT A40
COLUMN COLUMN_NAME FORMAT A30
COLUMN DATA_TYPE FORMAT A20
"
    # Execute SQL using DBA_USER credentials, passing the PRE_SQL_COMMANDS
    run_sql "$BINARY_DOUBLE_QUERY" "$FORMATTING" "DBA_USER" "$PRE_SQL_COMMANDS"
    echo -e "\n${GREEN}Check complete. 'No rows selected' is the expected, healthy result.${NC}"
}
# Application Get Form Name
get_form_name() {
    # Check if we have database instances to connect to (assuming VALID_SIDS is globally available)
    if [ ${#VALID_SIDS[@]} -eq 0 ]; then
        echo "No database instances found to check."
        return
    fi

    echo -e "---- ${CYAN}AR Form Name Lookup by Schema ID (T-Table ID)${NC} ----"

    # 1. Dynamically get the AR application schema name (e.g., ARADMIN)
    local APP_SCHEMA=$(get_app_schema)

    if [ -z "$APP_SCHEMA" ]; then
        echo -e "${RED}ERROR: Could not find an application schema matching '%APP_ADMIN%'. Aborting lookup.${NC}"
        return
    fi

    echo -e "${YELLOW}INFO: Dynamically set current_schema to: **$APP_SCHEMA**${NC}"

    # 2. Prompt for the Schema ID (T-Table ID)
    read -p "Enter the TABLE NAME ID (e.g., DEEDS775) to find the Form Name: "

    # Basic input validation
    if [ -z "$SCHEMA_ID" ]; then
        echo -e "${RED}ERROR: Schema ID cannot be empty. Aborting.${NC}"
        return
    fi

    # 3. Construct the query
    # ARSCHEMA.SCHEMAID is the internal T-table number (e.g., 775)
    # The user enters 'T775', so we need to extract the number.
    # We use LIKE for a robust match just in case.
    local NUMERIC_ID=$(echo $SCHEMA_ID | tr -d '[:alpha:]')

    local FORM_NAME_QUERY="
keep your routine application work
"

    local FORM_NAME_FORMATTING="
COLUMN SCHEMAID FORMAT 99999
COLUMN NAME FORMAT A50 WORD_WRAP
"

   # 4. Run the query using the DBA_USER credentials
    run_sql "$FORM_NAME_QUERY" "$FORM_NAME_FORMATTING" "DBA_USER"
}
############################################
# Menus
############################################
wait_for_return() {
    echo ""
    read -n 1 -s -p "Press ${BOLD}any key${NC} to return to the previous menu..."
    echo ""
}

sysdba_menu() {
    while true; do
        clear
        echo -e "======================================"
        echo -e " ${BOLD}${GREEN}💻 SYSDBA Health Checks (Server/Cluster)${NC}"
        echo -e "======================================"

        # Display menu options horizontally
        echo -e " ${YELLOW}1.${NC} DB status ${CYAN}|${NC} ${YELLOW}2.${NC} RAC Services ${CYAN}|${NC} ${YELLOW}3.${NC} PDBs ${CYAN}|${NC} ${YELLOW}4.${NC} ASM DGs ${CYAN}|${NC} ${YELLOW}5.${NC} Filesystem ${CYAN}|${NC} ${YELLOW}6.${NC} CPU ${CYAN}|${NC} ${YELLOW}7.${NC} RAC status ${CYAN}|${NC} ${YELLOW}8.${NC} Restore points ${CYAN}|${NC} ${YELLOW}9.${NC} Backup status ${CYAN}|${NC} ${YELLOW}10.${NC} Data Guard Status ${CYAN}|${NC} ${RED}11.${NC} Return"
        echo -e "---"

        read -p "Enter choice [1-11]: " choice
        echo ""
        case $choice in
            1) status_database ; wait_for_return ;;
            2) rac_services_status ; wait_for_return ;;
            3) status_pdbs ; wait_for_return ;;
            4) asm_diskgroups ; wait_for_return ;;
            5) check_filesystem ; wait_for_return ;;
            6) check_cpu ; wait_for_return ;;
            7) rac_cluster_status ; wait_for_return ;;
            8) restore_points ; wait_for_return ;;
            9) backup_status ; wait_for_return ;;
            10) dataguard_status ; wait_for_return ;;
            11) break ;;
            *) echo -e "${RED}Invalid choice.${NC}" ; wait_for_return ;;
        esac
    done
}

dba_menu() {
    # 1. Select CDB/PDB and set CONNECT_STRING to the service name
    select_and_set_pdb || return

    while true; do
        clear
        echo -e "======================================"
        echo -e " ${BOLD}${GREEN}📊 DBA Health Checks (Connection: ${DBA_USER}@${CONNECT_STRING})${NC}"
        echo -e "======================================"

        # Display menu options horizontally
        echo -e " ${YELLOW}1.${NC} Long SQLs ${CYAN}|${NC} ${YELLOW}2.${NC} Live SQL Mon ${CYAN}|${NC} ${YELLOW}3.${NC} Blocking Sum ${CYAN}|${NC} ${YELLOW}4.${NC} Blocking SQL ${CYAN}|${NC} ${YELLOW}5.${NC} Invalid objs ${CYAN}|${NC} ${YELLOW}6.${NC} Unusable idxs ${CYAN}|${NC} ${YELLOW}7.${NC} Failed jobs ${CYAN}|${NC} ${YELLOW}8.${NC} DataPump Status  ${CYAN}|${NC} ${YELLOW}9.${NC} Sessions/Host ${CYAN}|${NC} ${YELLOW}10.${NC} App LRQ (>4m) ${CYAN}|${NC} ${YELLOW}11.${NC} DB Size ${CYAN}|${NC} ${YELLOW}12.${NC} TS Usage (>85%) ${CYAN}|${NC} ${YELLOW}13.${NC} FRA Usage ${CYAN}|${NC} ${YELLOW}14.${NC} SGA/PGA Adv ${CYAN}|${NC} ${YELLOW}15.${NC} Profile Idle ${CYAN}|${NC} ${YELLOW}16.${NC} Triggers ${CYAN}|${NC} ${RED}17.${NC} Return"
        echo -e "---"

        read -p "Enter choice [1-17]: " choice
        echo ""
        case $choice in
            1) long_running_sqls ; wait_for_return ;;
            2) sql_monitoring ; wait_for_return ;;
            3) blocking_sessions ; wait_for_return ;;
            4) find_blocking_sql_text ; wait_for_return ;;
            5) invalid_objects ; wait_for_return ;;
            6) unusable_indexes ; wait_for_return ;;
            7) failed_jobs ; wait_for_return ;;
            8) datapump_jobs ; wait_for_return ;;
            9) sessions_per_machine ; wait_for_return ;;
            10) db_size ; wait_for_return ;;
            11) tablespace_usage_high ; wait_for_return ;;
            12) fra_usage_dba ; wait_for_return ;;
            13) sga_pga_advisor ; wait_for_return ;;
            14) check_profile_idle ; wait_for_return ;;
            15) check_triggers ; wait_for_return ;;
            16) CONNECT_STRING=""; break ;; # Reset connection string and exit
            *) echo -e "${RED}Invalid choice.${NC}" ; wait_for_return ;;
        esac
    done
}

appdba_menu() {
        # 1. Select CDB/PDB and set CONNECT_STRING to the service name
    select_and_set_pdb || return

    while true; do
        clear
        echo -e "======================================"
        echo -e " ${BOLD}${GREEN}📊 DBA Application Checks (Connection: ${DBA_USER}@${CONNECT_STRING})${NC}"
        echo -e "======================================"

        # Display menu options horizontally
       echo -e " 1.${NC} App LRQ (>4m) ${CYAN}|${NC} ${YELLOW}2.${NC} Profile Idle ${CYAN}|${NC} ${YELLOW}3.${NC} Triggers ${CYAN}|${YELLOW}4.${NC} Get Form Name ${CYAN}|${YELLOW}5.${NC} HTH Upgrade Checks ${CYAN}|${NC} ${RED}6.${NC} Return"
        echo -e "---"

        read -p "Enter choice [1-7]: " choice
        echo ""
        case $choice in
            1) check_profile_idle ; wait_for_return ;;
            2) check_triggers ; wait_for_return ;;
            3) get_form_name ; wait_for_return ;;
            4) common_db_chk_menu ; wait_for_return ;;
            5) CONNECT_STRING=""; break ;; # Reset connection string and exit
            *) echo -e "${RED}Invalid choice.${NC}" ; wait_for_return ;;
        esac
    done
}

############################################
# Main loop
############################################
while true; do
    clear
    echo -e "${GREEN}=================================================================${NC}"
    echo -e "${GREEN}|                                                                 |${NC}"
    echo -e "${GREEN}#################################################################${NC}"
    echo -e "${BOLD}${GREEN}#   🩺 Oracle DBA Buddy Utility                          #${NC}"
    echo -e "${BOLD}${GREEN}#   Author : Sandeep Reddy Narani                        #${NC}"
    echo -e "${GREEN}#################################################################${NC}"
    echo -e "${GREEN}|                                                               |${NC}"
    echo -e "${GREEN}=================================================================${NC}"
    # Display main menu options horizontally
    echo -e " ${YELLOW}1.${NC} SYSDBA Mode ${CYAN}|${NC} ${YELLOW}2.${NC} DBA Mode (${BOLD}${DBA_USER} connection${NC}) ${CYAN}|${YELLOW}3.${NC} APPDBA Mode ${CYAN}|${NC} ${RED}4.${NC} Exit"
    echo -e "---"

    read -p "Enter your choice [1-4]: " mode

    case $mode in
        1) sysdba_menu ;;
        2) dba_menu ;;
        3) appdba_menu ;;
        4) echo -e "${GREEN}Exiting...${NC}" ; break ;;
        *) echo -e "${RED}Invalid choice.${NC}" ; wait_for_return ;;
    esac
done
