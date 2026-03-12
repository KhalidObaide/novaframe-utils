# Phase 1 Enhancements

Two final enhancements completed before moving to Phase 2:

## 1. IP Management UI

Added comprehensive IP pool management to the hardware detail page (`/hardware/[id]`).

### Features
- **View all IPs**: Table showing all IPs assigned to the hardware server
- **Add single IP**: Modal to add a single IP address to the pool
- **Add IP range**: Modal to add multiple IPs at once (e.g., 192.168.1.10-20)
- **Delete IP**: Remove available IPs from the pool (assigned IPs cannot be deleted)
- **Status indicators**: Visual feedback for available vs. assigned IPs

### UI Location
The IP Pool section appears below the Container table on the hardware detail page.

### Usage
1. Navigate to a hardware server detail page
2. Click "+ Add IP" to open the modal
3. Choose between "Single IP" or "IP Range" mode
4. Enter the IP address(es) and submit
5. IPs will appear in the table below
6. Delete available IPs by clicking the "Delete" button

## 2. ZFS Storage for Disk Quotas

Updated `setup-vds.sh` to use ZFS storage backend instead of `dir` to enable disk quota enforcement.

### Changes Made

#### System Dependencies
Added `zfsutils-linux` package to the installation list.

#### LXD Storage Pool
Changed from:
```yaml
storage_pools:
- config: {}
  name: default
  driver: dir
```

To:
```yaml
storage_pools:
- config:
    size: ${ZFS_SIZE_GB}GB  # Dynamically calculated: available_space - 10GB headroom
  name: default
  driver: zfs
```

The script now automatically calculates the optimal ZFS pool size based on available disk space, reserving 10GB for VDS operations.

### Benefits
- **Disk quotas enforced**: Containers now respect the disk limit specified during creation
- **Better isolation**: Each container has its own ZFS dataset
- **Snapshots support**: ZFS enables future snapshot/backup features
- **Better performance**: Copy-on-write filesystem optimized for virtualization

### Verification
After creating a container with a specific disk limit (e.g., 40GB), run:
```bash
lxc exec container-name -- df -h
```

The root filesystem (`/`) should now show the specified limit instead of the full VDS storage.

### Hardware Controller Compatibility
The hardware-controller already handles this correctly. The disk limit logic in `services/lxd.py` (lines 159-164) checks the storage driver:
```python
if disk:
    driver = _get_storage_driver()
    if driver != "dir":
        _run(f"lxc config device override {name} root size={disk}")
```

With ZFS, the condition passes and disk limits are applied.

## Setup for New VDS

When setting up a new VDS, simply run the updated script:
```bash
bash setup-vds.sh --api-key 'YOUR_SECRET' --github-token 'ghp_xxx'
```

The script will:
1. Install ZFS utilities
2. Initialize LXD with ZFS storage pool
3. Set up networking, nginx, and the hardware-controller service

## Migration for Existing VDS

If you have an existing VDS using `dir` storage, you'll need to:
1. Back up any existing containers
2. Reinitialize LXD with ZFS
3. Recreate containers

**Note**: This is destructive and should only be done on test systems or during planned maintenance.

## Next Steps

With these enhancements complete, we're ready to proceed to Phase 2: Customer-facing Dashboard.
