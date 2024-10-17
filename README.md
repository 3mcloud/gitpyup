# gitpyup
A set of PowerShell scripts to automate deployment of python applications to non-coders.

# status
* 10/17 - cloning gitpyup and apps works*, Python install works, *deploy key functionality WIP
* 10/2 - not ready for use yet but looking for someone to try an app deployment in the next week or so
* 9/27 - Setup-NationalInstruments.ps1 ready for stand alone use
* 9/25 - porting from [clarke](https://github.com/3M-Cloud/clarke/tree/main/scripts) begins

## End user usage
1. Download 3 files, *.bat, *.yml, *.ps1 All files must be in the same folder and not in a zip.
1. Right click run-elevated-firse.bat and click 'Run with Elevated Privileges' or 'Run as Administrator', allow elevation when prompted
1. Right click *.ps1 and click 'Run with PowerShell', allow  elevation when prompted and follow the prompts

## features
### Features for everyone
* Update via start menu shortcut
* Fixes “SSL certificate verify failed” for conda and pip

### Features for end-users
* Simple: download 3 files, run 1 with admin privileges 
* Start menu shortcuts
* Multi-user installation option
* Don’t need github access
* Use for multiple apps (each gets own conda environment)

### Features for python app developers
* No compiling or bundling
* Optionally install National Instruments drivers

## Developer Usage

### Full deployment
1. generate read-only deploy key for your application repo
1. generate yourself or request deploy key for gitpyup from Milo
2. create config file: yourAppName.yml

* in this example plotme is the application
```yml
applications:
  - name: gitpyup
    clone_uri: git@github.com:3M-Cloud/gitpyup.git
    deploy_key: "replace with deploy key"
  - name: plotme
    clone_uri: git@github.com:3mcloud/plotme.git
    deploy_key: "replace with deploy key"
```

3. upload 3 files somewhere your users can access
    1. DeployOn-*.ps1
    2. yourAppName.yml
    3. run-elevated-first.bat

### Standalone Modules
* Setup-NationalInstruments.ps1 - modify $packages array to add or remove packages, run with elevated priveleges

## FAQ 


## Contributing

### Development Guidelines
* https://learn.microsoft.com/en-us/powershell/scripting/developer/cmdlet/strongly-encouraged-development-guidelines
* https://powershellfaqs.com/powershell-naming-conventions/


