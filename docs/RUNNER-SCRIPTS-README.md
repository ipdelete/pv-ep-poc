# Storage Test Runner Scripts

This directory contains two runner scripts that execute the storage access test on the Azure VM remotely.

## Scripts Overview

### 1. `run-storage-test.sh` - Simple Runner
A straightforward script that runs the storage access test with default settings.

**Features:**
- ✅ Simple execution with no parameters
- ✅ Detailed output and progress indicators
- ✅ Comprehensive validation checks
- ✅ User-friendly error messages

**Usage:**
```bash
./run-storage-test.sh
```

### 2. `run-storage-test-advanced.sh` - Advanced Runner
A feature-rich script with command-line options and customization capabilities.

**Features:**
- ✅ Command-line parameter support
- ✅ Quiet mode for automation
- ✅ Custom resource group and VM names
- ✅ Execution timing and detailed summaries
- ✅ Help documentation

**Usage:**
```bash
# Run with default settings
./run-storage-test-advanced.sh

# Use custom resource group and VM
./run-storage-test-advanced.sh -g my-rg -v my-vm

# Run in quiet mode (minimal output)
./run-storage-test-advanced.sh --quiet

# Show help
./run-storage-test-advanced.sh --help
```

## What These Scripts Do

Both runner scripts perform the same core functionality:

1. **🔍 Validation Checks:**
   - Verify test script exists locally
   - Check Azure CLI availability
   - Validate Azure authentication
   - Confirm VM is running

2. **🚀 Remote Execution:**
   - Use `az vm run-command invoke` to execute the test script on the VM
   - Stream the output back to the local terminal
   - Provide execution status and timing

3. **📊 Result Summary:**
   - Display test results
   - Show execution duration
   - Provide helpful tips for next steps

## Prerequisites

- ✅ Azure CLI installed and configured
- ✅ Authenticated to Azure (`az login`)
- ✅ VM must be running and accessible
- ✅ Test script (`test-storage-access.sh`) in same directory

## Example Output

### Simple Runner
```
=======================================================
Azure Storage Test Runner
=======================================================

📋 Configuration:
   Resource Group: rg-stgdemo-poc-eastus2-01
   VM Name: vm-stgdemo-poc-eastus2-01
   Test Script: test-storage-access.sh

✅ Test script found: test-storage-access.sh
✅ Azure CLI found
✅ Logged in to Azure subscription: My Subscription
✅ VM is running and accessible

🚀 Executing storage access test on VM...
   This may take a few moments...

=======================================================
VM TEST OUTPUT:
=======================================================
[Test output appears here...]

=======================================================
✅ Test execution completed successfully!
=======================================================
```

### Advanced Runner (Quiet Mode)
```
🚀 Executing storage access test on VM...
✅ Test execution completed successfully! (Duration: 63s)
```

## Command Line Options (Advanced Script)

| Option | Description | Default |
|--------|-------------|---------|
| `-g, --resource-group` | Resource group name | `rg-stgdemo-poc-eastus2-01` |
| `-v, --vm-name` | Virtual machine name | `vm-stgdemo-poc-eastus2-01` |
| `-s, --script` | Test script filename | `test-storage-access.sh` |
| `-q, --quiet` | Minimal output mode | `false` |
| `-h, --help` | Show help message | - |

## Error Handling

Both scripts include comprehensive error handling for common scenarios:

- ❌ Test script not found
- ❌ Azure CLI not installed
- ❌ Not logged in to Azure
- ❌ VM not running or not found
- ❌ Test execution failure

## Use Cases

### Development and Testing
Use the simple runner for interactive development and debugging:
```bash
./run-storage-test.sh
```

### Automation and CI/CD
Use the advanced runner in quiet mode for automated testing:
```bash
./run-storage-test-advanced.sh --quiet
```

### Custom Environments
Use the advanced runner with custom parameters for different environments:
```bash
./run-storage-test-advanced.sh \
  --resource-group rg-prod-storage \
  --vm-name vm-test-prod-01
```

## Integration Examples

### Bash Script Integration
```bash
#!/bin/bash
echo "Running storage tests..."
if ./run-storage-test-advanced.sh --quiet; then
    echo "✅ Storage tests passed"
else
    echo "❌ Storage tests failed"
    exit 1
fi
```

### Azure DevOps Pipeline
```yaml
- task: AzureCLI@2
  displayName: 'Run Storage Tests'
  inputs:
    azureSubscription: 'MyServiceConnection'
    scriptType: 'bash'
    scriptLocation: 'scriptPath'
    scriptPath: './run-storage-test-advanced.sh'
    arguments: '--quiet'
```

### GitHub Actions
```yaml
- name: Run Storage Tests
  run: |
    chmod +x ./run-storage-test-advanced.sh
    ./run-storage-test-advanced.sh --quiet
```

## Troubleshooting

### Common Issues

1. **Script not executable**
   ```bash
   chmod +x run-storage-test.sh
   chmod +x run-storage-test-advanced.sh
   ```

2. **VM not running**
   ```bash
   az vm start --resource-group rg-name --name vm-name
   ```

3. **Authentication issues**
   ```bash
   az login
   az account set --subscription "subscription-name"
   ```

4. **Permission issues**
   - Ensure your Azure account has VM Contributor role
   - Verify the VM has the run-command extension enabled

## Best Practices

- ✅ Run tests in a non-production environment first
- ✅ Use quiet mode for automated scripts
- ✅ Monitor execution time for performance baseline
- ✅ Keep test scripts and runners in version control
- ✅ Regular testing to validate ongoing functionality

These runner scripts provide a convenient and reliable way to execute storage access tests remotely on your Azure VMs, supporting both interactive and automated use cases.
