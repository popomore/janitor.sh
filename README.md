# Janitor.sh

This is an intelligent temporary file cleanup script for Linux systems that can automatically clean temporary files based on disk usage.

## Features

- ✅ Trigger cleanup based on configured disk threshold
- ✅ Support target threshold, stop cleanup when target is reached
- ✅ Configurable file retention duration
- ✅ Support batch deletion control
- ✅ Configurable multiple directories with priority processing
- ✅ Detailed logging output
- ✅ Dry run mode
- ✅ Complete test suite

## File Description

- `janitor.sh` - Main cleanup script
- `janitor.conf.template` - Configuration file template
- `test/test_janitor.sh` - Test tool
- `test/test_janitor.conf` - Test configuration file
- `test/run_docker_test.sh` - Docker test runner script
- `test/Dockerfile.test` - Docker test image

## Configuration Parameters

### Configuration File Format

The script looks for configuration in the following order:
1. `/etc/janitor.conf` (default)
2. Built-in default values

```bash
# Trigger threshold: Start cleanup when disk usage exceeds this percentage
TRIGGER_THRESHOLD=90

# Target threshold: Stop cleanup when disk usage reaches this percentage
TARGET_THRESHOLD=50

# File retention time (hours): Files modified within this time will not be deleted
RETENTION_HOURS=24

# Batch size: Maximum number of files to delete per directory scan
BATCH_SIZE=100

# Temporary directories list: Comma separated, ordered by priority (first has highest priority)
TEMP_DIRS="/tmp,/var/tmp,/var/log,/var/cache"
```

### Configuration Description

- **TRIGGER_THRESHOLD**: Disk usage threshold percentage to trigger cleanup
- **TARGET_THRESHOLD**: Target disk usage percentage to stop cleanup
- **RETENTION_HOURS**: File retention time in hours
- **BATCH_SIZE**: Maximum number of files to process per round
- **TEMP_DIRS**: List of directories to clean, comma separated

## Usage

### Basic Usage

```bash
# Run with default configuration
./janitor.sh

# Use specified configuration file
./janitor.sh -c /path/to/janitor.conf

# Dry run mode (don't actually delete files)
./janitor.sh -d -v

# Show help
./janitor.sh -h
```

### Command Line Options

- `-c, --config FILE` - Specify configuration file path
- `-d, --dry-run` - Dry run mode, don't actually delete files
- `-v, --verbose` - Verbose output mode
- `-h, --help` - Show help information

## Execution Flow

1. **Load Configuration**: Read configuration file and validate parameters
2. **Check Disk Usage**: Get current disk usage
3. **Determine Cleanup Need**: Compare current usage with trigger threshold
4. **Traverse Directories**: Process directories in configured priority order
5. **File Scanning**: Find files that meet criteria in each directory
6. **Batch Deletion**: Sort by modification time and delete oldest files
7. **Threshold Check**: Check if target threshold is reached after each deletion round
8. **Complete Cleanup**: Output cleanup results and final disk usage

## Testing

### Testing with Docker

We provide a complete Docker testing environment to safely test script functionality.

#### Quick Testing

```bash
# Run complete test
./test/run_docker_test.sh -t

# Run dry run mode test
./test/run_docker_test.sh -d

# Start interactive container for manual testing
./test/run_docker_test.sh -i
```

#### Detailed Testing Steps

1. **Build test image**:
   ```bash
   ./test/run_docker_test.sh -b
   ```

2. **Run complete test**:
   ```bash
   ./test/run_docker_test.sh -t
   ```

3. **Clean Docker resources**:
   ```bash
   ./test/run_docker_test.sh -c
   ```

### Manual Testing

If you want to test in local environment:

```bash
# Create test environment
./test/test_janitor.sh -s

# Run dry run test
./test/test_janitor.sh -d

# Run complete test
./test/test_janitor.sh -a

# Verify results
./test/test_janitor.sh -v

# Reset test environment
./test/test_janitor.sh -r
```

## Test Validation Standards

The test script validates the following functionality:

1. **Configuration Loading**: Verify configuration file is loaded correctly
2. **Disk Threshold Check**: Verify trigger and target threshold logic
3. **File Time Filtering**: Verify only files exceeding retention time are deleted
4. **Batch Processing**: Verify file deletion count control per round
5. **Directory Priority**: Verify directories are processed in configured order
6. **Log Output**: Verify detailed operation logs

## Security Considerations

1. **Backup Important Data**: Ensure important data is backed up before using in production
2. **Test Configuration**: Recommend validating configuration parameters in test environment first
3. **Use Dry Run**: Recommend using `-d` parameter for dry run on first use
4. **Monitor Logs**: Regularly check cleanup logs to ensure script is working properly
5. **Permission Control**: Ensure script can only access specified temporary directories

## Deployment Recommendations

### System Service Deployment

1. **Copy scripts to system directory**:
   ```bash
   sudo cp janitor.sh /usr/local/bin/
   sudo cp janitor.conf.template /etc/janitor.conf
   sudo chmod +x /usr/local/bin/janitor.sh
   ```

2. **Create systemd service**:
   ```bash
   sudo tee /etc/systemd/system/janitor.service << EOF
   [Unit]
   Description=Temporary Files Cleaner
   After=multi-user.target

   [Service]
   Type=oneshot
   ExecStart=/usr/local/bin/janitor.sh
   User=root

   [Install]
   WantedBy=multi-user.target
   EOF
   ```

3. **Create timer**:
   ```bash
   sudo tee /etc/systemd/system/janitor.timer << EOF
   [Unit]
   Description=Run Temporary Files Cleaner every hour
   Requires=janitor.service

   [Timer]
   OnCalendar=hourly
   Persistent=true

   [Install]
   WantedBy=timers.target
   EOF
   ```

4. **Enable service**:
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable janitor.timer
   sudo systemctl start janitor.timer
   ```

### Cron Deployment

```bash
# Run every hour
0 * * * * /usr/local/bin/janitor.sh >/var/log/temp-cleaner.log 2>&1
```

## Troubleshooting

### Common Issues

1. **Insufficient Permissions**: Ensure script has sufficient permissions to access target directories
2. **Configuration File Not Found**: Check if configuration file path is correct
3. **Insufficient Disk Space**: If disk is full, may need to manually clean some files first
4. **Find Command Compatibility**: Some systems may have different find command parameters
5. **Path Does Not Exist**: The script now handles non-existent paths gracefully and will log appropriate error messages

### Debugging Methods

1. **Use Dry Run Mode**: `./janitor.sh -d -v`
2. **Check Log Output**: Review detailed execution logs
3. **Manual Testing**: Use test tools to verify functionality
4. **Check Disk Usage**: `df -h /`

## License

This script is released under the MIT License and can be freely used and modified.

## Contributing

Welcome to submit issue reports and improvement suggestions!
