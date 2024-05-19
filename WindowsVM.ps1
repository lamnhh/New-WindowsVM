$Playbook = @'
- name: Change time display
  hosts: default
  tasks:
  - name: Change timezone
    community.windows.win_timezone:
      timezone: SE Asia Standard Time
  - name: Change region format to UK
    community.windows.win_region:
      format: en-GB
    
- name: Change hostname
  hosts: default
  tasks:
  - name: Change hostname
    ansible.windows.win_hostname:
      name: "{{hostname}}"
    register: res
  - name: Reboot
    ansible.windows.win_reboot:
    when: res.reboot_required

- name: Setup Defender
  hosts: default
  tasks:
  - name: Install windows defender
    win_feature:
      name: Windows-Defender
    register: win_defender_install
    when: is_windows_server
  - name: Reboot if needed
    win_reboot:
      reboot_timeout: 600
      post_reboot_delay: 30
    when: is_windows_server and win_defender_install.reboot_required

- name: Install Firefox
  hosts: default
  tasks:
  - name: Download Firefox MSI
    retries: 3
    ansible.windows.win_package:
      path: https://download.mozilla.org/?product=firefox-msi-latest-ssl&os=win64&lang=en-US
  - name: Create the same shortcut using environment variables
    community.windows.win_shortcut:
      description: The Mozilla Firefox web browser
      src: '%ProgramFiles%\Mozilla Firefox\Firefox.exe'
      dest: '%Public%\Desktop\Firefox.lnk'
      icon: '%ProgramFiles%\Mozilla Firefox\Firefox.exe,0'
      directory: '%ProgramFiles%\Mozilla Firefox'
      
- name: Update
  hosts: default
  tasks:
  - name: Enable update service
    ansible.windows.win_service:
      name: Windows Update
      state: started
      start_mode: auto
    when: enable_update == True
  - name: Install all updates and reboot as many times as needed
    ansible.windows.win_updates:
      reboot: yes
    when: enable_update == True
'@

function New-WindowsVM {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$Hostname,
        
        [Parameter(Mandatory=$true)]
        [ValidateSet("WS2016", "WS2019", "WS2022", "W10", "W11")]
        [string]$Version,

        [string]$Name = $Hostname,

        [switch]$EnableUpdate
    )

    $BoxNameMap = @{
        "WS2016" = @{
          "box" = "StefanScherer/windows_2016"
          "is_windows_server" = $true
        }
        "WS2019" = @{
          "box" = "StefanScherer/windows_2019"
          "is_windows_server" = $true
        }
        "WS2022" = @{
          "box" = "StefanScherer/windows_2022"
          "is_windows_server" = $true
        }
        "W10" = @{
          "box" = "StefanScherer/windows_10"
          "is_windows_server" = $false
        }
        "W11" = @{
          "box" = "StefanScherer/windows_11"
          "is_windows_server" = $false
        }
    }
    $BoxName = $BoxNameMap[$Version]["box"]
    $IsWindowsServer = $BoxNameMap[$Version]["is_windows_server"]

    $TargetPath = "$env:USERPROFILE\Documents\Virtual Machines\$Name"
    New-Item -ItemType Directory -Force -Path $TargetPath | Out-Null
    Set-Location $TargetPath

    Write-Output "ipconfig" | Out-File -FilePath "get-ip.ps1" -Encoding utf8
    Write-Output @"
Vagrant.configure("2") do |config|
  config.vm.define "$Name"
  config.vm.box = "$BoxName"
#  config.vm.synced_folder '.', '/vagrant', disabled: true
  config.vm.network "forwarded_port", guest: 3389, host: 3389, id: 'rdp', auto_correct: true, disabled: true
  config.vm.network "forwarded_port", guest: 22, host: 2222, id: 'ssh', auto_correct: true, disabled: true
  config.vm.provision :shell, :path => "get-ip.ps1", privileged: false
end
"@ | Out-File -FilePath "Vagrantfile" -Encoding utf8

    $IP = ""
    vagrant up | ForEach-Object {
      $line = $_
      if ($line.Contains("IPv4")) {
        $IP = $line.Split(":")[-1].trim()
      }
      $line
    }

    Write-Output @"
[default]
$Name ansible_host=$IP hostname=$Hostname enable_update=$EnableUpdate is_windows_server=$IsWindowsServer

[all:vars]
ansible_user=vagrant
ansible_password=vagrant
ansible_connection=winrm
ansible_winrm_transport=basic
ansible_port=5985
ansible_winrm_server_cert_validation=ignore
ansible_winrm_operation_timeout_sec=400
ansible_winrm_read_timeout_sec=500
"@ | Out-File -FilePath inventory -Encoding ascii
    Write-Output $Playbook | Out-File -FilePath playbook.yml -Encoding ascii
    wsl ~/.local/bin/ansible-playbook -i inventory playbook.yml
}

New-WindowsVM -Hostname TEST7 -Version W11 -EnableUpdate