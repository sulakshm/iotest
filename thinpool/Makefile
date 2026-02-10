# LVM Thin Pool Stress Test - Makefile
#
# Common operations for thin pool stress testing
#

.PHONY: help install check clean test-quick test-standard test-stress analyze

# Default target
help:
	@echo "LVM Thin Pool Stress Test - Available Targets"
	@echo ""
	@echo "Setup:"
	@echo "  make install        - Install required dependencies"
	@echo "  make check          - Check system requirements"
	@echo "  make permissions    - Make scripts executable"
	@echo ""
	@echo "Testing:"
	@echo "  make test-quick     - Run quick 30-minute test"
	@echo "  make test-standard  - Run standard 4-hour test"
	@echo "  make test-stress    - Run high stress 8-hour test"
	@echo "  make test-custom    - Run with custom parameters"
	@echo ""
	@echo "Analysis:"
	@echo "  make analyze        - Analyze latest test logs"
	@echo "  make report         - Generate detailed report"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean          - Remove log files"
	@echo "  make clean-lvm      - Emergency LVM cleanup"
	@echo ""
	@echo "Environment Variables:"
	@echo "  DRIVES              - Drives to use (e.g., /dev/sdb,/dev/sdc)"
	@echo "  PARALLEL            - Parallel deletes (default: 4)"
	@echo "  HOURS               - Max hours (default: 4)"
	@echo "  ITERATIONS          - Max iterations (default: 0)"
	@echo "  VOLUMES             - Number of volumes (default: 16)"
	@echo "  MODE                - Volume mode: raw or formatted (default: raw)"
	@echo ""

# Install dependencies
install:
	@echo "Installing dependencies..."
	@if command -v apt-get >/dev/null 2>&1; then \
		sudo apt-get update && sudo apt-get install -y lvm2 fio util-linux; \
	elif command -v yum >/dev/null 2>&1; then \
		sudo yum install -y lvm2 fio util-linux; \
	else \
		echo "Error: Package manager not found. Please install manually."; \
		exit 1; \
	fi
	@echo "Dependencies installed successfully"

# Check system requirements
check:
	@echo "Checking system requirements..."
	@echo -n "LVM2: "
	@command -v lvm >/dev/null 2>&1 && echo "✓ Installed" || echo "✗ Not found"
	@echo -n "FIO: "
	@command -v fio >/dev/null 2>&1 && echo "✓ Installed" || echo "✗ Not found"
	@echo -n "blkdiscard: "
	@command -v blkdiscard >/dev/null 2>&1 && echo "✓ Installed" || echo "✗ Not found"
	@echo ""
	@echo "Available block devices:"
	@lsblk -d -n -o NAME,SIZE,TYPE | grep disk || echo "No block devices found"

# Make scripts executable
permissions:
	@echo "Making scripts executable..."
	@chmod +x *.sh
	@echo "Scripts are now executable"

# Quick test (30 minutes)
test-quick:
	@if [ -z "$(DRIVES)" ]; then \
		echo "Error: DRIVES variable not set"; \
		echo "Usage: make test-quick DRIVES=/dev/sdb,/dev/sdc"; \
		exit 1; \
	fi
	@echo "Running quick test (30 minutes)..."
	sudo ./thin_pool_stress_test.sh \
		-d $(DRIVES) \
		-p 2 \
		-h 0.5 \
		-n 16 \
		-c 80 \
		-v raw

# Standard test (4 hours)
test-standard:
	@if [ -z "$(DRIVES)" ]; then \
		echo "Error: DRIVES variable not set"; \
		echo "Usage: make test-standard DRIVES=/dev/sdb,/dev/sdc"; \
		exit 1; \
	fi
	@echo "Running standard test (4 hours)..."
	sudo ./thin_pool_stress_test.sh \
		-d $(DRIVES) \
		-p $(or $(PARALLEL),4) \
		-h $(or $(HOURS),4) \
		-n $(or $(VOLUMES),16) \
		-c 80 \
		-v $(or $(MODE),raw)

# High stress test (8 hours)
test-stress:
	@if [ -z "$(DRIVES)" ]; then \
		echo "Error: DRIVES variable not set"; \
		echo "Usage: make test-stress DRIVES=/dev/sdb,/dev/sdc,/dev/sdd"; \
		exit 1; \
	fi
	@echo "Running high stress test (8 hours)..."
	sudo ./thin_pool_stress_test.sh \
		-d $(DRIVES) \
		-p 8 \
		-h 8 \
		-n 16 \
		-c 80 \
		-v raw

# Custom test
test-custom:
	@if [ -z "$(DRIVES)" ]; then \
		echo "Error: DRIVES variable not set"; \
		echo "Usage: make test-custom DRIVES=/dev/sdb,/dev/sdc PARALLEL=4 HOURS=4"; \
		exit 1; \
	fi
	@echo "Running custom test..."
	sudo ./thin_pool_stress_test.sh \
		-d $(DRIVES) \
		-p $(or $(PARALLEL),4) \
		-h $(or $(HOURS),4) \
		-i $(or $(ITERATIONS),0) \
		-n $(or $(VOLUMES),16) \
		-c $(or $(CAPACITY),50) \
		-v $(or $(MODE),raw)

# Analyze latest logs
analyze:
	@if [ ! -d "thin_pool_stress_logs" ]; then \
		echo "Error: No log directory found"; \
		exit 1; \
	fi
	@echo "Analyzing latest test logs..."
	sudo ./analyze_thin_pool_logs.sh thin_pool_stress_logs

# Generate detailed report
report: analyze
	@echo "Report generated in thin_pool_stress_logs/analysis_report.txt"
	@cat thin_pool_stress_logs/analysis_report.txt

# Clean log files
clean:
	@echo "Removing log files..."
	@rm -rf thin_pool_stress_logs
	@echo "Log files removed"

# Emergency LVM cleanup
clean-lvm:
	@echo "WARNING: This will remove ALL LVM structures for stress_vg"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		echo "Cleaning up LVM structures..."; \
		sudo pkill -9 fio 2>/dev/null || true; \
		sudo umount /mnt/thin_vol_* 2>/dev/null || true; \
		sudo lvremove -f stress_vg 2>/dev/null || true; \
		sudo vgremove -f stress_vg 2>/dev/null || true; \
		if [ -n "$(DRIVES)" ]; then \
			for drive in $$(echo $(DRIVES) | tr ',' ' '); do \
				sudo pvremove -f $$drive 2>/dev/null || true; \
			done; \
		fi; \
		echo "LVM cleanup complete"; \
	else \
		echo "Cleanup cancelled"; \
	fi

# Archive logs
archive:
	@if [ ! -d "thin_pool_stress_logs" ]; then \
		echo "Error: No log directory found"; \
		exit 1; \
	fi
	@ARCHIVE_NAME="thin_pool_logs_$$(date +%Y%m%d_%H%M%S).tar.gz"; \
	echo "Creating archive: $$ARCHIVE_NAME"; \
	tar -czf $$ARCHIVE_NAME thin_pool_stress_logs/; \
	echo "Archive created successfully"

# Show current LVM status
status:
	@echo "Current LVM Status:"
	@echo ""
	@echo "Volume Groups:"
	@sudo vgs 2>/dev/null || echo "No volume groups found"
	@echo ""
	@echo "Logical Volumes:"
	@sudo lvs 2>/dev/null || echo "No logical volumes found"
	@echo ""
	@echo "Physical Volumes:"
	@sudo pvs 2>/dev/null || echo "No physical volumes found"

