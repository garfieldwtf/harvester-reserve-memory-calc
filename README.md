# Harvester VM Memory Calculator

A powerful bash script to calculate reserved memory for Harvester virtual machines. Supports both forward calculation (VM size → reserved memory) and reverse calculation (desired guest memory → VM size).

## Features

- ✅ **Forward Calculation**: Calculate reserved memory for a given VM size
- ✅ **Reverse Calculation**: Calculate VM size needed for desired guest memory
- ✅ **Multiple Methods**: Support for auto, legacy (100MiB fixed), and ratio-based calculations
- ✅ **YAML Output**: Direct annotation output for easy copy-paste into VM configurations
- ✅ **Common Sizes**: Pre-calculated examples for common VM sizes
- ✅ **Verbose Mode**: Detailed information for advanced users
- ✅ **No Dependencies**: Only requires `bc` (available on all Linux systems)

## Quick Start

```bash
# Make the script executable
chmod +x harvester-memory-calc.sh

# Calculate for 4GB VM
./harvester-memory-calc.sh 4Gi

# Calculate VM size needed for 24GB guest memory
./harvester-memory-calc.sh --guest 24Gi
```

## Installation

### Method 1: Direct Download
```bash
wget https://github.com/garfieldwtf/harvester-reserve-memory-calc/blob/5c8efdf2b697de81d3a839d3ca61437e65cd9aeb/harvester-memory-calc.sh
chmod +x harvester-memory-calc.sh
```

### Method 2: System-wide Installation
```bash
sudo cp harvester-memory-calc.sh /usr/local/bin/harvester-memory-calc
sudo chmod +x /usr/local/bin/harvester-memory-calc
# Now use from anywhere: harvester-memory-calc 4Gi
```

### Dependencies
The script requires `bc` (basic calculator). Install it if not present:

**Ubuntu/Debian:**
```bash
sudo apt-get update && sudo apt-get install bc
```

**RHEL/CentOS:**
```bash
sudo yum install bc
```

**Fedora:**
```bash
sudo dnf install bc
```

## Usage

### Forward Calculation (VM Size → Reserved Memory)

```bash
# Basic usage
./harvester-memory-calc.sh 4Gi

# Different calculation methods
./harvester-memory-calc.sh 8GB --method legacy    # 100MiB fixed reservation
./harvester-memory-calc.sh 2Gi --method ratio     # Ratio-based calculation
./harvester-memory-calc.sh 16Gi --method auto     # Auto-select (default)

# Show only YAML annotation
./harvester-memory-calc.sh 4Gi --annotation

# Detailed information
./harvester-memory-calc.sh 8Gi --verbose
```

### Reverse Calculation (Guest Memory → VM Size)

```bash
# Calculate VM size for desired guest memory
./harvester-memory-calc.sh --guest 24Gi
./harvester-memory-calc.sh --guest 8GB --method legacy
./harvester-memory-calc.sh --guest 4Gi --annotation
./harvester-memory-calc.sh --guest 16Gi --verbose
```

### Utility Commands

```bash
# Show common VM sizes
./harvester-memory-calc.sh --list-common

# Show help
./harvester-memory-calc.sh --help
```

## Calculation Methods

### 1. Auto (Default)
- **Small VMs (<4GB)**: Uses legacy method (100MiB fixed)
- **Large VMs (≥4GB)**: Uses ratio-based method
- **Recommended** for most use cases

### 2. Legacy (100MiB Fixed)
- Reserves exactly 100MiB for QEMU overhead
- Simple and predictable
- Best for small VMs or when you need guaranteed guest memory

### 3. Ratio-based
- Uses dynamic ratios based on VM size:
  - ≤1GB: 1% overhead
  - ≤2GB: 2% overhead  
  - ≤4GB: 3% overhead
  - ≤8GB: 4% overhead
  - >8GB: 5% overhead
- More efficient for large VMs
- Matches Harvester's default behavior

## Examples

### Example 1: Basic Forward Calculation
```bash
$ ./harvester-memory-calc.sh 4Gi

FORWARD CALCULATION: VM Size -> Reserved Memory
========================================
VM Memory:       4.00 Gi
Reserved:        128.00 Mi
Guest Memory:    3.87 Gi
Method:          ratio-based
Overhead:        3.1%

YAML Annotation:
  annotations:
    harvesterhci.io/reservedMemory: "134217728"
```

### Example 2: Reverse Calculation
```bash
$ ./harvester-memory-calc.sh --guest 24Gi

REVERSE CALCULATION: Desired Guest Memory -> VM Size
========================================
Desired Guest:   24.00 Gi
Required VM:     24.75 Gi
Reserved:        792.00 Mi
Actual Guest:    24.00 Gi
Method:          ratio-based
Overhead:        3.1%

YAML Configuration:
  memory: 24.75 Gi
  annotations:
    harvesterhci.io/reservedMemory: "830472192"
```

### Example 3: YAML Annotation Only
```bash
$ ./harvester-memory-calc.sh 8Gi --annotation
harvesterhci.io/reservedMemory: "268435456"
```

### Example 4: Common Sizes Reference
```bash
$ ./harvester-memory-calc.sh --list-common

Common VM Sizes Calculation:
============================================================
  1Gi   -> Reserved: 100.00 Mi  -> Guest: 924.00 Mi
  2Gi   -> Reserved: 100.00 Mi  -> Guest: 1.90 Gi
  4Gi   -> Reserved: 128.00 Mi  -> Guest: 3.87 Gi
  8Gi   -> Reserved: 256.00 Mi  -> Guest: 7.75 Gi
  16Gi  -> Reserved: 512.00 Mi  -> Guest: 15.50 Gi
  32Gi  -> Reserved: 1.00 Gi    -> Guest: 31.00 Gi
```

## Integration with Harvester

### Using in VM YAML

**Forward Calculation (you know VM size):**
```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: my-vm
  annotations:
    harvesterhci.io/reservedMemory: "134217728"  # From script output
spec:
  template:
    spec:
      domain:
        resources:
          limits:
            memory: 4Gi
```

**Reverse Calculation (you know guest memory needed):**
```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: my-vm
  annotations:
    harvesterhci.io/reservedMemory: "830472192"  # From script output
spec:
  template:
    spec:
      domain:
        resources:
          limits:
            memory: 24.75Gi  # From script output
```

## Memory Format Support

The script supports various memory formats:

| Format | Example | Description |
|--------|---------|-------------|
| Binary | `4Gi` | Gibibytes (recommended) |
| Decimal | `4GB` | Gigabytes |
| Megabytes | `512Mi` | Mebibytes |
| Kilobytes | `1024Ki` | Kibibytes |
| Bytes | `4294967296` | Raw bytes |

**Recommendation**: Use `Gi` and `Mi` for consistency with Kubernetes.

## Troubleshooting

### Common Issues

1. **"bc: command not found"**
   ```bash
   # Install bc
   sudo apt-get install bc  # Ubuntu/Debian
   sudo yum install bc      # RHEL/CentOS
   ```

2. **"Invalid size format"**
   - Use supported formats: `4Gi`, `8GB`, `512Mi`, `2048Ki`
   - Don't include spaces: Use `4Gi` not `4 Gi`

3. **Permission denied**
   ```bash
   chmod +x harvester-memory-calc.sh
   ```

### Debug Mode

For detailed output, use verbose mode:
```bash
./harvester-memory-calc.sh 4Gi --verbose
```

## How It Works

The script implements the same logic as Harvester's virtual machine mutator webhook:

1. **Parses** memory sizes using Kubernetes-style units
2. **Calculates** reserved memory based on selected method
3. **Validates** that guest memory meets minimum requirements (10MiB)
4. **Outputs** results in human-readable and machine-readable formats

## Contributing

Contributions are welcome! Please feel free to submit pull requests or open issues for:

- Bug fixes
- New features
- Documentation improvements
- Test cases

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Related Links

- [Harvester Documentation](https://docs.harvesterhci.io/)
- [KubeVirt VirtualMachine Resources](https://kubevirt.io/user-guide/virtual_machines/virtual_hardware/)
- [Kubernetes Resource Units](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/#meaning-of-memory)

## Support

If you encounter any issues or have questions:

1. Check the [troubleshooting](#troubleshooting) section
2. Search existing [issues](https://github.com/yourusername/harvester-memory-calc/issues)
3. Open a new issue with detailed information

---

**Happy VM configuring! 🚀**
