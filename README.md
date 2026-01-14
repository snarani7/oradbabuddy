# 🩺 Oracle DBA Buddy Utility

**A powerful, interactive Oracle Database health check and management tool that revolutionizes how DBAs connect to PDBs and perform critical database checks.**

---

## 🌟 Overview
## oradbabuddy
**Oracle DBA Buddy** is an advanced, menu-driven bash utility designed to streamline Oracle database administration tasks. It eliminates the complexity of manually connecting to Container Databases (CDBs) and Pluggable Databases (PDBs), providing DBAs with instant access to database health checks through an intuitive, color-coded interface.

### 🚀 Key Benefits

- **⚡ Lightning-Fast PDB Connection**: Connect to any PDB or CDB in seconds with an interactive menu - no more remembering service names or connection strings
- **🎯 One-Click Health Checks**: Access 30+ pre-configured database health checks with a single command
- **🔍 Intelligent Discovery**: Automatically discovers all running Oracle instances and their associated PDBs
- **🎨 User-Friendly Interface**: Beautiful, color-coded menus that make navigation effortless
- **🔄 Multi-Mode Operation**: Three specialized modes (SYSDBA, DBA, APPDBA) for different administrative needs
- **📊 Comprehensive Monitoring**: From basic status checks to advanced performance analysis - everything in one place

---

## ✨ Features

### 🔌 **Revolutionary PDB Connection System**

The script's most powerful feature is its **intelligent PDB/CDB selection system**:

- **Automatic Discovery**: Scans running Oracle instances and automatically discovers all available PDBs
- **Unified Menu**: View all CDBs and PDBs in a single, organized list
- **Smart Environment Setup**: Automatically configures `ORACLE_SID`, `ORACLE_HOME`, and connection strings
- **No Manual Configuration**: No need to manually set environment variables or remember service names
- **RAC-Aware**: Intelligently handles RAC instances and Data Guard configurations

### 📋 **Three Operational Modes**

#### 1. **SYSDBA Mode** 💻
Server and cluster-level health checks that don't require database connections:
- Database status and open mode
- RAC services status (via `srvctl` or SQL fallback)
- PDB status across all containers
- ASM diskgroup usage
- Filesystem health checks
- CPU utilization monitoring
- RAC/Clusterware status
- Restore points
- RMAN backup status (last 24 hours)
- Data Guard status and lag monitoring

#### 2. **DBA Mode** 📊
Comprehensive database health checks using DBA credentials:
- **Performance Monitoring**:
  - Long-running SQL queries (>300 seconds)
  - Real-time SQL monitoring (V$SQL_MONITOR)
  - Active session monitoring with "Poor Man's Script"
  - Blocking sessions analysis
  - Blocking SQL text lookup
- **Database Health**:
  - Invalid objects detection
  - Unusable indexes identification
  - Failed scheduler jobs (past 24 hours)
  - DataPump job progress
  - Sessions per machine/host
- **Storage Management**:
  - Database size (allocated vs used)
  - Tablespace usage (>85% threshold)
  - FRA (Flash Recovery Area) usage
- **Resource Planning**:
  - SGA/PGA limits and advisor recommendations
  - Profile idle time limits
  - Database triggers (HDM, LOGON, INCON related)

#### 3. **APPDBA Mode** 🎯
Application-specific database checks:
- Application-specific long-running queries
- Profile idle time configuration
- Database triggers monitoring
- Form name lookup by schema ID
- HTH upgrade compatibility checks

### 🛠️ **Advanced Capabilities**

- **Smart Instance Matching**: Handles RAC instances, Data Guard, and complex naming conventions
- **Connection Validation**: Pre-validates connections before executing queries
- **Error Handling**: Graceful error handling with informative messages
- **Color-Coded Output**: Easy-to-read output with color-coded status indicators
- **Formatted SQL Results**: Professional, column-aligned query results
- **Environment Variable Support**: Secure password management via environment variables

---

## 📦 Installation

### Prerequisites

- Oracle Database installed and running
- Bash shell (version 4.0+)
- Oracle client tools (`sqlplus`, `srvctl` for RAC)
- Access to `/etc/oratab` or `/var/opt/oracle/oratab`
- Appropriate Oracle user permissions (SYSDBA for mode 1, DBA user for modes 2 & 3)

### Setup Steps

1. **Clone or download the script**:
   ```bash
   git clone <repository-url>
   cd oradbabuddy
   ```

2. **Make the script executable**:
   ```bash
   chmod +x oradbabuddy.sh
   ```

3. **Configure DBA credentials** (for DBA and APPDBA modes):
   
   Edit the script and set your DBA user (or use environment variables):
   ```bash
   # Option 1: Set in script (line 25)
   DBA_USER="your_dba_user"
   
   # Option 2: Use environment variable (recommended for security)
   export DBA_PASS="your_dba_password"
   ```

4. **Run the script**:
   ```bash
   ./oradbabuddy.sh
   ```

---

## 🎮 Usage

### Quick Start

Simply run the script and navigate through the intuitive menus:

```bash
./oradbabuddy.sh
```

### Main Menu

Upon execution, you'll see the main menu:

```
=================================================================
|                                                                 |
#################################################################
#   🩺 Oracle DBA Buddy Utility                          #
#   Author : Sandeep Reddy Narani                        #
#################################################################
|                                                               |
=================================================================
 1. SYSDBA Mode | 2. DBA Mode (dbadeeds connection) | 3. APPDBA Mode | 4. Exit
---
Enter your choice [1-4]:
```

### PDB Connection Workflow (DBA/APPDBA Modes)

When you select **DBA Mode** or **APPDBA Mode**, the script will:

1. **Automatically discover** all running Oracle instances
2. **Query each CDB** to find available PDBs
3. **Display a unified menu** showing:
   - All CDB root containers
   - All PDBs within each CDB
   - Instance information for each entry

Example PDB selection menu:
```
======================================
 PDB Selection for DBA Checks
======================================
Select Database Service to connect to:
 1. PRODDB - CDB (Root) (Instance: PRODDB1)
 2. PDB1 - PDB (Instance: PRODDB1)
 3. PDB2 - PDB (Instance: PRODDB1)
 4. TESTDB - CDB (Root) (Instance: TESTDB1)
 5. TESTPDB - PDB (Instance: TESTDB1)

Enter number for database service:
```

4. **Automatically configure** the connection:
   - Sets `ORACLE_SID` to the appropriate instance
   - Sets `ORACLE_HOME` from oratab
   - Configures `CONNECT_STRING` to the selected service name
   - Validates the connection before proceeding

5. **Present the health check menu** for the selected database

### Example Workflow

```bash
# 1. Start the utility
./oradbabuddy.sh

# 2. Select "2. DBA Mode"
# 3. Choose PDB from the list (e.g., "2. PDB1 - PDB")
# 4. Select health check (e.g., "1. Long SQLs")
# 5. View results instantly
# 6. Press any key to return to menu
```

---

## 🔧 Configuration

### Environment Variables

The script supports environment variables for secure credential management:

```bash
export DBA_PASS="your_secure_password"
```

### Customization

You can customize the following in the script:

- **DBA User** (line 25): Change `DBA_USER` to your DBA username
- **Color Schemes**: Modify ANSI color codes (lines 11-18) for custom styling
- **Query Thresholds**: Adjust time limits and thresholds in individual functions

---

## 📊 Available Health Checks

### SYSDBA Mode Checks

| # | Check | Description |
|---|-------|-------------|
| 1 | DB Status | Database name, open mode, and role |
| 2 | RAC Services | RAC service status via srvctl |
| 3 | PDBs | List all PDBs and their open modes |
| 4 | ASM Diskgroups | ASM diskgroup usage and status |
| 5 | Filesystem | Disk space and mount health |
| 6 | CPU | CPU utilization (mpstat) |
| 7 | RAC Status | Clusterware and interconnect status |
| 8 | Restore Points | Flashback restore points |
| 9 | Backup Status | RMAN backup status (last 24h) |
| 10 | Data Guard | Data Guard status and lag |

### DBA Mode Checks

| # | Check | Description |
|---|-------|-------------|
| 1 | Long SQLs | Queries running >300 seconds |
| 2 | Live SQL Mon | Real-time SQL monitoring |
| 3 | Blocking Sum | Blocking session summary |
| 4 | Blocking SQL | Find blocking SQL text |
| 5 | Invalid Objects | List invalid database objects |
| 6 | Unusable Indexes | Identify unusable indexes |
| 7 | Failed Jobs | Failed scheduler jobs (24h) |
| 8 | DataPump Status | DataPump job progress |
| 9 | Sessions/Host | Session distribution by host |
| 10 | DB Size | Database size and space usage |
| 11 | TS Usage (>85%) | Tablespaces over 85% full |
| 12 | FRA Usage | Flash Recovery Area usage |
| 13 | SGA/PGA Adv | Memory advisor recommendations |
| 14 | Profile Idle | Profile idle time limits |
| 15 | Triggers | Database triggers status |

### APPDBA Mode Checks

| # | Check | Description |
|---|-------|-------------|
| 1 | Profile Idle | Application profile settings |
| 2 | Triggers | Application-related triggers |
| 3 | Get Form Name | Lookup form names by schema ID |
| 4 | HTH Upgrade | HTH upgrade compatibility checks |

---

## 🎯 Use Cases

### Scenario 1: Quick PDB Health Check
**Problem**: Need to check tablespace usage in a specific PDB, but don't remember the service name.

**Solution**: 
1. Run `oradbabuddy.sh`
2. Select DBA Mode
3. Choose PDB from menu
4. Select "TS Usage (>85%)"
5. Done in 30 seconds!

### Scenario 2: Performance Investigation
**Problem**: Database is slow, need to identify blocking sessions and long-running queries.

**Solution**:
1. Run `oradbabuddy.sh`
2. Select DBA Mode → Choose PDB
3. Check "Long SQLs" for queries >300s
4. Check "Blocking Sum" for blocking sessions
5. Use "Blocking SQL" to get SQL text
6. All information in one place!

### Scenario 3: RAC Environment Monitoring
**Problem**: Need to check RAC services and cluster status across multiple nodes.

**Solution**:
1. Run `oradbabuddy.sh`
2. Select SYSDBA Mode
3. Check "RAC Services" for service status
4. Check "RAC Status" for clusterware health
5. Comprehensive RAC overview!

---

## 🔒 Security Features

- **Password Protection**: Supports environment variables for password storage
- **Connection Validation**: Pre-validates connections before executing queries
- **Error Handling**: Graceful error messages without exposing sensitive information
- **Permission Checks**: Validates Oracle user permissions before operations

---

## 🐛 Troubleshooting

### Issue: "oratab file not found"
**Solution**: Ensure Oracle is installed and oratab exists at `/etc/oratab` or `/var/opt/oracle/oratab`

### Issue: "No running Oracle instances found"
**Solution**: Verify Oracle instances are running: `ps -ef | grep ora_pmon`

### Issue: "Could not connect as DBA_USER"
**Solution**: 
- Verify DBA credentials are correct
- Check listener is running
- Ensure service name is correct
- Verify user has DBA privileges

### Issue: "srvctl command not found"
**Solution**: This is expected for non-RAC environments. The script will fall back to SQL queries.

---

## 📝 Technical Details

### Architecture

- **Instance Discovery**: Uses `ps -ef | grep ora_pmon` to find running instances
- **PDB Discovery**: Queries `V$PDBS` via SYSDBA connection
- **Environment Management**: Dynamically sets Oracle environment per instance
- **Connection Management**: Maintains separate connection strings for SYSDBA and DBA modes

### Supported Oracle Versions

- Oracle Database 12c and above (PDB support)
- Oracle Database 11g (limited PDB features)
- RAC and Data Guard configurations

### Platform Support

- Linux (primary platform)
- Unix variants (with bash 4.0+)

---

## 🤝 Contributing

Contributions are welcome! Please feel free to submit pull requests or open issues for:
- New health check functions
- Bug fixes
- Performance improvements
- Documentation enhancements

---

## 📄 License

This utility is provided as-is for Oracle database administration purposes.

---

## 👤 Author

**Sandeep Reddy Narani**  
*Oracle DBA & Database Administrator*

---

## 🙏 Acknowledgments

Built with the goal of making Oracle database administration faster, easier, and more efficient for DBAs worldwide.

---

## 📞 Support

For issues, questions, or feature requests, please open an issue in the repository.

---

**⭐ If this tool helps you, please consider giving it a star! ⭐**

---

*Last Updated: December 2025*
