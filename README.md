# gitpyup
A set of PowerShell scripts to automate deployment of python applications. The automation includes cloning of application repos, installation of Miniforge, and setting up conda environments for each application.

## use cases
* non-coders
* many devices
* users need to update often

## End user usage (developers keep going)
1. Download 3 files, *.bat, *.yml, *.ps1 All files must be in the same folder and not in a zip.
2. Right click run-elevated-firse.bat and click 'Run with Elevated Privileges' or 'Run as Administrator', allow elevation when prompted
3. Right click *.ps1 and click 'Run with PowerShell', allow  elevation when prompted and follow the prompts

## Requirements
* Operating system: Windows 10 or 11
* Internet connection during installation/update
* Disk used: varies by application but minimum ~2GB

## Features
### Features for everyone
* Installs python optimized for enterprise environments (miniforge-cost,versatility,reproduceability)
* Attempts to fix “SSL certificate verify failed” for conda and pip

### Features for end-users
* Update via start menu shortcut
* Simple: download 3 files, run 1 with admin privileges 
* Start menu shortcuts
* Multi-user installation option
* Don’t need github access
* Use for multiple apps (each gets own conda environment)
* No GUI, headless/remote installs possible

### Features for python app developers
* Updates distributed via git (uses git cli, so not tied to github.com)
* Use SSH (deploy) keys to access private repos
* No compiling or bundling
* Optionally install National Instruments drivers
* Environment file autodetect: priority highest to lowest - environment.yml > setup.py/pyproject.toml > requirements.txt
* Detects developer install: uses existing git repos

## Developer Usage

### Deploy Application(s)
1. if application repos is private, generate read-only deploy key for your application repo
2. (optional) add gitpyup.yml to your application repo(s) to generate shortcuts and or set the environment file

```yml
# example contents of optional gitpyup.yml in root of application repo
environment_file: setup.py  # specify to override autodetect
shortcuts:  # generate shortcuts
  - name: myconsolescript
    command: conda run -n <app name> <console script> # e.g. conda run -n plotme plotme
    target: powershell.exe  # (optional) default is powershell.exe
  - name: myscript
    target: powershell.exe
    script: myscript.ps1
```

3. create config file: yourAppName.yml

* In this example plotme is the only application.  Application order doesn't matter.
```yml
# <your app name>.yml - name is up to you
applications:
# optional, gitpyup can be placed here to override the default that is in Deploy-gitpyup.ps1
  - name: gitpyup
    clone_uri: git@github.com:3Mcloud/gitpyup.git
    deploy_key: "replace with deploy key if needed"
  - name: plotme
    clone_uri: git@github.com:3mcloud/plotme.git
    # example key format
    deploy_key: |-
      -----BEGIN OPENSSH PRIVATE KEY-----
      **********************************************
      **********************************************
      -----END OPENSSH PRIVATE KEY-----
```

4. upload 3 files somewhere your users can access
    1. Deploy-gitpyup.ps1
    2. yourAppName.yml
    3. run-elevated-first.bat

## Script Descriptions
* gitpyup/Deploy-gitpyup.ps1 - Initial setup and updates, clones repos, creates shortcuts
* gitpyup/Setup-Python.ps1 - Installs/updates Miniforge
* gitpyup/Setup-Application.ps1 - Creates/updates application  environments
* gitpyup/Uninstall-gitpyup.ps1 - Removes start menu shortcuts, cloned repos
* gitpyup/run-elevated-first.bat - Sets PowerShell policy and unblocks Deploy-gitpyup.ps1

### Standalone Modules
* gitpyup/Setup-NationalInstruments.ps1 - modify $packages array to add or remove packages, run with elevated priveleges

## FAQ 


## Contributing

### Ideas in priority order
1. Tests
1. NoPrompt flag for non-interactive install so it can be used in CI/CD pipelines, add currently interactive configuration options to yourappname.yml
1. Convert to powershell module and publish to PowerShell Gallery
1. Modify Setup-Python.ps1 so it can be used standalone
1. share conda environment between multiple applications via application.yml or gitpyup.yml
1. allow customization of National Instruments packages via gitpyup.yml
1. support additional WinGet packages via gitpyup.yml

### Development Guidelines
* https://learn.microsoft.com/en-us/powershell/scripting/developer/cmdlet/strongly-encouraged-development-guidelines
* https://powershellfaqs.com/powershell-naming-conventions/


