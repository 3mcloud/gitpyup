# gitpyup
A set of PowerShell scripts to automate deployment of python applications to non-coders.

## End user usage (developers keep going)
1. Download 3 files, *.bat, *.yml, *.ps1 All files must be in the same folder and not in a zip.
1. Right click run-elevated-firse.bat and click 'Run with Elevated Privileges' or 'Run as Administrator', allow elevation when prompted
1. Right click *.ps1 and click 'Run with PowerShell', allow  elevation when prompted and follow the prompts

## features
### Features for everyone
* Installs python optimally for 3M python applications
* Fixes “SSL certificate verify failed” for conda and pip

### Features for end-users
* Update via start menu shortcut
* Simple: download 3 files, run 1 with admin privileges 
* Start menu shortcuts
* Multi-user installation option
* Don’t need github access
* Use for multiple apps (each gets own conda environment)

### Features for python app developers
* Updates distributed via git (uses git cli, so not tied to github.com)
* Use SSH (deploy) keys to access private repos
* No compiling or bundling
* Optionally install National Instruments drivers
* Environment file autodetect: priority highest to lowest - environment.yml > setup.py > requirements.txt

## Developer Usage

### Deploy Application(s)
1. generate read-only deploy key for your application repo
2. generate yourself or request deploy key for gitpyup from Milo
3. (optional) add gitpyup.yml to your application repo(s) to generate shortcuts and or set the environment file

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

4. create config file: yourAppName.yml

* In this example plotme is the application.  The gitpyup application is allways included. Application order doesn't matter.
```yml
# <your app name>.yml - name is up to you
applications:
  - name: gitpyup
    clone_uri: git@github.com:3M-Cloud/gitpyup.git
    deploy_key: "replace with deploy key if needed"
  - name: plotme
    clone_uri: git@github.com:3mcloud/plotme.git
    deploy_key: "replace with deploy key if needed"
```

5. upload 3 files somewhere your users can access
    1. Deploy-gitpyup.ps1
    2. yourAppName.yml
    3. run-elevated-first.bat

### Standalone Modules
* Setup-NationalInstruments.ps1 - modify $packages array to add or remove packages, run with elevated priveleges

## FAQ 


## Contributing

### Development Guidelines
* https://learn.microsoft.com/en-us/powershell/scripting/developer/cmdlet/strongly-encouraged-development-guidelines
* https://powershellfaqs.com/powershell-naming-conventions/


