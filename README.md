# Windows Server 2022 Automated Pipeline for OpenShift Virtualization

This repository contains an automated pipeline for building Windows Server 2022 golden images for OpenShift Virtualization (KubeVirt) using Tekton Pipelines.

## Overview

This pipeline uses the **KubeVirt Windows EFI Installer** pipeline to create fully automated, sysprepped Windows Server 2022 images with:
-  VirtIO drivers pre-installed
-  WinRM configured for Ansible management
-  EFI boot support
-  Automatic sysprep and shutdown
-  Ready-to-use DataSource for VM deployment

## Files in this Repository

| File | Description |
|------|-------------|
| `windows-efi-installer.yaml` | Main Tekton pipeline from KubeVirt project |
| `pipelinerun-windows-efi-installer.yaml` | Example PipelineRun configuration |
| `autounattend-with-winrm.xml` | Windows unattended installation file with WinRM pre-configured |
| `post-install.ps1` | PowerShell script for WinRM configuration and final setup |
| `serviceaccount-pipeline.yaml` | ServiceAccount with necessary RBAC permissions |

## Prerequisites

### Required Components
1. **OpenShift 4.x** cluster with admin access
2. **OpenShift Virtualization** (KubeVirt) installed and running
3. **OpenShift Pipelines** (Tekton) installed
4. **Persistent Storage** with at least 100Gi available
5. **CLI Tools**:
   - `oc` (logged in to cluster)
   - `virtctl` (optional, for VM console access)
   - `tkn` (optional, for easier pipeline management)

### Storage Requirements
- Windows ISO download: ~9Gi
- Base DataVolume (root disk): 50Gi
- Temporary workspace: ~20Gi
- **Total**: ~80Gi per build

### Network Access
- Microsoft download servers (for Windows ISO)
- Fedora servers (for VirtIO drivers container image)
- GitHub (for downloading default autounattend ConfigMaps - though we override this)

## Architecture

### How It Works

```
Start Pipeline → Download Windows ISO → Create Root Disk →
Modify ISO for EFI → Create VM → Install Windows →
Run post-install.ps1 → Sysprep & Shutdown →
Create DataSource → Cleanup
```

### Key Features

1. **Fully Automated**: No manual intervention required
2. **EFI Boot**: Modern UEFI boot support
3. **VirtIO Drivers**: Injected automatically from container disk
4. **WinRM Ready**: Configured during installation for Ansible
5. **Sysprepped**: Image is generalized and ready for cloning

## Installation

### Step 1: Namespace

```bash
# Set as current project
oc project openshift-virtualization-os-images
```

### Step 2: Create ServiceAccount

```bash
# Apply ServiceAccount with proper RBAC permissions
oc apply -f serviceaccount-pipeline.yaml
```

### Step 3: Create ConfigMap for autounattend.xml

The pipeline expects a ConfigMap containing the Windows unattended installation file.

```bash
# Delete the ConfigMap if it exists
oc delete configmap windows2022-autounattend -n openshift-virtualization-os-images --ignore-not-found

# Create combined ConfigMap with both autounattend.xml and post-install.ps1
oc create configmap windows2022-autounattend \
  --from-file=autounattend.xml=autounattend-with-winrm.xml \
  --from-file=post-install.ps1=post-install.ps1 \
  -n openshift-virtualization-os-images
```

**Note**: The autounattend.xml references `post-install.ps1` from drive F:, which will be mounted from this ConfigMap.

### Step 4: Apply Pipeline

```bash
# Apply the KubeVirt Windows EFI installer pipeline
oc apply -f windows-efi-installer.yaml
```

Verify the pipeline was created:

```bash
oc get pipeline windows-efi-installer -n openshift-virtualization-os-images
```

## Running the Pipeline

### Option 1: Using the Example PipelineRun

1. **Get Windows Server 2022 ISO URL**

   You'll need a valid download URL. Options:
   - **Microsoft Evaluation Center**: https://www.microsoft.com/en-us/evalcenter/download-windows-server-2022 (link expires in 24 hours)
   - **Volume License Service Center** (if you have licenses)
   - **Your own web server** with uploaded ISO

2. **Edit the PipelineRun**

   Update the `winImageDownloadURL` in `pipelinerun-windows-efi-installer.yaml`:

   ```yaml
   - name: winImageDownloadURL
     value: "YOUR_WINDOWS_ISO_URL_HERE"
   ```

3. **Update Storage Class** (if needed)

   The example uses `lvms-nvme-vg-immediate`. Change to your storage class:

   ```yaml
   - name: storageClassName
     value: "your-storage-class"
   ```

4. **Run the Pipeline**

   ```bash
   oc create -f pipelinerun-windows-efi-installer.yaml
   ```

### Option 2: Using kubectl/oc directly

```bash
oc create -f - <<EOF
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: windows2022-install-
  namespace: openshift-virtualization-os-images
spec:
  pipelineRef:
    name: windows-efi-installer
  params:
    - name: winImageDownloadURL
      value: "YOUR_WINDOWS_ISO_URL"
    - name: acceptEula
      value: "true"
    - name: autounattendConfigMapName
      value: "windows2022-autounattend"
    - name: baseDvName
      value: "win2k22"
    - name: isoDVName
      value: "win2k22-installer-iso"
    - name: instanceTypeName
      value: "u1.large"
    - name: instanceTypeKind
      value: "VirtualMachineClusterInstancetype"
    - name: preferenceName
      value: "windows.2k22.virtio"
    - name: virtualMachinePreferenceKind
      value: "VirtualMachineClusterPreference"
    - name: storageClassName
      value: "lvms-nvme-vg-immediate"
EOF
```

### Option 3: Using tkn CLI

```bash
tkn pipeline start windows-efi-installer \
  -p winImageDownloadURL="YOUR_WINDOWS_ISO_URL" \
  -p acceptEula=true \
  -p autounattendConfigMapName=windows2022-autounattend \
  -p baseDvName=win2k22 \
  -p isoDVName=win2k22-installer-iso \
  -p instanceTypeName=u1.large \
  -p instanceTypeKind=VirtualMachineClusterInstancetype \
  -p preferenceName=windows.2k22.virtio \
  -p virtualMachinePreferenceKind=VirtualMachineClusterPreference \
  -p storageClassName=lvms-nvme-vg-immediate \
  -n openshift-virtualization-os-images \
  --showlog
```

## Monitoring the Pipeline

### Watch Pipeline Progress

```bash
# List all pipeline runs
oc get pipelinerun -n openshift-virtualization-os-images

# Watch logs with tkn
tkn pipelinerun logs -f -n openshift-virtualization-os-images

# Or watch logs with oc
oc logs -f <pipelinerun-pod-name> -n openshift-virtualization-os-images
```

### View in OpenShift Console

Navigate to: **Pipelines → PipelineRuns** in the OpenShift web console.

### Monitor the Installer VM

During installation, a temporary VM is created:

```bash
# List VMs
oc get vm -n openshift-virtualization-os-images

# Watch VM console (requires virtctl)
virtctl vnc <vm-name> -n openshift-virtualization-os-images
```

### Expected Timeline

- **ISO Download**: 5-10 minutes (depends on connection speed)
- **Windows Installation**: 20-30 minutes
- **Post-install & WinRM config**: 2-5 minutes
- **Sysprep**: 5-10 minutes
- **Total**: ~45-60 minutes

## Post-Installation

### Verify the DataSource

After the pipeline completes successfully:

```bash
# Check DataSource was created
oc get datasource win2k22 -n openshift-virtualization-os-images

# Check the PVC
oc get pvc win2k22 -n openshift-virtualization-os-images

# View details
oc describe datasource win2k22 -n openshift-virtualization-os-images
```

### Deploy a Test VM

Create a VM from the golden image:

```bash
oc apply -f - <<EOF
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: win2k22-test
  namespace: default
spec:
  running: true
  template:
    metadata:
      labels:
        kubevirt.io/vm: win2k22-test
    spec:
      domain:
        cpu:
          cores: 2
        devices:
          disks:
            - name: rootdisk
              disk:
                bus: virtio
          interfaces:
            - name: default
              masquerade: {}
        memory:
          guest: 4Gi
      networks:
        - name: default
          pod: {}
      volumes:
        - name: rootdisk
          dataVolume:
            name: win2k22-test-disk
---
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: win2k22-test-disk
  namespace: default
spec:
  source:
    pvc:
      name: win2k22
      namespace: openshift-virtualization-os-images
  storage:
    resources:
      requests:
        storage: 50Gi
    storageClassName: lvms-nvme-vg-immediate
EOF
```

### Test WinRM Connectivity

```bash
# Get VM IP address
VM_IP=$(oc get vmi win2k22-test -n default -o jsonpath='{.status.interfaces[0].ipAddress}')

echo "VM IP: $VM_IP"

# Test with Ansible (requires ansible and pywinrm installed)
ansible all -i "$VM_IP," -m win_ping \
  -e "ansible_connection=winrm" \
  -e "ansible_user=Administrator" \
  -e "ansible_password=p3zdh4t1!" \
  -e "ansible_winrm_transport=basic" \
  -e "ansible_winrm_server_cert_validation=ignore"
```

## Configuration Details

### Default Administrator Credentials

**Username**: `Administrator`
**Password**: `r3dh4t1!` (base64 encoded in autounattend-with-winrm.xml)

⚠️ **IMPORTANT**: Change this password after deployment or before building the image!

### Locale Settings

The image is configured with:
- **UI Language**: English (US)
- **System Locale**: Swedish (Sweden)
- **Input Locale**: Swedish keyboard
- **Time Zone**: W. Europe Standard Time (Stockholm)

### WinRM Configuration

The image comes pre-configured with:
-  WinRM HTTP listener on port 5985
-  Basic Authentication enabled
-  Unencrypted traffic allowed
-  PowerShell RemoteSigned execution policy
-  Firewall rules configured

### Network Settings

- **Remote Desktop**: Enabled (firewall rule added)
- **WinRM**: Enabled (firewall rule added)
- **Computer Name**: Auto-generated random name

## Customization

### Change Administrator Password

1. Edit `autounattend-with-winrm.xml`
2. Find the `<AdministratorPassword>` section:
   ```xml
   <AdministratorPassword>
       <Value>cgAzAGQAaAA0AHQAMQAhAA==</Value>
       <PlainText>false</PlainText>
   </AdministratorPassword>
   ```
3. Encode your password to base64:
   ```bash
   echo -n 'YourPassword' | iconv -t UTF-16LE | base64
   ```
4. Replace the `<Value>` with your encoded password
5. Recreate the ConfigMap

### Change Locale Settings

Edit `autounattend-with-winrm.xml` and modify:
- `<InputLocale>` - Keyboard layout
- `<SystemLocale>` - System locale for non-Unicode programs
- `<UILanguage>` - Display language
- `<UserLocale>` - Regional format (date, time, currency)
- `<TimeZone>` - System timezone

### Add Additional Software

Edit `post-install.ps1` and add installation commands before the sysprep section:

```powershell
# Example: Install Chocolatey
Write-Host "Installing Chocolatey..."
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))

# Example: Install software via Chocolatey
choco install -y firefox
choco install -y 7zip
```

### Modify VM Resources

Edit the PipelineRun parameters:
- `instanceTypeName`: Change VM size (u1.small, u1.medium, u1.large, etc.)
- Storage size is configured in the pipeline (default 50Gi)

## Troubleshooting

### Pipeline Fails: "efisys_noprompt.bin not found"

**Cause**: Older Windows Server 2022 ISOs don't have EFI no-prompt boot files.

**Solution**: Download the latest Windows Server 2022 ISO from Microsoft.

### Pipeline Fails: ServiceAccount Permissions

**Cause**: ServiceAccount doesn't have proper RBAC permissions.

**Solution**:
```bash
# Verify ServiceAccount exists
oc get sa pipeline -n openshift-virtualization-os-images

# Verify RoleBindings
oc get rolebinding -n openshift-virtualization-os-images | grep pipeline

# Reapply if needed
oc apply -f serviceaccount-pipeline.yaml
```

### ISO Download Fails or Times Out

**Cause**:
- Microsoft evaluation URLs expire after 24 hours
- Network connectivity issues
- ISO file too large for default timeout

**Solution**:
- Get a fresh download URL from Microsoft
- Upload ISO to your own web server with reliable connectivity
- Or pre-upload ISO to a PVC and modify pipeline to use existing PVC

### VM Installation Takes Too Long (>2 hours)

**Cause**: Pipeline has a 2-hour timeout for installation.

**Solution**: This is normal for Windows installation. If it fails:
1. Check VM console to see where it's stuck
2. Verify network connectivity for Windows Update downloads
3. Consider disabling Windows Updates in autounattend.xml to speed up

### Cannot Connect to VM via WinRM

**Checklist**:
1.  VM is fully booted (wait 5 minutes after VM shows Running)
2.  VM has an IP address: `oc get vmi <vm-name> -o jsonpath='{.status.interfaces[0].ipAddress}'`
3.  WinRM port 5985 is accessible
4.  Using correct credentials (Administrator / p3zdh4t1!)
5.  Ansible is using `winrm` connection and `basic` auth

**Test manually**:
```bash
# Install test tools
pip install pywinrm

# Create test script
cat > test_winrm.py <<'EOF'
import winrm

s = winrm.Session('http://VM_IP:5985/wsman', auth=('Administrator', 'p3zdh4t1!'), transport='basic', server_cert_validation='ignore')
r = s.run_cmd('ipconfig')
print(r.std_out.decode())
EOF

python test_winrm.py
```

### Pipeline Succeeds but DataSource Not Created

**Cause**: DataSource creation might have failed in the final step.

**Solution**: Manually create the DataSource:
```bash
oc apply -f - <<EOF
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataSource
metadata:
  name: win2k22
  namespace: openshift-virtualization-os-images
spec:
  source:
    pvc:
      name: win2k22
      namespace: openshift-virtualization-os-images
EOF
```

## Security Considerations

⚠️ **WARNING**: This configuration is designed for **lab/development environments**.

### Current Security Settings (NOT for Production)
-  Basic Authentication enabled (credentials sent in base64)
-  Unencrypted WinRM (HTTP, not HTTPS)
-  Simple default password
-  Firewall configured to allow all WinRM traffic
-  UAC in audit mode during setup

### Production Hardening Checklist
For production deployments, you should:

1. **Use HTTPS for WinRM**
   - Configure HTTPS listener with valid certificate
   - Disable HTTP listener
   - Update port from 5985 to 5986

2. **Use Better Authentication**
   - Enable Kerberos authentication
   - Or use certificate-based authentication
   - Disable Basic Authentication

3. **Change Default Password**
   - Use strong, unique password
   - Or integrate with Active Directory
   - Implement password rotation

4. **Harden Firewall**
   - Restrict WinRM access to specific IP ranges
   - Use network policies in Kubernetes
   - Enable Windows Firewall advanced settings

5. **Enable Security Features**
   - Enable and properly configure UAC
   - Enable Windows Defender
   - Apply latest security updates
   - Enable audit logging

6. **Regular Updates**
   - Rebuild images monthly with latest patches
   - Subscribe to Microsoft security bulletins
   - Test updates before deployment

## Maintenance

### Rebuild Images Monthly

To get the latest Windows updates:

```bash
# Run pipeline with date-stamped name
tkn pipeline start windows-efi-installer \
  -p baseDvName=win2k22-$(date +%Y%m) \
  -p winImageDownloadURL="YOUR_ISO_URL" \
  ... other params ...
```

### Clean Up Old Images

```bash
# List all Windows images
oc get pvc -n openshift-virtualization-os-images | grep win2k22

# Delete old image PVCs
oc delete pvc win2k22-202310 -n openshift-virtualization-os-images

# Also delete old DataSources if created
oc delete datasource win2k22-202310 -n openshift-virtualization-os-images
```

### Update DataSource to Latest Image

```bash
# Update DataSource to point to newest image
oc patch datasource win2k22 -n openshift-virtualization-os-images \
  --type merge \
  -p '{"spec":{"source":{"pvc":{"name":"win2k22-202311"}}}}'
```

## Additional Resources

- **OpenShift Virtualization**: https://docs.openshift.com/container-platform/latest/virt/about-virt.html
- **KubeVirt Tekton Tasks**: https://github.com/kubevirt/kubevirt-tekton-tasks
- **Windows Unattended Installation**: https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/automate-windows-setup
- **WinRM Configuration**: https://learn.microsoft.com/en-us/windows/win32/winrm/installation-and-configuration-for-windows-remote-management
- **Ansible Windows**: https://docs.ansible.com/ansible/latest/os_guide/windows_setup.html

## License

See [LICENSE](LICENSE) file for details.

**Note**: Ensure you have proper licensing for Windows Server 2022 before using this pipeline. This repository provides automation tools only; you are responsible for obtaining appropriate Microsoft licenses.

## Contributing

Feel free to open issues or submit pull requests for improvements!
